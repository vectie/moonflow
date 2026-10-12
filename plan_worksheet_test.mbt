///|
fn worksheet_cell(value : String) -> String {
  "\"" + value.replace_all(old="\"", new="\"\"") + "\""
}

///|
fn worksheet_rows(
  source : Json,
  edits : Array[@moonflow.PlanItemEditV1],
) -> String raise {
  let original = @moonflow.start_declared_plan_v1(
    source, "worksheet", "existing-graph", "2026-07-31T00:00:00Z",
  )
  let items = @moonflow.events_from_work_graph(source).filter(event => {
    event.kind == @moonflow.ItemRegistered
  })
  let rows = [
    "source_graph_digest,work_item_id,product_id,operation,input_artifacts,depends_on,acceptance_criteria,timeout_ms",
  ]
  for edit in edits {
    let item = items
      .filter(item => item.work_item_id == edit.work_item_id)
      .get(0)
      .unwrap()
    rows.push(
      [
        original.source_graph_digest,
        edit.work_item_id,
        item.product_id,
        item.operation,
        edit.input_artifacts.to_json().stringify(),
        edit.depends_on.to_json().stringify(),
        edit.acceptance_criteria.to_json().stringify(),
        edit.timeout_ms.to_string(),
      ]
      .map(worksheet_cell)
      .join(","),
    )
  }
  rows.join("\n") + "\n"
}

///|
fn worksheet_import(
  source : Json,
  csv : String,
) -> @moonflow.PlanWorksheetImportV1 raise {
  @moonflow.declared_plan_from_worksheet_v1(
    source, csv, "worksheet", "2026-07-31T00:00:00Z",
  )
}

///|
test "worksheet lossless export and import preserve every declared field" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) &&
    fields["items"] is Array(items) &&
    items[1] is Object(left) else {
    fail("fixture")
  }
  left["acceptance_criteria"] = [
    "  Check café, \"☾\" and \\ paths\r\nsecond line  ",
  ].to_json()
  left["input_artifacts"] = ["requests/逗号, quote\".json"].to_json()
  let before = graph.stringify()
  let csv = @moonflow.declared_plan_worksheet_csv_v1(graph)
  let imported = worksheet_import(graph, csv)
  assert_eq(imported.changed_item_ids, [])
  assert_eq(imported.row_count, 4)
  assert_eq(imported.csv_digest.length(), 71)
  assert_eq(
    imported.draft,
    @moonflow.start_declared_plan_v1(
      graph, "worksheet", "existing-graph", "2026-07-31T00:00:00Z",
    ),
  )
  assert_eq(@moonflow.declared_plan_worksheet_csv_v1(graph), csv)
  assert_eq(graph.stringify(), before)
}

///|
test "worksheet atomic rewiring edits inputs criteria timeout and prepares existing declarations" {
  let graph = plan_diamond_graph()
  let original = plan_draft()
  // Reverse the root-left edge in one edit set: either single-step edit would
  // temporarily make a cycle or would not yet describe the requested graph.
  let edits = original.edits.map(edit => {
    match edit.work_item_id {
      "root" => { ..edit, depends_on: ["left"], }
      "left" =>
        {
          ..edit,
          depends_on: [],
          input_artifacts: ["requests/left-v2.json"],
          acceptance_criteria: ["Review revised left"],
          timeout_ms: 90000,
        }
      _ => edit
    }
  })
  assert_true(
    (try? @moonflow.edit_declared_plan_item_v1(original, edits[0])) is Err(_),
  )
  let imported = worksheet_import(graph, worksheet_rows(graph, edits))
  assert_eq(imported.changed_item_ids, ["root", "left"])
  let prepared = @moonflow.prepare_declared_plan_v1(
    imported.draft,
    @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
    "2026-07-31T00:00:00Z",
  )
  let projection = @moonflow.replay(
    prepared.preparation_id,
    @moonflow.events_from_work_graph(prepared.graph),
  )
  assert_eq(projection.find_item("root").unwrap().depends_on, ["left"])
  let left = projection.find_item("left").unwrap()
  assert_eq(left.declaration_id, "left")
  assert_eq(left.input_artifacts, ["requests/left-v2.json"])
  assert_eq(left.acceptance_criteria, ["Review revised left"])
  assert_eq(left.timeout_ms, 90000)
  assert_eq(left.depends_on, [])
  for item in projection.items {
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.declaration_id, item.work_item_id)
  }
  assert_eq(
    @moonflow.decode_declared_plan_draft_v1(imported.draft.to_json()),
    imported.draft,
  )
}

///|
test "worksheet sorted rows and reordered columns BOM CRLF normalize to source order" {
  let graph = plan_diamond_graph()
  let original = plan_draft()
  let csv = worksheet_rows(graph, [
    original.edits[3],
    original.edits[1],
    original.edits[0],
    original.edits[2],
  ])
  let sorted = worksheet_import(
    graph,
    "\u{FEFF}" + csv.replace_all(old="\n", new="\r\n"),
  )
  let normal = worksheet_import(
    graph,
    @moonflow.declared_plan_worksheet_csv_v1(graph),
  )
  assert_eq(sorted.draft, normal.draft)
  assert_eq(sorted.changed_item_ids, [])
  assert_true(sorted.csv_digest != normal.csv_digest)
  // Move the digest column to the end; all data rows start with one quoted digest.
  let lines = csv
    .trim_end()
    .to_string()
    .split("\n")
    .map(line => {
      let parts = line.split(",").collect()
      let first = parts.remove(0)
      parts.push(first)
      parts.join(",")
    })
    .collect()
  assert_eq(
    worksheet_import(graph, lines.join("\n") + "\n").draft,
    normal.draft,
  )
}

///|
test "worksheet heterogeneous operations are retained without catalog access" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) &&
    fields["items"] is Array(items) &&
    items[3] is Object(join) else {
    fail("fixture")
  }
  join["product_id"] = "local-export"
  join["operation"] = "local-export/package@1.0.0"
  join["input_contracts"] = ["local-export/request@1.0.0"].to_json()
  join["output_contracts"] = ["local-export/result@1.0.0"].to_json()
  let imported = worksheet_import(
    graph,
    @moonflow.declared_plan_worksheet_csv_v1(graph),
  )
  assert_eq(imported.changed_item_ids, [])
  let form = @moonflow.declared_plan_form_v1(imported.draft)
  guard form is Object(form_fields) && form_fields["items"] is Array(form_items) else {
    fail("form")
  }
  assert_eq(form_items[3], items[3])
}

///|
test "worksheet rejects changed source immutable columns and incomplete item sets" {
  let graph = plan_diamond_graph()
  let csv = @moonflow.declared_plan_worksheet_csv_v1(graph)
  let edits = plan_draft().edits
  for
    bad in [
      csv.replace_all(old="moonmold", new="other-product"),
      csv.replace_all(old="execute@0.2.0", new="execute@0.3.0"),
      csv.replace_all(old="\"left\"", new="\"renamed\""),
      worksheet_rows(graph, [edits[0], edits[1], edits[2]]),
      worksheet_rows(graph, [edits[0], edits[1], edits[2], edits[2]]),
    ] {
    assert_true((try? worksheet_import(graph, bad)) is Err(_))
  }
  guard graph is Object(fields) else { fail("graph") }
  fields["source_digest"] = "sha256:changed"
  assert_true((try? worksheet_import(graph, csv)) is Err(_))
}

///|
test "worksheet validates complete dependency edits and typed array cells" {
  let graph = plan_diamond_graph()
  let original = plan_draft()
  for
    bad_edit in [
      { ..original.edits[0], depends_on: ["join"], },
      { ..original.edits[0], depends_on: ["missing"], },
      { ..original.edits[0], input_artifacts: ["../escape.json"], },
      { ..original.edits[0], input_artifacts: [], },
      { ..original.edits[0], acceptance_criteria: [], },
      { ..original.edits[0], timeout_ms: 0, },
      { ..original.edits[0], timeout_ms: 86400001, },
    ] {
    let edits = [
      bad_edit,
      original.edits[1],
      original.edits[2],
      original.edits[3],
    ]
    assert_true(
      (try? worksheet_import(graph, worksheet_rows(graph, edits))) is Err(_),
    )
  }
  let csv = @moonflow.declared_plan_worksheet_csv_v1(graph)
  for
    replacement in [
      "", "null", "{}", "[1]", "[\"unterminated]", "[true]", "[[\"nested\"]]",
    ] {
    let bad = csv.replace_all(old="\"[]\"", new=worksheet_cell(replacement))
    assert_true((try? worksheet_import(graph, bad)) is Err(_))
  }
  for timeout in ["-1", "1.5", "1e3", "", "999999999999999999999"] {
    assert_true(
      (try? worksheet_import(
        graph,
        csv.replace_all(old="\"60000\"", new=worksheet_cell(timeout)),
      ))
      is Err(_),
    )
  }
}

///|
test "worksheet malformed headers records and over-limit CSV fail entirely" {
  let graph = plan_diamond_graph()
  let csv = @moonflow.declared_plan_worksheet_csv_v1(graph)
  for
    bad in [
      csv.replace_all(old="input_artifacts,", new="unknown,"),
      csv.replace_all(old="input_artifacts,", new="depends_on,"),
      "work_item_id\nroot\n",
      csv + "\n",
      csv + "\"unterminated",
      csv.replace_all(old="\"60000\"", new="\"60000\",extra"),
      "x".repeat(1048577),
    ] {
    assert_true((try? worksheet_import(graph, bad)) is Err(_))
  }
}

///|
test "worksheet supports 256 source items and refuses a larger graph" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) && fields["items"] is Array(items) else {
    fail("fixture")
  }
  let template = items[0].stringify()
  let many : Array[Json] = []
  for index in 0..<256 {
    let item = @json.parse(template)
    guard item is Object(row) else { fail("row") }
    row["work_item_id"] = ("item-" + index.to_string()).to_json()
    row["declaration_id"] = ("declaration-" + index.to_string()).to_json()
    many.push(item)
  }
  fields["items"] = many.to_json()
  let csv = @moonflow.declared_plan_worksheet_csv_v1(graph)
  let imported = worksheet_import(graph, csv)
  assert_eq(imported.row_count, 256)
  assert_eq(imported.changed_item_ids, [])
  let extra = @json.parse(template)
  guard extra is Object(row) else { fail("row") }
  row["work_item_id"] = "extra"
  row["declaration_id"] = "extra"
  many.push(extra)
  fields["items"] = many.to_json()
  assert_true((try? @moonflow.declared_plan_worksheet_csv_v1(graph)) is Err(_))
  assert_true((try? worksheet_import(graph, csv)) is Err(_))
}

///|
test "worksheet imported draft is detached from caller graph and repeated import is deterministic" {
  let source = plan_diamond_graph()
  let csv = @moonflow.declared_plan_worksheet_csv_v1(source)
  let first = worksheet_import(source, csv)
  assert_eq(worksheet_import(source, csv), first)
  let retained = first.draft.to_json().stringify()
  guard source is Object(fields) &&
    fields["items"] is Array(items) &&
    items[0] is Object(root) else {
    fail("fixture")
  }
  root["timeout_ms"] = 70000
  assert_eq(first.draft.to_json().stringify(), retained)
}

///|
test "worksheet quoted identity cells preserve embedded CRLF and literal carriage returns" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) &&
    fields["items"] is Array(items) &&
    items[3] is Object(join) else {
    fail("fixture")
  }
  join["work_item_id"] = "join\r\nbranch\rtail"
  join["operation"] = "local/quoted\r\noperation@1.0.0"
  let imported = worksheet_import(
    graph,
    @moonflow.declared_plan_worksheet_csv_v1(graph),
  )
  assert_eq(imported.changed_item_ids, [])
  assert_eq(imported.draft.edits[3].work_item_id, "join\r\nbranch\rtail")
}
