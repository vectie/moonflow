///|
fn composition_fixture() -> Json {
  {
    "contract_id": "moonflow.graph-composition-input.v1",
    "graph_id": "combined",
    "book_id": "synthetic-composition",
    "recorded_at": "2026-07-31T00:00:00Z",
    "sources": [
      { "alias": "model", "graph": plan_diamond_graph() },
      { "alias": "review", "graph": plan_diamond_graph() },
    ],
    "links": [{ "prerequisite": "model.join", "dependent": "review.root" }],
  }
}

///|
test "composition combines exact declarations and feeds existing editing preparation" {
  let request = composition_fixture()
  let before = request.stringify()
  let result = @moonflow.compose_declared_graph_v1(request)
  guard result is { "graph": graph, "sources": Array(sources), .. } else {
    fail("result")
  }
  let draft = @moonflow.start_declared_plan_v1(
    graph, "edit-combined", "existing-graph", "2026-07-31T00:00:00Z",
  )
  assert_eq(draft.edits.length(), 8)
  assert_eq(draft.edits[4].depends_on, ["model.join"])
  assert_eq(draft.edits[7].depends_on, ["review.left", "review.right"])
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let prepared = @moonflow.prepare_declared_plan_v1(
    draft, catalog, "2026-07-31T00:00:00Z",
  )
  let events = @moonflow.conformant_events_from_work_graph_at_v1(
    prepared.graph,
    catalog,
    "2026-07-31T00:00:00Z",
  )
  let run = @moonflow.replay(prepared.preparation_id, events)
  for item in run.items {
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
    assert_true(item.declaration_id.starts_with("composition:sha256:"))
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.requested_authority, "workspace-mutation")
  }
  assert_eq(sources.length(), 2)
  assert_eq(request.stringify(), before)
  assert_eq(@moonflow.compose_declared_graph_v1(request), result)
  let edited = @moonflow.edit_declared_plan_item_v1(draft, {
    ..draft.edits[4],
    acceptance_criteria: ["Review composed output"],
  })
  assert_eq(edited.edits[4].acceptance_criteria, ["Review composed output"])
  assert_eq(draft.edits[4].acceptance_criteria, [
    "Review the exact root artifact",
  ])
}

///|
test "composition detaches mutable inputs retains item extras and has source-sensitive lineage" {
  let request = composition_fixture()
  guard request is Object(fields) &&
    fields["sources"] is Array(sources) &&
    sources[0] is { "graph": Object(source), .. } &&
    source["items"] is Array(items) &&
    items[0] is Object(root) else {
    fail("fixture")
  }
  root["adapter_extension"] = { "exact": ["unchanged"] }
  let result = @moonflow.compose_declared_graph_v1(request)
  guard result is { "graph": Object(graph), .. } &&
    graph["items"] is Array(composed) &&
    composed[0] is Object(first) else {
    fail("result")
  }
  assert_eq(first["adapter_extension"], root["adapter_extension"])
  assert_eq(first["input_artifacts"], root["input_artifacts"])
  let identity = first["declaration_id"]
  root["acceptance_criteria"] = ["New explicit review"]
  assert_true(first["acceptance_criteria"] != root["acceptance_criteria"])
  let changed = @moonflow.compose_declared_graph_v1(request)
  guard changed is { "graph": { "items": Array(new_items), .. }, .. } &&
    new_items[0] is Object(new_first) else {
    fail("result")
  }
  assert_true(identity != new_first["declaration_id"])
}

///|
test "composition rejects ambiguous names bad links cycles source reuse and invalid graphs" {
  for
    scenario in [
      "alias", "unsafe", "missing", "same-source", "duplicate-link", "cycle", "source-id",
      "invalid-source", "timestamp", "no-sources",
    ] {
    let request = composition_fixture()
    guard request is Object(fields) &&
      fields["sources"] is Array(sources) &&
      sources[1] is Object(second) &&
      sources[0] is { "graph": Object(source), .. } &&
      source["items"] is Array(items) &&
      items[0] is Object(root) else {
      fail("fixture")
    }
    match scenario {
      "alias" => second["alias"] = "model"
      "unsafe" => second["alias"] = "../review"
      "missing" =>
        fields["links"] = [
          { "prerequisite": "model.missing", "dependent": "review.root" },
        ]
      "same-source" =>
        fields["links"] = [
          { "prerequisite": "model.root", "dependent": "model.left" },
        ]
      "duplicate-link" =>
        fields["links"] = [
          { "prerequisite": "model.join", "dependent": "review.root" },
          { "prerequisite": "model.join", "dependent": "review.root" },
        ]
      "cycle" =>
        fields["links"] = [
          { "prerequisite": "model.join", "dependent": "review.root" },
          { "prerequisite": "review.join", "dependent": "model.root" },
        ]
      "source-id" => fields["graph_id"] = source["graph_id"]
      "invalid-source" => root["depends_on"] = ["absent"]
      "timestamp" => fields["recorded_at"] = "yesterday"
      _ => fields["sources"] = []
    }
    let before = request.stringify()
    assert_true(
      (try? @moonflow.compose_declared_graph_v1(request)) is Err(_),
      msg=scenario,
    )
    assert_eq(request.stringify(), before)
  }
}

///|
test "composition permits disconnected sources and rejects aggregate overflow" {
  let request = composition_fixture()
  guard request is Object(fields) &&
    fields["sources"] is Array(sources) &&
    sources[0] is { "graph": Object(source), .. } &&
    source["items"] is Array(items) else {
    fail("fixture")
  }
  fields["links"] = []
  let result = @moonflow.compose_declared_graph_v1(request)
  guard result is { "graph": graph, .. } else { fail("result") }
  assert_eq(@moonflow.declared_graph_map_v1(graph).root_item_ids, [
    "model.root", "review.root",
  ])
  let template = items[0].stringify()
  let expanded = Array::makei(253, i => {
    let value = @json.parse(template)
    guard value is Object(item) else { fail("item") }
    item["work_item_id"] = "step-\{i}".to_json()
    item["declaration_id"] = "step-\{i}".to_json()
    value
  })
  source["items"] = expanded[:252].to_array().to_json()
  let boundary = @moonflow.compose_declared_graph_v1(request)
  guard boundary is { "graph": { "items": Array(composed), .. }, .. } else {
    fail("result")
  }
  assert_eq(composed.length(), 256)
  source["items"] = expanded.to_json()
  assert_true((try? @moonflow.compose_declared_graph_v1(request)) is Err(_))
}

///|
test "composition rejects namespace collisions even when source aliases are unique" {
  let request = composition_fixture()
  guard request is Object(fields) &&
    fields["sources"] is Array(sources) &&
    sources[0] is Object(first) &&
    sources[1] is Object(second) &&
    first["graph"] is Object(g1) &&
    second["graph"] is Object(g2) &&
    g1["items"] is Array(i1) &&
    g2["items"] is Array(i2) &&
    i1[0] is Object(root1) &&
    i2[0] is Object(root2) else {
    fail("fixture")
  }
  first["alias"] = "a"
  second["alias"] = "a.b"
  root1["work_item_id"] = "b.c"
  root2["work_item_id"] = "c"
  g1["items"] = [i1[0]].to_json()
  g2["items"] = [i2[0]].to_json()
  fields["links"] = []
  assert_true((try? @moonflow.compose_declared_graph_v1(request)) is Err(_))
}
