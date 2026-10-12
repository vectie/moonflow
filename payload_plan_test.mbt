///|
fn payload_mapping() -> Json {
  {
    "contract_id": "moonflow.payload-plan-mapping.v1",
    "records_pointer": "/jobs",
    "template_work_item_id": "left",
    "work_item_id_pointer": "/id",
    "depends_on_pointer": "/after",
    "bindings": [
      { "target_pointer": "/name", "value_pointer": "/label" },
      { "target_pointer": "/shape/size", "value_pointer": "/size" },
      { "target_pointer": "/shape/flags", "value_pointer": "/flags" },
      { "target_pointer": "/values/0", "value_pointer": "/first" },
      { "target_pointer": "/a~1b~0c", "value_pointer": "/nested" },
    ],
  }
}

///|
fn payload_template() -> Json {
  {
    "contract_id": "synthetic.request.v1",
    "name": "placeholder",
    "shape": { "size": 0, "flags": false, "fixed": "retained" },
    "values": [0, 99],
    "a/b~c": {},
  }
}

///|
fn payload_records() -> String {
  (
    #|{"jobs":[
    #| {"id":"red","label":"café, \"red\"\n雪","size":12.5,"flags":[true,false,null],"first":null,"nested":{"x":1},"after":[]},
    #| {"id":"blue","label":"blue","size":7,"flags":false,"first":[1,2],"nested":{"x":["b"]},"after":["red"]}
    #|]}
  )
}

///|
test "payload materialization retains typed values and exact operation in an ordinary editable plan" {
  let source = plan_diamond_graph()
  let template = payload_template()
  let before = source.stringify()
  let template_before = template.stringify()
  let imported = @moonflow.declared_plan_from_payloads_v1(
    source,
    payload_mapping(),
    template,
    payload_records(),
    "payload-batch",
    "2026-07-31T00:00:00Z",
  )
  let red = @json.parse(imported.artifacts[0].json_text)
  assert_eq(red, {
    "contract_id": "synthetic.request.v1",
    "name": "café, \"red\"\n雪",
    "shape": { "size": 12.5, "flags": [true, false, null], "fixed": "retained" },
    "values": [null, 99],
    "a/b~c": { "x": 1 },
  })
  assert_eq(imported.artifacts.length(), 2)
  assert_eq(imported.draft.edits[1].depends_on, ["red"])
  for index, artifact in imported.artifacts {
    assert_eq(imported.draft.edits[index].input_artifacts, [
      artifact.artifact_ref,
    ])
    assert_eq(artifact.sha256.length(), 71)
    assert_true(artifact.json_text.has_suffix("\n"))
    assert_true(
      artifact.artifact_ref.contains(artifact.sha256.substring(start=7)),
    )
  }
  let prepared = @moonflow.prepare_declared_plan_v1(
    imported.draft,
    @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
    "2026-07-31T00:00:00Z",
  )
  let run = @moonflow.replay(
    prepared.preparation_id,
    @moonflow.events_from_work_graph(prepared.graph),
  )
  assert_eq(run.items.length(), 2)
  for item in run.items {
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.required_claim, "digital-artifact")
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
  }
  assert_eq(source.stringify(), before)
  assert_eq(template.stringify(), template_before)
  assert_eq(
    @moonflow.decode_declared_plan_draft_v1(imported.draft.to_json()),
    imported.draft,
  )
}

///|
test "payload identity is deterministic and exact request bytes are shared across identical jobs" {
  let first = @moonflow.declared_plan_from_payloads_v1(
    plan_diamond_graph(),
    payload_mapping(),
    payload_template(),
    payload_records(),
    "batch",
    "2026-07-31T00:00:00Z",
  )
  let second = @moonflow.declared_plan_from_payloads_v1(
    plan_diamond_graph(),
    payload_mapping(),
    payload_template(),
    payload_records() + "\n",
    "batch",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(first.artifacts, second.artifacts)
  assert_eq(first.draft, second.draft)
  assert_true(first.records_digest != second.records_digest)
  let mapping : Json = {
    "contract_id": "moonflow.payload-plan-mapping.v1",
    "records_pointer": "",
    "template_work_item_id": "left",
    "work_item_id_pointer": "/id",
    "depends_on_pointer": null,
    "additional_input_artifacts_pointer": "/files",
    "bindings": [{ "target_pointer": "/name", "value_pointer": "/name" }],
  }
  let same = @moonflow.declared_plan_from_payloads_v1(
    plan_diamond_graph(),
    mapping,
    { "name": "" },
    "[{\"id\":\"one\",\"name\":\"same\",\"files\":[\"evidence/a.json\"]},{\"id\":\"two\",\"name\":\"same\",\"files\":[]}]",
    "same",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(same.artifacts[0].artifact_ref, same.artifacts[1].artifact_ref)
  assert_eq(same.draft.edits[0].input_artifacts[1], "evidence/a.json")
  assert_eq(same.draft.edits[1].depends_on, [])
}

///|
test "payload targets refuse unknown paths root overlap noncanonical arrays and scalar traversal" {
  for
    targets in [
      [""],
      ["/absent"],
      ["/values/01"],
      ["/values/-"],
      ["/values/8"],
      ["/name/x"],
      ["/a~2b"],
      ["/shape", "/shape/size"],
      ["/name", "/name"],
    ] {
    guard payload_mapping() is Object(fields) else { fail("mapping") }
    fields["bindings"] = targets
      .map(target => {
        ({ "target_pointer": target, "value_pointer": "/label" } : Json)
      })
      .to_json()
    assert_true(
      (try? @moonflow.declared_plan_from_payloads_v1(
        plan_diamond_graph(),
        Json::object(fields),
        payload_template(),
        payload_records(),
        "bad",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}

///|
test "payload mapping refuses malformed records missing values and invalid declarations as a whole" {
  for
    text in [
      "not-json",
      "{\"jobs\":[]}",
      "{\"jobs\":[1]}",
      "{\"jobs\":[{\"id\":\"x\",\"after\":[]}]}",
      payload_records().replace(old="\"blue\"", new="\"red\""),
      payload_records().replace(old="\"red\"", new="\"../red\""),
      payload_records().replace(old="\"after\":[]", new="\"after\":[\"blue\"]"),
    ] {
    assert_true(
      (try? @moonflow.declared_plan_from_payloads_v1(
        plan_diamond_graph(),
        payload_mapping(),
        payload_template(),
        text,
        "bad",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
  for field in ["operation", "requested_authority", "input_artifacts_pointer"] {
    guard payload_mapping() is Object(fields) else { fail("mapping") }
    fields[field] = "untrusted".to_json()
    assert_true(
      (try? @moonflow.declared_plan_from_payloads_v1(
        plan_diamond_graph(),
        Json::object(fields),
        payload_template(),
        payload_records(),
        "bad",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}

///|
test "payload bindings retain sibling paths and optional generic edit fields" {
  let mapping : Json = {
    "contract_id": "moonflow.payload-plan-mapping.v1",
    "records_pointer": "",
    "template_work_item_id": "left",
    "work_item_id_pointer": "/id",
    "acceptance_criteria_pointer": "/criteria",
    "timeout_ms_pointer": "/timeout",
    "bindings": [
      { "target_pointer": "/a", "value_pointer": "/v" },
      { "target_pointer": "/ab", "value_pointer": "/v" },
    ],
  }
  let imported = @moonflow.declared_plan_from_payloads_v1(
    plan_diamond_graph(),
    mapping,
    { "a": null, "ab": null },
    "[{\"id\":\"next\",\"v\":true,\"criteria\":[\"Review generated request\"],\"timeout\":45000}]",
    "next",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(@json.parse(imported.artifacts[0].json_text), {
    "a": true,
    "ab": true,
  })
  assert_eq(imported.draft.edits[0].timeout_ms, 45000)
  assert_eq(imported.draft.edits[0].acceptance_criteria, [
    "Review generated request",
  ])
}

///|
test "payload import enforces record binding and generated byte budgets" {
  let basic : Json = {
    "contract_id": "moonflow.payload-plan-mapping.v1",
    "records_pointer": "",
    "template_work_item_id": "left",
    "work_item_id_pointer": "/id",
    "bindings": [{ "target_pointer": "/value", "value_pointer": "/value" }],
  }
  let jobs = Array::makei(257, index => {
    ({ "id": "job-\{index}", "value": 1 } : Json)
  })
  assert_true(
    (try? @moonflow.declared_plan_from_payloads_v1(
      plan_diamond_graph(),
      basic,
      { "value": null },
      jobs.to_json().stringify(),
      "large",
      "2026-07-31T00:00:00Z",
    ))
    is Err(_),
  )
  for count in [0, 65] {
    guard basic is Object(fields) else { fail("mapping") }
    let changed = fields.copy()
    changed["bindings"] = Array::makei(count, _ => {
      ({ "target_pointer": "/value", "value_pointer": "/value" } : Json)
    }).to_json()
    assert_true(
      (try? @moonflow.declared_plan_from_payloads_v1(
        plan_diamond_graph(),
        Json::object(changed),
        { "value": null },
        "[{\"id\":\"one\",\"value\":1}]",
        "large",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
  let over_file : Json = [{ "id": "one", "value": "x".repeat(600000) }]
  assert_true(
    (try? @moonflow.declared_plan_from_payloads_v1(
      plan_diamond_graph(),
      basic,
      { "value": null, "fixed": "x".repeat(600000) },
      over_file.stringify(),
      "large",
      "2026-07-31T00:00:00Z",
    ))
    is Err(_),
  )
  let ten = Array::makei(10, index => {
    ({ "id": "job-\{index}", "value": 1 } : Json)
  })
  assert_true(
    (try? @moonflow.declared_plan_from_payloads_v1(
      plan_diamond_graph(),
      basic,
      { "value": null, "fixed": "x".repeat(900000) },
      ten.to_json().stringify(),
      "large",
      "2026-07-31T00:00:00Z",
    ))
    is Err(_),
  )
}
