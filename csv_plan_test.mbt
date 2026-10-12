///|
fn batch_csv() -> String {
  (
    #|work_item_id,input_artifacts,depends_on,acceptance_criteria,timeout_ms
    #|stool-red,requests/red.json,,"Review red stool, including its joints",45000
    #|stool-blue,requests/blue.json,,, 
    #|display,"requests/display.json
    #|references/room.json","stool-red
    #|stool-blue","Review the assembled display
    #|Check both stools are visible",90000
    #|
  )
}

///|
test "CSV batch expands exact operation inputs and dependencies into an editable prepared graph" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let imported = @moonflow.declared_plan_from_csv_v1(
    source,
    "left",
    batch_csv(),
    "furniture-batch",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(imported.row_count, 3)
  assert_eq(imported.csv_digest.length(), 71)
  let draft = @moonflow.decode_declared_plan_draft_v1(imported.draft.to_json())
  assert_eq(draft, imported.draft)
  assert_eq(draft.edits[1].timeout_ms, 60000)
  assert_eq(draft.edits[1].acceptance_criteria, [
    "Review the exact left artifact",
  ])
  let prepared = @moonflow.prepare_declared_plan_v1(
    draft,
    @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
    "2026-07-31T00:00:00Z",
  )
  let events = @moonflow.events_from_work_graph(prepared.graph)
  let run = @moonflow.replay(prepared.preparation_id, events)
  assert_eq(run.items.length(), 3)
  assert_true(run.find_item("left") is None)
  let display = run.find_item("display").unwrap()
  assert_eq(display.depends_on, ["stool-red", "stool-blue"])
  assert_eq(display.input_artifacts, [
    "requests/display.json", "references/room.json",
  ])
  assert_eq(display.acceptance_criteria.length(), 2)
  assert_eq(run.find_item("stool-red").unwrap().depends_on, [])
  for item in run.items {
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.product_id, "moonmold")
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.required_claim, "digital-artifact")
    assert_eq(item.input_contracts, ["moonmold/spatial-operation-request@1.0.0"])
    assert_eq(item.output_contracts, [
      "moonmold/spatial-operation-receipt@1.0.0",
    ])
    assert_true(item.declaration_id != "left")
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
  }
  assert_true(run.items[0].declaration_id != run.items[1].declaration_id)
  let changed = @moonflow.edit_declared_plan_item_v1(draft, {
    ..draft.edits[0],
    input_artifacts: ["requests/revised-red.json"],
  })
  let revised = @moonflow.prepare_declared_plan_v1(
    changed,
    @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
    "2026-07-31T00:00:00Z",
  )
  assert_true(revised.preparation_id != prepared.preparation_id)
  assert_eq(source.stringify(), before)
}

///|
test "CSV spreadsheet BOM CRLF reordered columns and doubled quotes remain useful values" {
  let csv = "\u{FEFF}acceptance_criteria,input_artifacts,work_item_id\r\n\"Check \"\"café\"\" sign, plus finish\r\nCheck legs\",\"requests/café, final.json\",sign\r\n"
  let imported = @moonflow.declared_plan_from_csv_v1(
    plan_diamond_graph(),
    "left",
    csv,
    "signs",
    "2026-07-31T00:00:00Z",
  )
  let edit = imported.draft.edits[0]
  assert_eq(edit.work_item_id, "sign")
  assert_eq(edit.input_artifacts, ["requests/café, final.json"])
  assert_eq(edit.acceptance_criteria, [
    "Check \"café\" sign, plus finish", "Check legs",
  ])
}

///|
test "CSV repeated import and normal prepare are deterministic" {
  let first = @moonflow.declared_plan_from_csv_v1(
    plan_diamond_graph(),
    "left",
    batch_csv(),
    "batch",
    "2026-07-31T00:00:00Z",
  )
  let second = @moonflow.declared_plan_from_csv_v1(
    plan_diamond_graph(),
    "left",
    batch_csv(),
    "batch",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(first, second)
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  assert_eq(
    @moonflow.prepare_declared_plan_v1(
      first.draft,
      catalog,
      "2026-07-31T00:00:00Z",
    ),
    @moonflow.prepare_declared_plan_v1(
      second.draft,
      catalog,
      "2026-07-31T00:00:00Z",
    ),
  )
}

///|
test "CSV malformed table and invalid complete batches are rejected before a draft exists" {
  for
    csv in [
      "work_item_id,input_artifacts\na,\"unterminated", "work_item_id,input_artifacts\na,requests/a.json,unexpected\n",
      "work_item_id,input_artifacts,operation\na,requests/a.json,other\n", "work_item_id,input_artifacts\nleft,requests/a.json\n",
      "work_item_id,input_artifacts,depends_on\na,requests/a.json,b\nb,requests/b.json,a\n",
      "work_item_id,input_artifacts,depends_on\na,requests/a.json,not-in-batch\n",
      "work_item_id,input_artifacts\na,../escape.json\n",
    ] {
    assert_true(
      (try? @moonflow.declared_plan_from_csv_v1(
        plan_diamond_graph(),
        "left",
        csv,
        "invalid",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}
