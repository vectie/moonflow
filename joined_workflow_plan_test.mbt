///|
fn joined_spec(unmatched? : String = "error") -> Json {
  {
    "contract_id": "moonflow.workflow-record-join.v1",
    "primary_records_pointer": "/jobs",
    "lookup_records_pointer": "/models",
    "primary_key_pointer": "/model",
    "lookup_key_pointer": "/key",
    "unmatched": unmatched.to_json(),
  }
}

///|
fn joined_workflow_spec() -> Json {
  let spec = workflow_payload_spec()
  guard spec is Object(fields) && fields["steps"] is Array(steps) else {
    abort("fixture")
  }
  fields["records_pointer"] = ""
  fields["record_id_pointer"] = "/primary/id"
  for step in steps {
    guard step is Object(values) &&
      values["bindings"] is Array(bindings) &&
      bindings[3] is Object(binding) else {
      abort("fixture")
    }
    binding["value_pointer"] = "/record"
  }
  spec
}

///|
fn joined_import(
  primary? : String = "{\"jobs\":[{\"id\":\"chair\",\"model\":\"wood\"},{\"id\":\"table\",\"model\":\"wood\"}]}",
  lookup? : String = "{\"models\":[{\"key\":\"unused\"},{\"key\":\"wood\",\"parameters\":[42.5,true,null,\"雪\"]}]}",
  spec? : Json = joined_spec(),
  workflow? : Json = joined_workflow_spec(),
) -> @moonflow.JoinedWorkflowPlanImportV1 raise {
  @moonflow.declared_plan_from_joined_workflow_v1(
    plan_diamond_graph(),
    workflow,
    spec,
    primary,
    lookup,
    "joined-study",
    "2026-07-31T00:00:00Z",
  )
}

///|
fn joined_refuses(
  primary : String,
  lookup : String,
  spec? : Json = joined_spec(),
) -> Unit raise {
  try joined_import(primary~, lookup~, spec~) catch {
    _ => ()
  } noraise {
    _ => fail("invalid join succeeded")
  }
}

///|
test "joined workflow enriches ordered records and preserves typed data and topology" {
  let result = joined_import()
  assert_eq(result.workflow.record_ids, ["chair", "table"])
  assert_eq(result.unmatched_primary_rows, [])
  assert_eq(result.unused_lookup_rows, [1])
  assert_eq(result.workflow.draft.edits[3].depends_on, [
    "chair.left", "chair.right",
  ])
  assert_eq(result.workflow.draft.edits[7].depends_on, [
    "table.left", "table.right",
  ])
  assert_eq(result.joined_records[0], {
    "primary": { "id": "chair", "model": "wood" },
    "lookup": { "key": "wood", "parameters": [42.5, true, null, "雪"] },
  })
  guard @json.parse(result.workflow.artifacts[0].json_text) is Object(payload) else {
    fail("payload")
  }
  assert_eq(payload["data"], result.joined_records[0])
  assert_eq(result, joined_import())
}

///|
test "joined workflow explicit null retains unmatched records and never drops work" {
  let result = joined_import(
    lookup="{\"models\":[]}",
    spec=joined_spec(unmatched="null"),
  )
  assert_eq(result.unmatched_primary_rows, [1, 2])
  assert_eq(result.workflow.draft.edits.length(), 8)
  guard result.joined_records[0] is Object(fields) else { fail("record") }
  assert_eq(fields["lookup"], Json::null())
  joined_refuses(
    "{\"jobs\":[{\"id\":\"one\",\"model\":\"absent\"}]}", "{\"models\":[]}",
  )
}

///|
test "joined workflow rejects ambiguous lookup rows including unused keys" {
  let primary = "{\"jobs\":[{\"id\":\"one\",\"model\":\"found\"}]}"
  joined_refuses(
    primary, "{\"models\":[{\"key\":\"found\"},{\"key\":\"found\"}]}",
  )
  joined_refuses(
    primary, "{\"models\":[{\"key\":\"found\"},{\"key\":\"other\"},{\"key\":\"other\"}]}",
  )
}

///|
test "joined workflow distinguishes scalar types and preserves large numeric identities" {
  let primary = "{\"jobs\":[{\"id\":\"s\",\"model\":\"1\"},{\"id\":\"n\",\"model\":1},{\"id\":\"b\",\"model\":true},{\"id\":\"large\",\"model\":9007199254740993}]}"
  let lookup = "{\"models\":[{\"key\":true,\"v\":false},{\"key\":1,\"v\":12.5},{\"key\":\"1\",\"v\":null},{\"key\":9007199254740992},{\"key\":9007199254740993,\"v\":\"exact\"}]}"
  let result = joined_import(primary~, lookup~)
  assert_eq(result.unused_lookup_rows, [4])
  guard result.joined_records[3] is Object(record) &&
    record["lookup"] is Object(values) else {
    fail("lookup")
  }
  assert_eq(values["v"], "exact")
  joined_refuses(
    "{\"jobs\":[{\"id\":\"n\",\"model\":1.0}]}", "{\"models\":[{\"key\":1}]}",
  )
  let fractional = joined_import(
    primary="{\"jobs\":[{\"id\":\"precise\",\"model\":1.00000000000000001}]}",
    lookup="{\"models\":[{\"key\":1.00000000000000002,\"v\":\"wrong\"},{\"key\":1.00000000000000001,\"v\":\"correct\"}]}",
  )
  assert_eq(fractional.unused_lookup_rows, [1])
  assert_true(
    fractional.workflow.artifacts[0].json_text.contains("1.00000000000000001"),
  )
  assert_true(fractional.workflow.artifacts[0].json_text.contains("correct"))
  joined_refuses(
    "{\"jobs\":[{\"id\":\"n\",\"model\":1,\"model\":2}]}", "{\"models\":[{\"key\":2}]}",
  )
}

///|
test "joined workflow rejects null containers missing keys late failures and invalid modes" {
  for value in ["null", "[]", "{}"] {
    joined_refuses(
      "{\"jobs\":[{\"id\":\"one\",\"model\":" + value + "}]}",
      "{\"models\":[]}",
      spec=joined_spec(unmatched="null"),
    )
  }
  joined_refuses(
    "{\"jobs\":[{\"id\":\"one\",\"model\":1},{\"id\":\"two\"}]}", "{\"models\":[{\"key\":1}]}",
  )
  joined_refuses(
    "{\"jobs\":[{\"id\":\"one\",\"model\":1}]}", "{\"models\":[{\"key\":1},null]}",
  )
  joined_refuses("{\"jobs\":[]}", "{\"models\":[]}")
  joined_refuses(
    "{\"jobs\":[{\"id\":\"one\",\"model\":1}]}",
    "{\"models\":[]}",
    spec=joined_spec(unmatched="drop"),
  )
}

///|
test "joined workflow saves a normal editable draft and requires current preparation gates" {
  let result = joined_import()
  assert_eq(
    @moonflow.decode_declared_plan_draft_v1(result.workflow.draft.to_json()),
    result.workflow.draft,
  )
  let prepared = @moonflow.prepare_declared_plan_v1(
    result.workflow.draft,
    @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
    "2026-07-31T00:00:00Z",
  )
  let run = @moonflow.replay(
    prepared.preparation_id,
    @moonflow.conformant_events_from_work_graph_at_v1(
      prepared.graph,
      @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
      "2026-07-31T00:00:00Z",
    ),
  )
  assert_eq(run.items.length(), 8)
  for item in run.items {
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
    assert_eq(item.requested_authority, "workspace-mutation")
  }
  try
    @moonflow.prepare_declared_plan_v1(
      result.workflow.draft,
      @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
      "2026-08-02T00:00:00Z",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expired catalog prepared")
  }
}
