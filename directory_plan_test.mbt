///|
fn directory_selection() -> Json {
  {
    "contract_id": "moonflow.directory-plan-selection.v1",
    "directory_ref": "requests",
    "template_work_item_id": "left",
    "suffixes": [".json", ".request.json"],
    "recursive": true,
    "id_prefix": "request",
  }
}

///|
fn directory_import(
  paths : Array[String],
  selection? : Json = directory_selection(),
) -> @moonflow.DirectoryPlanImportV1 raise {
  @moonflow.declared_plan_from_directory_v1(
    plan_diamond_graph(),
    selection,
    paths,
    "folder-batch",
    "2026-07-31T00:00:00Z",
  )
}

///|
test "directory inventory becomes a sorted editable and preparable batch with exact source contracts" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let paths = [
    "requests/sub/blue.json", "requests/café, final.json", "requests/alpha.json",
  ]
  let imported = @moonflow.declared_plan_from_directory_v1(
    source,
    directory_selection(),
    paths,
    "folder-batch",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(imported.entries.map(entry => entry.artifact_ref), [
    "requests/alpha.json", "requests/café, final.json", "requests/sub/blue.json",
  ])
  assert_eq(paths[0], "requests/sub/blue.json")
  assert_eq(imported.inventory_digest.length(), 71)
  assert_eq(imported.selection_digest.length(), 71)
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
  for index, item in run.items {
    assert_eq(item.input_artifacts, [imported.entries[index].artifact_ref])
    assert_eq(item.work_item_id, imported.entries[index].work_item_id)
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.product_id, "moonmold")
    assert_eq(item.input_contracts, ["moonmold/spatial-operation-request@1.0.0"])
    assert_eq(item.output_contracts, [
      "moonmold/spatial-operation-receipt@1.0.0",
    ])
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.required_claim, "digital-artifact")
    assert_eq(item.acceptance_criteria, ["Review the exact left artifact"])
    assert_eq(item.timeout_ms, 60000)
    assert_eq(item.depends_on, [])
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
    assert_true(item.declaration_id != "left")
  }
  let changed = @moonflow.edit_declared_plan_item_v1(imported.draft, {
    ..imported.draft.edits[1],
    depends_on: [imported.entries[0].work_item_id],
    acceptance_criteria: ["Review the revised model"],
  })
  assert_true(
    @moonflow.prepare_declared_plan_v1(changed, catalog, "2026-07-31T00:00:00Z").preparation_id !=
    prepared.preparation_id,
  )
  assert_eq(source.stringify(), before)
}

///|
test "file identities do not depend on enumeration order or addition of earlier files" {
  let one = directory_import(["requests/z.json", "requests/a.json"])
  let two = directory_import(["requests/a.json", "requests/z.json"])
  assert_eq(one, two)
  let added = directory_import([
    "requests/0.json", "requests/a.json", "requests/z.json",
  ])
  assert_eq(added.entries[1], one.entries[0])
  assert_eq(added.entries[2], one.entries[1])
  assert_true(added.inventory_digest != one.inventory_digest)
  assert_true(one.entries[0].work_item_id.has_prefix("request-"))
  assert_eq(one.entries[0].work_item_id.length(), 72)
  let other_folder = directory_import(["requests/nested/a.json"])
  assert_true(
    other_folder.entries[0].work_item_id != one.entries[0].work_item_id,
  )
}

///|
test "literal suffixes recursion and Unicode filenames retain exact references" {
  let selection = directory_selection()
  guard selection is Object(fields)
  fields["recursive"] = false.to_json()
  let result = directory_import(
    ["requests/量表 🪑.request.json"],
    selection~,
  )
  assert_eq(result.entries[0].artifact_ref, "requests/量表 🪑.request.json")
  assert_true(
    (try? directory_import(["requests/nested/a.json"], selection~)) is Err(_),
  )
  assert_true(
    (try? directory_import(["requests/a.JSON"], selection~)) is Err(_),
  )
  assert_true(
    (try? directory_import(["requests/a.json.txt"], selection~)) is Err(_),
  )
}

///|
test "directory inventory rejects duplicates unsafe hidden outside and nonmatching paths" {
  for
    paths in [
      [],
      ["requests/a.json", "requests/a.json"],
      ["other/a.json"],
      ["requests-too/a.json"],
      ["requests/../a.json"],
      ["requests//a.json"],
      ["requests/./a.json"],
      ["requests/.hidden.json"],
      ["requests/.git/a.json"],
      ["/requests/a.json"],
      ["requests/a\\b.json"],
      ["requests/a\u{0000}.json"],
      ["requests/a.csv"],
      ["requests/"],
    ] {
    assert_true((try? directory_import(paths)) is Err(_))
  }
}

///|
test "directory selection rejects changed contract unknown fields and ambiguous filters" {
  let bad : Array[(String, Json)] = [
    ("contract_id", "other"),
    ("directory_ref", "/tmp"),
    ("directory_ref", "."),
    ("directory_ref", "requests/"),
    ("directory_ref", "requests/.hidden"),
    ("recursive", "true"),
    ("suffixes", []),
    ("suffixes", [".json", ".json"]),
    ("suffixes", ["*.json"]),
    ("suffixes", ["."]),
    ("suffixes", [".x/y"]),
    ("id_prefix", ".."),
    ("id_prefix", "a/b"),
    ("id_prefix", ""),
    ("template_work_item_id", "missing"),
    ("operation", "untrusted/run@1.0.0"),
  ]
  for (key, value) in bad {
    let selection = directory_selection()
    guard selection is Object(fields)
    fields[key] = value
    assert_true(
      (try? directory_import(["requests/a.json"], selection~)) is Err(_),
    )
  }
  let absent = directory_selection()
  guard absent is Object(fields)
  fields.remove("recursive")
  assert_true(
    (try? directory_import(["requests/a.json"], selection=absent)) is Err(_),
  )
}

///|
test "directory intake accepts 256 items and refuses a larger inventory" {
  let paths = Array::makei(256, i => "requests/\{i}.json")
  assert_eq(directory_import(paths).entries.length(), 256)
  let levels = Array::make(16, "nested").join("/")
  assert_eq(
    directory_import(["requests/" + levels + "/file.json"]).entries.length(),
    1,
  )
  assert_true(
    (try? directory_import(["requests/" + levels + "/extra/file.json"]))
    is Err(_),
  )
  paths.push("requests/overflow.json")
  assert_true((try? directory_import(paths)) is Err(_))
}

///|
test "directory intake refuses a generated ID matching an original source item" {
  let generated = directory_import(["requests/a.json"]).entries[0].work_item_id
  let source = plan_diamond_graph()
  guard source is Object(fields)
  guard fields.get("items") is Some(Array(items))
  // Rename the terminal item, which has no downstream references.
  guard items[3] is Object(item)
  item["work_item_id"] = generated.to_json()
  let result = try? @moonflow.declared_plan_from_directory_v1(
    source,
    directory_selection(),
    ["requests/a.json"],
    "folder",
    "2026-07-31T00:00:00Z",
  )
  guard result is Err(Failure(message)) else {
    fail("expected a generated source identity collision")
  }
  assert_true(
    message.contains("generated file ID conflicts with a source item"),
  )
}
