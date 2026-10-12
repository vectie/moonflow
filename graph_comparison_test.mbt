///|
test "graph comparison discovers edits and impacts without importing runs" {
  let before = plan_diamond_graph()
  let after = plan_diamond_graph()
  guard after is Object(graph) &&
    graph["items"] is Array(items) &&
    items[1] is Object(left) else {
    fail("fixture")
  }
  graph["graph_id"] = "diamond-r2".to_json()
  graph["declaration_revision"] = "r2".to_json()
  left["input_artifacts"] = ["requests/left-v2.json"].to_json()
  left["timeout_ms"] = (90000 : Int).to_json()
  let before_bytes = before.stringify()
  let after_bytes = after.stringify()
  let report = @moonflow.compare_declared_graphs_v1(before, after)
  assert_eq(report.items.map(item => item.change), [
    "unchanged", "changed", "unchanged", "unchanged",
  ])
  assert_eq(report.items[1].fields.map(field => field.field), [
    "input_artifacts", "timeout_ms",
  ])
  assert_eq(report.graph_fields.map(field => field.field), [
    "declaration_revision", "graph_id",
  ])
  assert_eq(report.before_impact.changed_item_ids, ["left"])
  assert_eq(report.after_impact.affected_items.map(item => item.work_item_id), [
    "join",
  ])
  assert_eq(report.after_impact.unaffected_item_ids, ["root", "right"])
  assert_true(report.before_graph_digest != report.after_graph_digest)
  assert_eq(before.stringify(), before_bytes)
  assert_eq(after.stringify(), after_bytes)
  left["input_artifacts"] = ["caller-changed.json"].to_json()
  assert_true(
    report.items[1].after
    is { "input_artifacts": ["requests/left-v2.json"], .. },
  )
  assert_true(
    @moonflow.declared_graph_comparison_text_v1(report).contains(
      "requests/left-v2.json",
    ),
  )
}

///|
test "graph comparison preserves lineage across rename and reused names" {
  let before = plan_diamond_graph()
  let after = plan_diamond_graph()
  guard after is Object(graph) &&
    graph["items"] is Array(items) &&
    items[1] is Object(left) &&
    items[2] is Object(right) &&
    items[3] is Object(join) else {
    fail("fixture")
  }
  left["work_item_id"] = "renamed".to_json()
  right["declaration_id"] = "replacement".to_json()
  join["depends_on"] = ["renamed", "right"].to_json()
  let report = @moonflow.compare_declared_graphs_v1(before, after)
  assert_eq(report.items.map(item => item.change), [
    "unchanged", "changed", "removed", "changed", "added",
  ])
  assert_eq(report.items[1].declaration_id, "left")
  assert_true(report.items[2].after is Null)
  assert_true(report.items[4].before is Null)
  assert_eq(report.before_impact.changed_item_ids, ["left", "right", "join"])
  assert_eq(report.after_impact.changed_item_ids, ["renamed", "right", "join"])
  assert_true(report.declaration_order_changed)
}

///|
test "graph comparison distinguishes null absent unknown metadata and ordered arrays" {
  let before = plan_diamond_graph()
  let after = plan_diamond_graph()
  guard before is Object(old) &&
    old["items"] is Array(old_items) &&
    old_items[0] is Object(root_before) &&
    after is Object(next) &&
    next["items"] is Array(items) &&
    items[0] is Object(root_after) else {
    fail("fixture")
  }
  root_before["extension"] = { "b": 2, "a": 1 }
  root_after["extension"] = { "a": 1, "b": 2 }
  root_after["notes"] = Json::null()
  next["items"] = [items[3], items[2], items[1], items[0]].to_json()
  let report = @moonflow.compare_declared_graphs_v1(before, after)
  assert_eq(report.items[0].fields.map(field => field.field), ["notes"])
  assert_eq(report.items[0].fields[0].before_present, false)
  assert_eq(report.items[0].fields[0].after_present, true)
  assert_true(report.items[0].fields[0].before is Null)
  assert_true(report.items[0].fields[0].after is Null)
  assert_true(report.declaration_order_changed)
  assert_true(
    @moonflow.declared_graph_comparison_text_v1(report).contains(
      "<absent> -> null",
    ),
  )
  let same = @moonflow.compare_declared_graphs_v1(before, before)
  assert_true(same.items.all(item => item.change == "unchanged"))
  assert_eq(same.before_impact.changed_item_ids, [])
  assert_eq(same.before_graph_digest, same.after_graph_digest)
}

///|
test "graph comparison tracks removal in old edges and added downstream in new edges" {
  let before = plan_diamond_graph()
  let after = plan_diamond_graph()
  guard after is Object(graph) &&
    graph["items"] is Array(items) &&
    items[3] is Object(join) else {
    fail("fixture")
  }
  join["depends_on"] = ["right"].to_json()
  graph["items"] = [items[0], items[2], items[3]].to_json()
  let report = @moonflow.compare_declared_graphs_v1(before, after)
  assert_eq(report.items[1].change, "removed")
  assert_eq(report.before_impact.changed_item_ids, ["left", "join"])
  assert_eq(report.after_impact.changed_item_ids, ["join"])
  assert_eq(report.after_impact.unaffected_item_ids, ["root", "right"])
}

///|
test "graph comparison refuses unrelated ambiguous malformed and oversized declarations" {
  let before = plan_diamond_graph()
  for mode in ["book", "duplicate", "cycle", "missing", "timeout", "many"] {
    let after = plan_diamond_graph()
    guard after is Object(graph) &&
      graph["items"] is Array(items) &&
      items[0] is Object(root) &&
      items[1] is Object(left) else {
      fail("fixture")
    }
    match mode {
      "book" => graph["book_id"] = "other".to_json()
      "duplicate" => left["declaration_id"] = "root".to_json()
      "cycle" => root["depends_on"] = ["join"].to_json()
      "missing" => left["depends_on"] = ["absent"].to_json()
      "timeout" => left["timeout_ms"] = (1.5 : Double).to_json()
      _ => graph["items"] = Array::make(257, items[0]).to_json()
    }
    assert_true(
      (try? @moonflow.compare_declared_graphs_v1(before, after)) is Err(_),
    )
    assert_true(
      (try? @moonflow.compare_declared_graphs_v1(after, before)) is Err(_),
    )
  }
}
