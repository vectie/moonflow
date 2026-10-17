///|
fn workflow_payload_spec(
  ids? : Array[String] = ["root", "left", "right", "join"],
) -> Json {
  {
    "contract_id": "moonflow.workflow-payload-plan.v1",
    "records_pointer": "/jobs",
    "record_id_pointer": "/id",
    "steps": ids.map(id => {
      (
        {
          "template_work_item_id": id,
          "request_template": {
            "request_id": "unset",
            "step": "unset",
            "job": "unset",
            "data": null,
            "unchanged": { "constant": true },
          },
          "bindings": [
            {
              "target_pointer": "/request_id",
              "value_pointer": "/work_item_id",
            },
            { "target_pointer": "/step", "value_pointer": "/step_id" },
            { "target_pointer": "/job", "value_pointer": "/record_id" },
            { "target_pointer": "/data", "value_pointer": "/record/data" },
          ],
        } : Json)
    }),
  }
}

///|
fn workflow_payload_records() -> String {
  (
    #|{"jobs":[{"id":"alpha","data":{"label":"café, \"雪\"\n","values":[true,12.5,null]}},{"id":"beta","data":false}]}
  )
}

///|
fn workflow_payload_import(
  source? : Json = plan_diamond_graph(),
  spec? : Json = workflow_payload_spec(),
  records? : String = workflow_payload_records(),
) -> @moonflow.WorkflowPayloadPlanImportV1 raise {
  @moonflow.declared_plan_from_workflow_payloads_v1(
    source, spec, records, "workflow-study", "2026-07-31T00:00:00Z",
  )
}

///|
fn workflow_payload_expect_failure(
  source? : Json = plan_diamond_graph(),
  spec? : Json = workflow_payload_spec(),
  records? : String = workflow_payload_records(),
) -> Unit raise {
  try workflow_payload_import(source~, spec~, records~) catch {
    _ => ()
  } noraise {
    _ => fail("invalid workflow payload import succeeded")
  }
}

///|
test "workflow payloads materialize typed diamond workflows in record and source order" {
  let result = workflow_payload_import()
  assert_eq(result.record_ids, ["alpha", "beta"])
  assert_eq(result.items_per_record, 4)
  assert_eq(result.artifacts.length(), 8)
  assert_eq(result.draft.edits.map(edit => edit.work_item_id), [
    "alpha.root", "alpha.left", "alpha.right", "alpha.join", "beta.root", "beta.left",
    "beta.right", "beta.join",
  ])
  assert_eq(result.draft.edits[0].depends_on, [])
  assert_eq(result.draft.edits[1].depends_on, ["alpha.root"])
  assert_eq(result.draft.edits[3].depends_on, ["alpha.left", "alpha.right"])
  assert_eq(result.draft.edits[4].depends_on, [])
  assert_eq(result.draft.edits[7].depends_on, ["beta.left", "beta.right"])
  assert_eq(@json.parse(result.artifacts[2].json_text), {
    "request_id": "alpha.right",
    "step": "right",
    "job": "alpha",
    "data": { "label": "café, \"雪\"\n", "values": [true, 12.5, null] },
    "unchanged": { "constant": true },
  })
  assert_eq(@json.parse(result.artifacts[7].json_text), {
    "request_id": "beta.join",
    "step": "join",
    "job": "beta",
    "data": false,
    "unchanged": { "constant": true },
  })
  for index, artifact in result.artifacts {
    assert_eq(artifact.work_item_id, result.draft.edits[index].work_item_id)
    assert_eq(result.draft.edits[index].input_artifacts, [artifact.artifact_ref])
    assert_true(artifact.json_text.has_suffix("\n"))
    assert_eq(artifact.sha256.length(), 71)
  }
}

///|
test "workflow payloads prepare exact contracts and fresh declarations without execution" {
  let result = workflow_payload_import()
  let prepared = @moonflow.prepare_declared_plan_v1(
    result.draft,
    @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
    "2026-07-31T00:00:00Z",
  )
  let events = @moonflow.conformant_events_from_work_graph_at_v1(
    prepared.graph,
    @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
    "2026-07-31T00:00:00Z",
  )
  let run = @moonflow.replay(prepared.preparation_id, events)
  assert_eq(run.items.length(), 8)
  for item in run.items {
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.required_claim, "digital-artifact")
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
    assert_true(
      !["root", "left", "right", "join"].contains(item.declaration_id),
    )
  }
  assert_eq(
    @moonflow.decode_declared_plan_draft_v1(result.draft.to_json()),
    result.draft,
  )
  try
    @moonflow.prepare_declared_plan_v1(
      result.draft,
      @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
      "2026-08-02T00:00:00Z",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expired health unexpectedly prepared")
  }
}

///|
test "workflow payloads bind steps by ID and preserve disconnected forward topology and opaque declarations" {
  guard plan_diamond_graph() is Object(source) &&
    source["items"] is Array(items) &&
    items[1] is Object(left) else {
    fail("fixture")
  }
  left["custom_extension"] = { "unchanged_id": "root" }
  left["operation"] = "synthetic/explicit-other@1.0.0"
  left["product_id"] = "synthetic"
  source["items"] = [items[3], items[1], items[2], items[0]]
  guard items[2] is Object(right) else { fail("fixture") }
  right["depends_on"] = []
  let result = workflow_payload_import(
    source=Json::object(source),
    spec=workflow_payload_spec(ids=["right", "join", "root", "left"]),
  )
  assert_eq(result.draft.edits[0].work_item_id, "alpha.join")
  assert_eq(result.draft.edits[0].depends_on, ["alpha.left", "alpha.right"])
  assert_eq(result.draft.edits[2].depends_on, [])
  let form = @moonflow.declared_plan_form_v1(result.draft)
  guard form is Object(fields) &&
    fields["items"] is Array(expanded) &&
    expanded[1] is Object(expanded_left) else {
    fail("form")
  }
  assert_eq(expanded_left["custom_extension"], { "unchanged_id": "root" })
  assert_eq(expanded_left["operation"], "synthetic/explicit-other@1.0.0")
  assert_eq(expanded_left["product_id"], "synthetic")
}

///|
test "workflow payloads support explicit per-step ancillary criteria timeout mappings" {
  guard workflow_payload_spec() is Object(fields) &&
    fields["steps"] is Array(steps) &&
    steps[3] is Object(join) else {
    fail("fixture")
  }
  join["additional_input_artifacts_pointer"] = "/record/files"
  join["acceptance_criteria_pointer"] = "/record/criteria"
  join["timeout_ms_pointer"] = "/record/timeout"
  let result = workflow_payload_import(
    spec=Json::object(fields),
    records=(
      #|{"jobs":[{"id":"one","data":null,"files":["references/spec.json"],"criteria":["Review this exact result"],"timeout":1234}]}
    ),
  )
  assert_eq(result.draft.edits[3].input_artifacts.length(), 2)
  assert_eq(result.draft.edits[3].input_artifacts[1], "references/spec.json")
  assert_eq(result.draft.edits[3].timeout_ms, 1234)
  assert_eq(result.draft.edits[3].acceptance_criteria, [
    "Review this exact result",
  ])
  assert_eq(result.draft.edits[0].timeout_ms, 60000)
  assert_eq(result.draft.edits[0].acceptance_criteria, [
    "Review the exact root artifact",
  ])
}

///|
test "workflow payloads are deterministic detached and raw input whitespace affects only export identity" {
  let source = plan_diamond_graph()
  let spec = workflow_payload_spec()
  let before = source.stringify()
  let spec_before = spec.stringify()
  let result = workflow_payload_import(source~, spec~)
  let repeat = workflow_payload_import(
    source~,
    spec~,
    records=workflow_payload_records() + "\n",
  )
  assert_eq(result.draft, repeat.draft)
  assert_eq(result.artifacts, repeat.artifacts)
  assert_eq(result.workflow_digest, repeat.workflow_digest)
  assert_true(result.records_digest != repeat.records_digest)
  assert_eq(source.stringify(), before)
  assert_eq(spec.stringify(), spec_before)
  guard source is Object(fields) &&
    fields["items"] is Array(items) &&
    items[0] is Object(root) else {
    fail("fixture")
  }
  root["operation"] = "caller-mutated"
  assert_eq(result.draft, repeat.draft)
  result.draft.edits[0].depends_on.push("caller-change")
  assert_eq(repeat.draft.edits[0].depends_on, [])
}

///|
test "workflow payloads reject incomplete ambiguous or widened specifications" {
  for
    ids in [
      ["root", "left", "right"],
      ["root", "left", "right", "root"],
      ["root", "left", "right", "missing"],
    ] {
    workflow_payload_expect_failure(spec=workflow_payload_spec(ids~))
  }
  for
    key in [
      "depends_on_pointer", "operation", "requested_authority", "request_template_ref",
    ] {
    guard workflow_payload_spec() is Object(fields) &&
      fields["steps"] is Array(steps) &&
      steps[3] is Object(step) else {
      fail("fixture")
    }
    step[key] = "/record/value"
    workflow_payload_expect_failure(spec=Json::object(fields))
  }
  for key in ["unexpected", "record_id_pointer", "contract_id"] {
    guard workflow_payload_spec() is Object(fields) else { fail("fixture") }
    fields[key] = "invalid"
    workflow_payload_expect_failure(spec=Json::object(fields))
  }
  guard workflow_payload_spec() is Object(fields) &&
    fields["steps"] is Array(steps) &&
    steps[3] is Object(step) else {
    fail("fixture")
  }
  step["bindings"] = [
    { "target_pointer": "/data", "value_pointer": "/record/absent" },
  ]
  workflow_payload_expect_failure(spec=Json::object(fields))
}

///|
test "workflow payloads reject invalid records and ambiguous generated identities before output" {
  for
    records in [
      "not json", "{\"jobs\":[]}", "{\"jobs\":[null]}", "{\"jobs\":[{\"id\":3,\"data\":null}]}",
      "{\"jobs\":[{\"id\":\"../outside\",\"data\":null}]}", "{\"jobs\":[{\"id\":\"same\",\"data\":null},{\"id\":\"same\",\"data\":null}]}",
      "{\"jobs\":[{\"id\":\"ok\",\"data\":null},{\"id\":\"bad\"}]}",
    ] {
    workflow_payload_expect_failure(records~)
  }
  guard plan_diamond_graph() is Object(source) &&
    source["items"] is Array(items) &&
    items[0] is Object(root) &&
    items[1] is Object(left) else {
    fail("fixture")
  }
  root["work_item_id"] = "b.c"
  root["depends_on"] = []
  left["work_item_id"] = "c"
  left["depends_on"] = []
  source["items"] = [items[0], items[1]]
  workflow_payload_expect_failure(
    source=Json::object(source),
    spec=workflow_payload_spec(ids=["b.c", "c"]),
    records="{\"jobs\":[{\"id\":\"a\",\"data\":null},{\"id\":\"a.b\",\"data\":null}]}",
  )
}

///|
test "workflow payloads accept exactly 256 expanded steps and reject the next record" {
  let jobs : Array[Json] = []
  for i in 0..<64 {
    jobs.push({ "id": ("job" + i.to_string()).to_json(), "data": null })
  }
  let result = workflow_payload_import(
    records=({ "jobs": jobs.to_json() } : Json).stringify(),
  )
  assert_eq(result.artifacts.length(), 256)
  jobs.push({ "id": "one-more", "data": null })
  workflow_payload_expect_failure(
    records=({ "jobs": jobs.to_json() } : Json).stringify(),
  )
}

///|
test "workflow payloads enforce combined request bytes across different steps" {
  guard plan_diamond_graph() is Object(source) &&
    source["items"] is Array(original) else {
    fail("fixture")
  }
  let items : Array[Json] = []
  let ids : Array[String] = []
  for i in 0..<16 {
    guard @json.parse(original[0].stringify()) is Object(item) else {
      fail("item")
    }
    let id = "step" + i.to_string()
    ids.push(id)
    item["work_item_id"] = id.to_json()
    item["declaration_id"] = id.to_json()
    items.push(Json::object(item))
  }
  source["items"] = items.to_json()
  let records : Json = {
    "jobs": [{ "id": "one", "data": "x".repeat(530000).to_json() }],
  }
  try
    workflow_payload_import(
      source=Json::object(source),
      spec=workflow_payload_spec(ids~),
      records=records.stringify(),
    )
  catch {
    error => assert_true(error.to_string().contains("8 MiB total"))
  } noraise {
    _ => fail("oversize workflow requests succeeded")
  }
}

///|
test "workflow payloads retain inherited per-file byte limit for Unicode requests" {
  let records : Json = {
    "jobs": [{ "id": "one", "data": "雪".repeat(360000).to_json() }],
  }
  try workflow_payload_import(records=records.stringify()) catch {
    error => {
      assert_true(error.to_string().contains("workflow step root"))
      assert_true(error.to_string().contains("1 MiB per file"))
    }
  } noraise {
    _ => fail("oversize Unicode request succeeded")
  }
}
