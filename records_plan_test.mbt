///|
fn records_mapping() -> Json {
  {
    "contract_id": "moonflow.records-plan-mapping.v1",
    "records_pointer": "/data/jobs",
    "template_work_item_id": "left",
    "work_item_id_pointer": "/identity/key",
    "input_artifacts_pointer": "/request/files",
    "depends_on_pointer": "/request/after",
    "acceptance_criteria_pointer": "/review/criteria",
    "timeout_ms_pointer": "/request/timeout",
  }
}

///|
fn records_export() -> String {
  (
    #|{"data":{"jobs":[
    #|  {"identity":{"key":"red"},"request":{"files":["requests/red.json"],"after":[],"timeout":45000},"review":{"criteria":["Check café, colour and joints"]},"operation":"ignored/untrusted@0.0.0"},
    #|  {"identity":{"key":"display"},"request":{"files":["requests/display.json","references/room.json"],"after":["red","blue"],"timeout":90000},"review":{"criteria":["Check both stools","Review \"final\" display"]}},
    #|  {"identity":{"key":"blue"},"request":{"files":["requests/blue.json"],"after":[],"timeout":60000},"review":{"criteria":["Check blue stool"]}}
    #|]},"next_page":null}
  )
}

///|
test "JSON records import nested arrays and forward dependencies into an editable exact-contract plan" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let imported = @moonflow.declared_plan_from_records_v1(
    source,
    records_mapping(),
    records_export(),
    "api-batch",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(imported.record_ids, ["red", "display", "blue"])
  assert_eq(imported.records_pointer, "/data/jobs")
  assert_eq(imported.records_digest.length(), 71)
  assert_eq(imported.mapping_digest.length(), 71)
  assert_eq(imported.draft.edits[1].input_artifacts, [
    "requests/display.json", "references/room.json",
  ])
  assert_eq(imported.draft.edits[1].depends_on, ["red", "blue"])
  assert_eq(imported.draft.edits[0].acceptance_criteria, [
    "Check café, colour and joints",
  ])
  assert_eq(imported.draft.edits[1].timeout_ms, 90000)
  assert_eq(
    @moonflow.decode_declared_plan_draft_v1(imported.draft.to_json()),
    imported.draft,
  )
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let prepared = @moonflow.prepare_declared_plan_v1(
    imported.draft,
    catalog,
    "2026-07-31T00:00:00Z",
  )
  let run = @moonflow.replay(
    prepared.preparation_id,
    @moonflow.events_from_work_graph(prepared.graph),
  )
  assert_eq(run.items.length(), 3)
  assert_true(run.find_item("left") is None)
  for item in run.items {
    assert_eq(item.product_id, "moonmold")
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.required_claim, "digital-artifact")
    assert_eq(item.input_contracts, ["moonmold/spatial-operation-request@1.0.0"])
    assert_eq(item.output_contracts, [
      "moonmold/spatial-operation-receipt@1.0.0",
    ])
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
  }
  assert_true(run.items[0].declaration_id != run.items[1].declaration_id)
  let edited = @moonflow.edit_declared_plan_item_v1(imported.draft, {
    ..imported.draft.edits[0],
    input_artifacts: ["requests/revised-red.json"],
  })
  assert_eq(imported.draft.edits[0].input_artifacts, ["requests/red.json"])
  assert_true(
    @moonflow.prepare_declared_plan_v1(edited, catalog, "2026-07-31T00:00:00Z").preparation_id !=
    prepared.preparation_id,
  )
  assert_eq(source.stringify(), before)
}

///|
test "JSON records root arrays escaped keys array indices and defaults are usable" {
  let mapping : Json = {
    "contract_id": "moonflow.records-plan-mapping.v1",
    "records_pointer": "",
    "template_work_item_id": "left",
    "work_item_id_pointer": "/identity/0/a~1b~0c",
    "input_artifacts_pointer": "/~01/",
  }
  let imported = @moonflow.declared_plan_from_records_v1(
    plan_diamond_graph(),
    mapping,
    "[{\"identity\":[{\"a/b~c\":\"escaped\"}],\"~1\":{\"\":[\"requests/café, final.json\"]}}]",
    "escaped-batch",
    "2026-07-31T00:00:00Z",
  )
  let edit = imported.draft.edits[0]
  assert_eq(edit.work_item_id, "escaped")
  assert_eq(edit.input_artifacts, ["requests/café, final.json"])
  assert_eq(edit.depends_on, [])
  assert_eq(edit.acceptance_criteria, ["Review the exact left artifact"])
  assert_eq(edit.timeout_ms, 60000)
}

///|
test "JSON records plain JSON null optional selectors use defaults without changing mapping identity" {
  let all_null_json =
    #|{"contract_id":"moonflow.records-plan-mapping.v1","records_pointer":"/data/jobs","template_work_item_id":"left","work_item_id_pointer":"/identity/key","input_artifacts_pointer":"/request/files","depends_on_pointer":null,"acceptance_criteria_pointer":null,"timeout_ms_pointer":null}
  let all_null_mapping = @json.parse(all_null_json)
  let before = all_null_mapping.stringify()
  let imported = @moonflow.declared_plan_from_records_v1(
    plan_diamond_graph(),
    all_null_mapping,
    records_export(),
    "null-batch",
    "2026-07-31T00:00:00Z",
  )
  for edit in imported.draft.edits {
    assert_eq(edit.depends_on, [])
    assert_eq(edit.acceptance_criteria, ["Review the exact left artifact"])
    assert_eq(edit.timeout_ms, 60000)
  }
  assert_eq(all_null_mapping.stringify(), before)
  let omitted_mapping = @json.parse(
    (
      #|{"contract_id":"moonflow.records-plan-mapping.v1","records_pointer":"/data/jobs","template_work_item_id":"left","work_item_id_pointer":"/identity/key","input_artifacts_pointer":"/request/files"}
    ),
  )
  let omitted = @moonflow.declared_plan_from_records_v1(
    plan_diamond_graph(),
    omitted_mapping,
    records_export(),
    "null-batch",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(imported.draft, omitted.draft)
  assert_true(imported.mapping_digest != omitted.mapping_digest)
  for
    selector in [
      "depends_on_pointer", "acceptance_criteria_pointer", "timeout_ms_pointer",
    ] {
    // Round-trip through actual JSON text, rather than MoonBit Option::None.
    guard records_mapping() is Object(fields) else { fail("mapping") }
    fields[selector] = @json.parse("null")
    let plain_json = @json.parse(Json::object(fields).stringify())
    let result = @moonflow.declared_plan_from_records_v1(
      plan_diamond_graph(),
      plain_json,
      records_export(),
      "single-null",
      "2026-07-31T00:00:00Z",
    )
    assert_eq(
      result.draft.edits[1].depends_on,
      if selector == "depends_on_pointer" {
        []
      } else {
        ["red", "blue"]
      },
    )
    assert_eq(
      result.draft.edits[1].acceptance_criteria,
      if selector == "acceptance_criteria_pointer" {
        ["Review the exact left artifact"]
      } else {
        ["Check both stools", "Review \"final\" display"]
      },
    )
    assert_eq(
      result.draft.edits[1].timeout_ms,
      if selector == "timeout_ms_pointer" {
        60000
      } else {
        90000
      },
    )
  }
}

///|
test "JSON records repeat deterministically and distinguish input and mapping identities" {
  let first = @moonflow.declared_plan_from_records_v1(
    plan_diamond_graph(),
    records_mapping(),
    records_export(),
    "batch",
    "2026-07-31T00:00:00Z",
  )
  let second = @moonflow.declared_plan_from_records_v1(
    plan_diamond_graph(),
    records_mapping(),
    records_export(),
    "batch",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(first, second)
  let whitespace = @moonflow.declared_plan_from_records_v1(
    plan_diamond_graph(),
    records_mapping(),
    records_export() + "\n",
    "batch",
    "2026-07-31T00:00:00Z",
  )
  assert_true(first.records_digest != whitespace.records_digest)
  assert_eq(first.draft, whitespace.draft)
  guard records_mapping() is Object(fields) else { fail("mapping") }
  let reordered : Map[String, Json] = {}
  for key in fields.keys().to_array().rev() {
    reordered[key] = fields[key]
  }
  let reordered_import = @moonflow.declared_plan_from_records_v1(
    plan_diamond_graph(),
    Json::object(reordered),
    records_export(),
    "batch",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(first.mapping_digest, reordered_import.mapping_digest)
}

///|
test "JSON records refuse malformed missing scalar or incorrectly typed selectors with record context" {
  for
    pointer in [
      "data/jobs", "/data/~2", "/data/jobs/01", "/data/jobs/-", "/data/jobs/999999999999999999999",
      "/data/jobs/0/identity/key/x", "/absent",
    ] {
    guard records_mapping() is Object(mapping) else { fail("mapping") }
    mapping["records_pointer"] = pointer.to_json()
    assert_true(
      (try? @moonflow.declared_plan_from_records_v1(
        plan_diamond_graph(),
        Json::object(mapping),
        records_export(),
        "bad",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
  guard records_mapping() is Object(mapping) else { fail("mapping") }
  mapping["input_artifacts_pointer"] = "/request/absent".to_json()
  try
    @moonflow.declared_plan_from_records_v1(
      plan_diamond_graph(),
      Json::object(mapping),
      records_export(),
      "bad",
      "2026-07-31T00:00:00Z",
    )
  catch {
    error => assert_true(error.to_string().contains("record 1"))
  } noraise {
    _ => fail("missing pointer was accepted")
  }
  for
    (key, value) in [
      ("records_pointer", "/data/jobs/0".to_json()),
      ("input_artifacts_pointer", "/request/files/0".to_json()),
      ("work_item_id_pointer", "/request/timeout".to_json()),
      ("timeout_ms_pointer", "/identity/key".to_json()),
      ("acceptance_criteria_pointer", "/request/timeout".to_json()),
      ("operation_pointer", "/operation".to_json()),
      ("template_work_item_id", "absent".to_json()),
      ("contract_id", "unknown".to_json()),
    ] {
    guard records_mapping() is Object(mapping) else { fail("mapping") }
    mapping[key] = value
    assert_true(
      (try? @moonflow.declared_plan_from_records_v1(
        plan_diamond_graph(),
        Json::object(mapping),
        records_export(),
        "bad",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}

///|
test "JSON records retain whole-batch graph and typed field validation" {
  let replacements : Array[Json] = [
    {
      "identity": { "key": "red" },
      "request": {
        "files": ["requests/duplicate.json"],
        "after": [],
        "timeout": 60000,
      },
      "review": { "criteria": ["Check"] },
    },
    {
      "identity": { "key": "left" },
      "request": { "files": ["requests/a.json"], "after": [], "timeout": 60000 },
      "review": { "criteria": ["Check"] },
    },
    {
      "identity": { "key": "../bad" },
      "request": { "files": ["requests/a.json"], "after": [], "timeout": 60000 },
      "review": { "criteria": ["Check"] },
    },
    {
      "identity": { "key": "blue" },
      "request": { "files": ["../escape.json"], "after": [], "timeout": 60000 },
      "review": { "criteria": ["Check"] },
    },
    {
      "identity": { "key": "blue" },
      "request": {
        "files": ["requests/a.json"],
        "after": ["display"],
        "timeout": 60000,
      },
      "review": { "criteria": ["Check"] },
    },
    {
      "identity": { "key": "blue" },
      "request": {
        "files": ["requests/a.json"],
        "after": ["absent"],
        "timeout": 60000,
      },
      "review": { "criteria": ["Check"] },
    },
    {
      "identity": { "key": "blue" },
      "request": { "files": ["requests/a.json"], "after": [], "timeout": 1.5 },
      "review": { "criteria": ["Check"] },
    },
    {
      "identity": { "key": "blue" },
      "request": {
        "files": ["requests/a.json"],
        "after": [],
        "timeout": 86400001,
      },
      "review": { "criteria": ["Check"] },
    },
    {
      "identity": { "key": "blue" },
      "request": { "files": ["requests/a.json"], "after": [], "timeout": 60000 },
      "review": { "criteria": [] },
    },
    {
      "identity": { "key": "blue" },
      "request": { "files": [123], "after": [], "timeout": 60000 },
      "review": { "criteria": ["Check"] },
    },
    Json::null(),
  ]
  for replacement in replacements {
    guard @json.parse(records_export())
      is { "data": { "jobs": Array(records), .. }, .. } else {
      fail("records")
    }
    records[2] = replacement
    assert_true(
      (try? @moonflow.declared_plan_from_records_v1(
        plan_diamond_graph(),
        records_mapping(),
        ({ "data": { "jobs": records } } : Json).stringify(),
        "bad",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}

///|
test "JSON records accept 256 items and refuse empty oversized or malformed exports" {
  let records : Array[Json] = []
  for index in 0..<256 {
    records.push({
      "identity": { "key": "item-\{index}" },
      "request": {
        "files": ["requests/\{index}.json"],
        "after": [],
        "timeout": 60000,
      },
      "review": { "criteria": ["Check item"] },
    })
  }
  let input : Json = { "data": { "jobs": records } }
  let imported = @moonflow.declared_plan_from_records_v1(
    plan_diamond_graph(),
    records_mapping(),
    input.stringify(),
    "limit",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(imported.record_ids.length(), 256)
  records.push(records[0])
  for
    value in [
      ({ "data": { "jobs": records } } : Json).stringify(),
      "{\"data\":{\"jobs\":[]}}",
      "{bad json",
      " ".repeat(1048577),
    ] {
    assert_true(
      (try? @moonflow.declared_plan_from_records_v1(
        plan_diamond_graph(),
        records_mapping(),
        value,
        "bad",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}
