///|
test "route diamond includes all connecting branches and shortest witness" {
  let source = plan_diamond_graph()
  let original = source.stringify()
  let report = @moonflow.declared_graph_route_v1(source, "root", "join")
  assert_true(report.reachable)
  assert_eq(report.shortest_distance, Some(2))
  assert_eq(report.shortest_path, ["root", "left", "join"])
  assert_eq(report.corridor_item_ids, ["root", "left", "right", "join"])
  assert_eq(report.corridor_edges.length(), 4)
  assert_eq(report.outside_prerequisite_edges.length(), 0)
  assert_eq(source.stringify(), original)
  let branch = @moonflow.declared_graph_route_v1(source, "left", "join")
  assert_eq(branch.corridor_item_ids, ["left", "join"])
  assert_eq(
    branch.outside_prerequisite_edges.map(e => {
      (e.prerequisite_id, e.consumer_id)
    }),
    [("root", "left"), ("right", "join")],
  )
}

///|
test "route distinguishes direction disconnection and zero edge identity" {
  let source = plan_diamond_graph()
  for pair in [("join", "root"), ("left", "right")] {
    let report = @moonflow.declared_graph_route_v1(source, pair.0, pair.1)
    assert_true(!report.reachable)
    assert_eq(report.shortest_distance, None)
    assert_true(report.to_json() is { "shortest_distance": Null, .. })
    assert_eq(report.shortest_path, [])
    assert_eq(report.corridor_item_ids, [])
    assert_eq(report.corridor_edges, [])
    assert_eq(report.outside_prerequisite_edges, [])
    assert_true(
      @moonflow.declared_graph_route_text_v1(report).contains(
        "No declared dependency route",
      ),
    )
  }
  let report = @moonflow.declared_graph_route_v1(source, "left", "left")
  assert_true(report.reachable)
  assert_eq(report.shortest_distance, Some(0))
  assert_eq(report.shortest_path, ["left"])
  assert_eq(report.corridor_item_ids, ["left"])
  assert_eq(report.outside_prerequisite_edges.length(), 1)
}

///|
test "route source order ties shortcuts duplicates and independent report arrays" {
  let source = plan_diamond_graph()
  guard source is Object(fields) &&
    fields["items"] is Array(items) &&
    items[3] is Object(join) else {
    fail("fixture")
  }
  fields["items"] = [items[3], items[2], items[1], items[0]].to_json()
  let reversed = @moonflow.declared_graph_route_v1(source, "root", "join")
  assert_eq(reversed.shortest_path, ["root", "right", "join"])
  assert_eq(reversed.corridor_item_ids, ["join", "right", "left", "root"])
  join["depends_on"] = ["root", "left", "left"].to_json()
  let shortcut = @moonflow.declared_graph_route_v1(source, "root", "join")
  assert_eq(shortcut.shortest_distance, Some(1))
  assert_eq(shortcut.shortest_path, ["root", "join"])
  assert_eq(shortcut.corridor_item_ids, ["join", "left", "root"])
  assert_eq(shortcut.corridor_edges.length(), 3)
  assert_eq(reversed.corridor_edges.length(), 4)
}

///|
test "route validates complete graph and both endpoints" {
  let source = plan_diamond_graph()
  for pair in [("missing", "join"), ("root", "missing"), ("", "join")] {
    assert_true(
      (try? @moonflow.declared_graph_route_v1(source, pair.0, pair.1)) is Err(_),
    )
  }
  guard source is Object(fields) &&
    fields["items"] is Array(items) &&
    items[2] is Object(right) else {
    fail("fixture")
  }
  right["depends_on"] = ["right"].to_json()
  assert_true(
    (try? @moonflow.declared_graph_route_v1(source, "root", "left")) is Err(_),
  )
}
