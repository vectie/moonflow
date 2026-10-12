///|
fn queue_mapping() -> Json {
  {
    "contract_id": "moonflow.queue-plan-mapping.v1",
    "template_work_item_id_pointer": "/kind",
    "work_item_id_pointer": "/id",
    "input_artifacts_pointer": "/request/files",
    "depends_on_pointer": "/after",
  }
}

///|
fn queue_text() -> String {
  (
    #|{"kind":"join","id":"display","request":{"files":["requests/café final.json","references/room.json"]},"after":["blue","red"],"operation":"untrusted/ignored@9.0.0"}
    #|{"kind":"left","id":"red","request":{"files":["requests/red.json"]},"after":[]}
    #|{"kind":"right","id":"blue","request":{"files":["requests/blue.json"]},"after":[]}
  )
}

///|
fn queue_import(
  text : String,
  mapping? : Json = queue_mapping(),
) -> @moonflow.QueuePlanImportV1 raise {
  @moonflow.declared_plan_from_queue_v1(
    plan_diamond_graph(),
    mapping,
    text,
    "queue",
    "2026-07-31T00:00:00Z",
  )
}

///|
test "JSONL queue preserves mixed template defaults physical lines and forward dependencies" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let imported = @moonflow.declared_plan_from_queue_v1(
    source,
    queue_mapping(),
    queue_text(),
    "queue",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(imported.entries.map(entry => entry.line_number), [1, 2, 3])
  assert_eq(imported.entries.map(entry => entry.work_item_id), [
    "display", "red", "blue",
  ])
  assert_eq(imported.entries.map(entry => entry.template_work_item_id), [
    "join", "left", "right",
  ])
  assert_eq(imported.draft.edits[0].depends_on, ["blue", "red"])
  assert_eq(imported.draft.edits[0].input_artifacts, [
    "requests/café final.json", "references/room.json",
  ])
  assert_eq(imported.draft.edits[0].acceptance_criteria, [
    "Review the exact join artifact",
  ])
  assert_eq(imported.draft.edits[1].acceptance_criteria, [
    "Review the exact left artifact",
  ])
  assert_eq(imported.draft.edits[2].acceptance_criteria, [
    "Review the exact right artifact",
  ])
  assert_eq(imported.draft.edits[0].timeout_ms, 60000)
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
  for item in run.items {
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.input_contracts, ["moonmold/spatial-operation-request@1.0.0"])
    assert_eq(item.output_contracts, [
      "moonmold/spatial-operation-receipt@1.0.0",
    ])
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.required_claim, "digital-artifact")
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
  }
  let edited = @moonflow.edit_declared_plan_item_v1(imported.draft, {
    ..imported.draft.edits[0],
    acceptance_criteria: ["Review revised display"],
  })
  assert_true(
    @moonflow.prepare_declared_plan_v1(edited, catalog, "2026-07-31T00:00:00Z").preparation_id !=
    prepared.preparation_id,
  )
  assert_eq(imported.draft.edits[0].acceptance_criteria, [
    "Review the exact join artifact",
  ])
  assert_eq(source.stringify(), before)
}

///|
test "JSONL queue selects heterogeneous exact source contracts without importing untrusted operations" {
  let source = plan_diamond_graph()
  guard source is { "items": Array(items), .. } && items[3] is Object(report) else {
    fail("source")
  }
  report["product_id"] = "synthetic-report"
  report["operation"] = "synthetic-report/render@1.0.0"
  report["requested_authority"] = "observe"
  report["required_claim"] = "reviewable-report"
  report["input_contracts"] = ["synthetic-report/request@1.0.0"]
  report["output_contracts"] = ["synthetic-report/result@1.0.0"]
  report["timeout_ms"] = 15000
  let before = source.stringify()
  let imported = @moonflow.declared_plan_from_queue_v1(
    source,
    queue_mapping(),
    queue_text(),
    "mixed",
    "2026-07-31T00:00:00Z",
  )
  let form = @moonflow.declared_plan_form_v1(imported.draft)
  guard form is { "items": Array(expanded), .. } else { fail("form") }
  assert_true(
    expanded[0]
    is {
      "product_id": "synthetic-report",
      "operation": "synthetic-report/render@1.0.0",
      "requested_authority": "observe",
      "required_claim": "reviewable-report",
      "input_contracts": ["synthetic-report/request@1.0.0"],
      "output_contracts": ["synthetic-report/result@1.0.0"],
      "timeout_ms": 15000,
      ..
    },
  )
  assert_true(
    expanded[1]
    is {
      "product_id": "moonmold",
      "operation": "moonmold/spatial.operation.execute@0.2.0",
      ..
    },
  )
  assert_eq(source.stringify(), before)
  report["operation"] = "later/change@9.0.0"
  assert_eq(@moonflow.declared_plan_form_v1(imported.draft), form)
}

///|
test "JSONL queue repeats deterministically and separates raw bytes from materialized draft" {
  let first = queue_import(queue_text())
  assert_eq(first, queue_import(queue_text()))
  for
    text in [
      queue_text() + "\n",
      queue_text().split("\n").join("\r\n") + "\r\n",
    ] {
    let changed = queue_import(text)
    assert_eq(changed.draft, first.draft)
    assert_eq(changed.entries, first.entries)
    assert_true(changed.queue_digest != first.queue_digest)
  }
  assert_eq(first.queue_digest.length(), 71)
  assert_eq(first.mapping_digest.length(), 71)
  guard queue_mapping() is Object(fields) else { fail("mapping") }
  let reordered : Map[String, Json] = {}
  for key in fields.keys().to_array().rev() {
    reordered[key] = fields[key]
  }
  assert_eq(queue_import(queue_text(), mapping=Json::object(reordered)), first)
}

///|
test "JSONL queue optional null selectors retain per-template defaults and escaped pointer values" {
  let mapping = @json.parse(
    (
      #|{"contract_id":"moonflow.queue-plan-mapping.v1","template_work_item_id_pointer":"/meta/0/a~1b~0c","work_item_id_pointer":"/id","input_artifacts_pointer":"/~01/","depends_on_pointer":null,"acceptance_criteria_pointer":null,"timeout_ms_pointer":null}
    ),
  )
  let before = mapping.stringify()
  let text = "{\"meta\":[{\"a/b~c\":\"left\"}],\"id\":\"escaped\",\"~1\":{\"\":[\"requests/茶.json\"]}}"
  let imported = queue_import(text, mapping~)
  assert_eq(imported.draft.edits[0].depends_on, [])
  assert_eq(imported.draft.edits[0].acceptance_criteria, [
    "Review the exact left artifact",
  ])
  assert_eq(imported.draft.edits[0].timeout_ms, 60000)
  assert_eq(mapping.stringify(), before)
  guard @json.parse(before) is Object(fields) else { fail("mapping") }
  for
    key in [
      "depends_on_pointer", "acceptance_criteria_pointer", "timeout_ms_pointer",
    ] {
    fields.remove(key)
  }
  let omitted = queue_import(text, mapping=Json::object(fields))
  assert_eq(omitted.draft, imported.draft)
  assert_true(omitted.mapping_digest != imported.mapping_digest)
}

///|
test "JSONL queue applies explicit typed criteria and timeout overrides" {
  guard queue_mapping() is Object(fields) else { fail("mapping") }
  fields["acceptance_criteria_pointer"] = "/review"
  fields["timeout_ms_pointer"] = "/timeout"
  let text = "{\"kind\":\"left\",\"id\":\"overridden\",\"request\":{\"files\":[\"a.json\"]},\"after\":[],\"review\":[\"Check \\\"café\\\"\"],\"timeout\":86400000}"
  let imported = queue_import(text, mapping=Json::object(fields))
  assert_eq(imported.draft.edits[0].acceptance_criteria, ["Check \"café\""])
  assert_eq(imported.draft.edits[0].timeout_ms, 86400000)
  for replacement in ["0", "1.5", "86400001", "null", "\"60000\""] {
    assert_true(
      (try? queue_import(
        text.replace(old="86400000", new=replacement),
        mapping=Json::object(fields),
      ))
      is Err(_),
    )
  }
}

///|
test "JSONL queue refuses blank malformed nonobject BOM and late invalid lines with physical line context" {
  for
    (text, expected) in [
      ("", "line 1"),
      ("\n", "line 1"),
      (" \r\n", "line 1"),
      (queue_text() + "\n\n", "line 4"),
      (queue_text() + "\n{bad", "line 4"),
      (queue_text() + "\nnull", "line 4"),
      (queue_text() + "\n[]", "line 4"),
      (queue_text() + "\n{}", "line 4"),
      ("\u{FEFF}" + queue_text(), "line 1"),
      (
        queue_text() + "\n" + queue_text().split("\n").to_array()[0].to_string(),
        "line 4",
      ),
      (queue_text().replace(old="\"right\"", new="\"unknown\""), "line 3"),
    ] {
    try queue_import(text) catch {
      error => assert_true(error.to_string().contains(expected))
    } noraise {
      _ => fail("invalid JSONL was accepted")
    }
  }
}

///|
test "JSONL queue retains complete batch graph validation and strict mapping" {
  for
    text in [
      queue_text().replace(old="\"blue\",\"red\"", new="\"missing\""),
      queue_text().replace(old="\"after\":[]", new="\"after\":[\"display\"]"),
      queue_text().replace(old="\"id\":\"blue\"", new="\"id\":\"left\""),
      queue_text().replace(old="\"id\":\"blue\"", new="\"id\":\"../escape\""),
      queue_text().replace(old="requests/blue.json", new="../escape.json"),
      queue_text().replace(old="[\"requests/blue.json\"]", new="[123]"),
      queue_text().replace(old="[\"requests/blue.json\"]", new="null"),
    ] {
    assert_true((try? queue_import(text)) is Err(_))
  }
  for
    (key, value) in [
      ("operation_pointer", "/operation"),
      ("contract_id", "unknown"),
      ("work_item_id_pointer", "id"),
      ("work_item_id_pointer", "/~2"),
      ("template_work_item_id_pointer", "/request/files/01"),
      ("input_artifacts_pointer", "/absent"),
    ] {
    guard queue_mapping() is Object(fields) else { fail("mapping") }
    fields[key] = value.to_json()
    assert_true(
      (try? queue_import(queue_text(), mapping=Json::object(fields))) is Err(_),
    )
  }
}

///|
test "JSONL queue enforces 256 line byte and nesting bounds" {
  let lines : Array[String] = []
  for index in 0..<256 {
    lines.push(
      (
        {
          "kind": "left",
          "id": "job-\{index}",
          "request": { "files": ["a.json"] },
          "after": [],
        } : Json).stringify(),
    )
  }
  assert_eq(queue_import(lines.join("\n") + "\n").entries.length(), 256)
  lines.push(lines[0])
  assert_true((try? queue_import(lines.join("\n"))) is Err(_))
  let small = lines[0]
  assert_true((try? queue_import(" ".repeat(1048577))) is Err(_))
  assert_true(
    (try? queue_import(small + " ".repeat(1048576 - small.length()))) is Ok(_),
  )
  assert_true(
    (try? queue_import(small + " ".repeat(1048577 - small.length()))) is Err(_),
  )
  let unicode = "{\"unused\":\"" + "茶".repeat(349526) + "\"}"
  assert_true(unicode.length() < 1048576)
  try queue_import(unicode) catch {
    error => assert_true(error.to_string().contains("UTF-8 bytes"))
  } noraise {
    _ => fail("oversize UTF-8 accepted")
  }
  let deep = "{\"kind\":\"left\",\"id\":\"deep\",\"request\":{\"files\":[\"a.json\"]},\"after\":[],\"unused\":" +
    "[".repeat(65) +
    "0" +
    "]".repeat(65) +
    "}"
  try queue_import(deep) catch {
    error => assert_true(error.to_string().contains("line 1: invalid JSON"))
  } noraise {
    _ => fail("excessive nesting accepted")
  }
}
