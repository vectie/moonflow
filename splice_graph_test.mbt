///|
fn splice_fixture() -> Json {
  {
    "contract_id": "moonflow.graph-splice-input.v1",
    "graph_id": "expanded-study",
    "alias": "detail",
    "replace_item_id": "left",
    "recorded_at": "2026-07-31T00:00:00Z",
    "graph": plan_diamond_graph(),
    "module": plan_diamond_graph(),
  }
}

///|
fn splice_draft(result : Json) -> @moonflow.DeclaredPlanDraftV1 raise {
  guard result is { "graph": graph, .. } else { fail("result graph") }
  @moonflow.start_declared_plan_v1(
    graph, "expanded", "existing-graph", "2026-07-31T00:00:00Z",
  )
}

///|
test "splice expands one step then prepares and imports through the real planner" {
  let request = splice_fixture()
  let before = request.stringify()
  let result = @moonflow.splice_declared_graph_v1(request)
  assert_eq(@moonflow.splice_declared_graph_v1(request), result)
  let draft = splice_draft(result)
  assert_eq(draft.edits.map(edit => edit.work_item_id), [
    "root", "detail.root", "detail.left", "detail.right", "detail.join", "right",
    "join",
  ])
  assert_eq(draft.edits[1].depends_on, ["root"])
  assert_eq(draft.edits[4].depends_on, ["detail.left", "detail.right"])
  assert_eq(draft.edits[6].depends_on, ["detail.join", "right"])
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
  assert_eq(run.items.length(), 7)
  assert_eq(run.find_item("left"), None)
  assert_eq(run.find_item("right").unwrap().declaration_id, "right")
  for item in run.items {
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.requested_authority, "workspace-mutation")
    if item.work_item_id.has_prefix("detail.") {
      assert_true(item.declaration_id.has_prefix("splice:sha256:"))
    }
  }
  assert_eq(request.stringify(), before)
}

///|
test "splice connects every disconnected module root and terminal and preserves other prerequisites" {
  let request = splice_fixture()
  guard request is Object(fields) &&
    fields["graph"] is Object(host) &&
    host["items"] is Array(items) &&
    fields["module"] is Object(module_graph) &&
    module_graph["items"] is Array(module_items) &&
    module_items[2] is Object(right) &&
    module_items[3] is Object(join) else {
    fail("fixture")
  }
  fields["replace_item_id"] = "join"
  // Two disconnected chains are valid declared work, both must finish.
  right["depends_on"] = []
  join["depends_on"] = ["right"]
  let after = @json.parse(items[0].stringify())
  guard after is Object(after_fields) else { fail("fixture") }
  after_fields["work_item_id"] = "after"
  after_fields["declaration_id"] = "after"
  after_fields["depends_on"] = ["root", "join", "left"]
  items.push(after)
  let result = @moonflow.splice_declared_graph_v1(request)
  guard result is Object(report) else { fail("report") }
  assert_eq(report["inserted_root_ids"], ["detail.root", "detail.right"])
  assert_eq(report["inserted_terminal_ids"], ["detail.left", "detail.join"])
  assert_eq(report["inherited_prerequisite_ids"], ["left", "right"])
  let edits = splice_draft(result).edits
  assert_eq(edits[3].depends_on, ["left", "right"])
  assert_eq(edits[5].depends_on, ["left", "right"])
  assert_eq(edits[7].depends_on, ["root", "detail.left", "detail.join", "left"])
  assert_eq(report["rewired_dependents"], [
    {
      "work_item_id": "after",
      "before": ["root", "join", "left"],
      "after": ["root", "detail.left", "detail.join", "left"],
    },
  ])
}

///|
test "splice root replacement rewires every dependent and single-item replacement works" {
  let request = splice_fixture()
  guard request is Object(fields) &&
    fields["module"] is Object(module_graph) &&
    module_graph["items"] is Array(module_items) else {
    fail("fixture")
  }
  fields["replace_item_id"] = "root"
  module_graph["items"] = [module_items[0]]
  let result = @moonflow.splice_declared_graph_v1(request)
  let draft = splice_draft(result)
  assert_eq(draft.edits.length(), 4)
  assert_eq(draft.edits[0].depends_on, [])
  assert_eq(draft.edits[1].depends_on, ["detail.root"])
  assert_eq(draft.edits[2].depends_on, ["detail.root"])
  assert_eq(draft.edits[3].depends_on, ["left", "right"])
  guard result is { "rewired_dependents": Array(rewired), .. } else {
    fail("report")
  }
  assert_eq(rewired.length(), 2)
}

///|
test "splice preserves exact payload contracts and caller-owned JSON is detached" {
  let request = splice_fixture()
  guard request is Object(fields) &&
    fields["module"] is Object(module_graph) &&
    module_graph["items"] is Array(module_items) &&
    module_items[0] is Object(root) else {
    fail("fixture")
  }
  root["adapter_extension"] = {
    "opaque_item_id": "left",
    "nested": ["unchanged"],
  }
  root["acceptance_criteria"] = ["Inspect café, \"finish\"\nnext line"]
  root["timeout_ms"] = 123456
  let original = @json.parse(root.to_json().stringify())
  let result = @moonflow.splice_declared_graph_v1(request)
  guard result is { "graph": { "items": Array(items), .. }, .. } &&
    items[1] is Object(inserted) &&
    original is Object(original_fields) else {
    fail("result")
  }
  for
    field in [
      "product_id", "operation", "requested_authority", "input_contracts", "output_contracts",
      "required_claim", "input_artifacts", "acceptance_criteria", "timeout_ms", "adapter_extension",
    ] {
    assert_eq(inserted[field], original_fields[field], msg=field)
  }
  let declaration = inserted["declaration_id"]
  root["acceptance_criteria"] = ["Changed review"]
  assert_eq(
    inserted["acceptance_criteria"],
    original_fields["acceptance_criteria"],
  )
  let changed = @moonflow.splice_declared_graph_v1(request)
  guard changed is { "graph": { "items": Array(changed_items), .. }, .. } &&
    changed_items[1] is Object(changed_inserted) else {
    fail("changed result")
  }
  assert_true(changed_inserted["declaration_id"] != declaration)
  inserted["input_artifacts"] = ["modified/output-only.json"]
  assert_eq(root["input_artifacts"], ["requests/root.json"])
}

///|
test "splice refuses invalid sources targets aliases collisions and cyclic modules without mutations" {
  for
    scenario in [
      "target", "alias", "collision", "cycle", "unknown-edge", "bad-host", "empty",
      "timestamp", "same-id", "contract", "bad-operation",
    ] {
    let request = splice_fixture()
    guard request is Object(fields) &&
      fields["module"] is Object(module_graph) &&
      module_graph["items"] is Array(module_items) &&
      module_items[0] is Object(root) &&
      fields["graph"] is Object(host) &&
      host["items"] is Array(host_items) &&
      host_items[2] is Object(host_right) &&
      host_items[3] is Object(host_join) else {
      fail("fixture")
    }
    match scenario {
      "target" => fields["replace_item_id"] = "absent"
      "alias" => fields["alias"] = "../escape"
      "collision" => {
        host_right["work_item_id"] = "detail.root"
        host_join["depends_on"] = ["left", "detail.root"]
      }
      "cycle" => root["depends_on"] = ["join"]
      "unknown-edge" => root["depends_on"] = ["external"]
      "bad-host" => host_join["depends_on"] = ["absent"]
      "empty" => module_graph["items"] = []
      "timestamp" => fields["recorded_at"] = "yesterday"
      "same-id" => fields["graph_id"] = host["graph_id"]
      "contract" => fields["contract_id"] = "wrong"
      _ => root["operation"] = ""
    }
    let before = request.stringify()
    try @moonflow.splice_declared_graph_v1(request) catch {
      _ => ()
    } noraise {
      _ => fail("expected rejection: " + scenario)
    }
    assert_eq(request.stringify(), before, msg=scenario)
  }
}

///|
test "splice enforces final item bound before emitting a graph" {
  let request = splice_fixture()
  guard request is Object(fields) &&
    fields["module"] is Object(module_graph) &&
    module_graph["items"] is Array(items) else {
    fail("fixture")
  }
  let expanded : Array[Json] = []
  for i in 0..<254 {
    let item = @json.parse(items[0].stringify())
    guard item is Object(item_fields) else { fail("fixture") }
    item_fields["work_item_id"] = ("item-" + i.to_string()).to_json()
    item_fields["declaration_id"] = ("decl-" + i.to_string()).to_json()
    expanded.push(item)
  }
  module_graph["items"] = expanded.to_json()
  try @moonflow.splice_declared_graph_v1(request) catch {
    _ => ()
  } noraise {
    _ => fail("257 result items must be refused")
  }
  ignore(expanded.pop())
  module_graph["items"] = expanded.to_json()
  let result = @moonflow.splice_declared_graph_v1(request)
  assert_eq(splice_draft(result).edits.length(), 256)
}
