///|
test "graph map diamond preserves declarations and emits prerequisite arrows" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let report = @moonflow.declared_graph_map_v1(source)
  assert_eq(report.layers, [["root"], ["left", "right"], ["join"]])
  assert_eq(report.root_item_ids, ["root"])
  assert_eq(report.leaf_item_ids, ["join"])
  assert_eq(report.edge_count, 4)
  assert_eq(report.nodes.map(node => node.layer), [0, 1, 1, 2])
  assert_eq(
    report.nodes[1].operation,
    "moonmold/spatial.operation.execute@0.2.0",
  )
  assert_eq(report.nodes[3].depends_on, ["left", "right"])
  let dot = @moonflow.declared_graph_dot_v1(source)
  assert_true(dot.contains("n0 -> n1;"))
  assert_true(dot.contains("n0 -> n2;"))
  assert_true(dot.contains("n1 -> n3;"))
  assert_true(dot.contains("n2 -> n3;"))
  assert_true(dot.contains("{ rank=same; n1; n2; }"))
  assert_eq(source.stringify(), before)
  guard source is { "items": Array(items), .. } && items[3] is Object(join) else {
    fail("fixture")
  }
  join["depends_on"] = ["root"].to_json()
  assert_eq(report.nodes[3].depends_on, ["left", "right"])
}

///|
test "graph map uses longest path layers with shortcuts reverse order and disconnected nodes" {
  let source = plan_diamond_graph()
  guard source is Object(fields) &&
    fields["items"] is Array(items) &&
    items[3] is Object(join) &&
    items[2] is Object(right) else {
    fail("fixture")
  }
  right["depends_on"] = ([] : Array[String]).to_json()
  join["depends_on"] = ["root", "left", "left"].to_json()
  fields["items"] = [items[3], items[2], items[1], items[0]].to_json()
  let report = @moonflow.declared_graph_map_v1(source)
  assert_eq(report.layers, [["right", "root"], ["left"], ["join"]])
  assert_eq(report.nodes.map(node => node.layer), [2, 0, 1, 0])
  assert_eq(report.root_item_ids, ["right", "root"])
  assert_eq(report.leaf_item_ids, ["join", "right"])
  assert_eq(report.edge_count, 3)
  assert_eq(report.nodes[0].depends_on, ["root", "left"])
}

///|
test "graph dot quotes Unicode quotes newlines backslashes and DOT-like declarations" {
  let source = plan_diamond_graph()
  guard source is Object(fields) &&
    fields["items"] is Array(items) &&
    items[0] is Object(root) else {
    fail("fixture")
  }
  fields["graph_id"] = "図 \"review\"\\N\nnext".to_json()
  root["operation"] = "tool/\"quoted\"\\N\nUnicode λ".to_json()
  let dot = @moonflow.declared_graph_dot_v1(source)
  let expected =
    #|図 \"review\"\\N\nnext
  assert_true(dot.contains(expected))
  assert_true(dot.contains("tool/\\\"quoted\\\"\\\\N\\nUnicode λ"))
  assert_true(!dot.contains("next\nDeclared"))
}

///|
test "graph map rejects invalid sources without topology" {
  for scenario in ["cycle", "missing", "duplicate", "empty"] {
    let source = plan_diamond_graph()
    guard source is Object(fields) &&
      fields["items"] is Array(items) &&
      items[0] is Object(root) else {
      fail("fixture")
    }
    match scenario {
      "cycle" => root["depends_on"] = ["join"].to_json()
      "missing" => root["depends_on"] = ["absent"].to_json()
      "duplicate" => items.push(items[0])
      _ => fields["items"] = ([] : Array[Json]).to_json()
    }
    assert_true((try? @moonflow.declared_graph_map_v1(source)) is Err(_))
    assert_true((try? @moonflow.declared_graph_dot_v1(source)) is Err(_))
  }
}

///|
test "graph map supports singletons and bounds a full 256 item chain" {
  let source = plan_diamond_graph()
  guard source is Object(fields) && fields["items"] is Array(items) else {
    fail("fixture")
  }
  let template = items[0].stringify()
  let expanded = Array::makei(257, index => {
    let value = @json.parse(template)
    guard value is Object(item) else { fail("fixture") }
    item["work_item_id"] = "step-\{index}".to_json()
    item["depends_on"] = (
      if index == 0 {
        []
      } else {
        ["step-\{index - 1}"]
      } : Array[String]).to_json()
    value
  })
  fields["items"] = [expanded[0]].to_json()
  let singleton = @moonflow.declared_graph_map_v1(source)
  assert_eq(singleton.root_item_ids, singleton.leaf_item_ids)
  assert_eq(singleton.edge_count, 0)
  fields["items"] = expanded[:256].to_array().to_json()
  let report = @moonflow.declared_graph_map_v1(source)
  assert_eq(report.layers.length(), 256)
  assert_eq(report.nodes[255].layer, 255)
  assert_eq(report.edge_count, 255)
  fields["items"] = expanded.to_json()
  assert_true((try? @moonflow.declared_graph_map_v1(source)) is Err(_))
}
