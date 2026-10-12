///|
test "change impact follows consumers and preserves source and caller arrays" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let changed = ["left"]
  let report = @moonflow.declared_change_impact_v1(source, changed)
  changed.push("right")
  assert_eq(report.changed_item_ids, ["left"])
  assert_eq(report.unaffected_item_ids, ["root", "right"])
  assert_eq(report.affected_items.length(), 1)
  assert_eq(report.affected_items[0].work_item_id, "join")
  assert_eq(report.affected_items[0].dependency_distance, 1)
  assert_eq(report.affected_items[0].impacted_prerequisite_ids, ["left"])
  assert_eq(source.stringify(), before)
  let leaf = @moonflow.declared_change_impact_v1(source, ["join"])
  assert_eq(leaf.affected_items, [])
  assert_eq(leaf.unaffected_item_ids, ["root", "left", "right"])
}

///|
test "change impact handles diamonds multiple changes and unordered sources" {
  let source = plan_diamond_graph()
  let root = @moonflow.declared_change_impact_v1(source, ["root"])
  assert_eq(root.affected_items.map(item => item.dependency_distance), [1, 1, 2])
  assert_eq(root.affected_items[2].impacted_prerequisite_ids, ["left", "right"])
  let both = @moonflow.declared_change_impact_v1(source, ["left", "root"])
  assert_eq(both, @moonflow.declared_change_impact_v1(source, ["root", "left"]))
  assert_eq(both.changed_item_ids, ["root", "left"])
  assert_eq(both.affected_items.map(item => item.dependency_distance), [1, 1])
  guard source is Object(fields) && fields["items"] is Array(items) else {
    fail("fixture")
  }
  fields["items"] = [items[3], items[2], items[1], items[0]].to_json()
  let reversed = @moonflow.declared_change_impact_v1(source, ["root"])
  assert_eq(reversed.affected_items.map(item => item.work_item_id), [
    "join", "right", "left",
  ])
  assert_eq(reversed.affected_items.map(item => item.dependency_distance), [
    2, 1, 1,
  ])
  assert_true(reversed.source_graph_digest != root.source_graph_digest)
}

///|
test "change impact rejects missing duplicate blank selection and invalid graph" {
  for ids in [[], ["missing"], ["left", "left"], [""]] {
    assert_true(
      (try? @moonflow.declared_change_impact_v1(plan_diamond_graph(), ids))
      is Err(_),
    )
  }
  for dependencies in [["missing"], ["join"]] {
    let source = plan_diamond_graph()
    guard source is { "items": Array(items), .. } && items[2] is Object(right) else {
      fail("fixture")
    }
    right["depends_on"] = dependencies.to_json()
    assert_true(
      (try? @moonflow.declared_change_impact_v1(source, ["left"])) is Err(_),
    )
  }
}

///|
test "change impact bounds and follows a 256 item chain" {
  let source = plan_diamond_graph()
  guard source is Object(fields) && fields["items"] is Array(items) else {
    fail("fixture")
  }
  let template = items[0].stringify()
  let expanded = Array::makei(257, index => {
    let value = @json.parse(template)
    guard value is Object(item) else { fail("fixture") }
    item["work_item_id"] = "step-\{index}".to_json()
    item["declaration_id"] = "step-\{index}".to_json()
    item["depends_on"] = (
      if index == 0 {
        []
      } else {
        ["step-\{index - 1}"]
      } : Array[String]).to_json()
    value
  })
  fields["items"] = expanded[:256].to_array().to_json()
  let report = @moonflow.declared_change_impact_v1(source, ["step-0"])
  assert_eq(report.affected_items.length(), 255)
  assert_eq(report.affected_items[254].dependency_distance, 255)
  fields["items"] = expanded.to_json()
  assert_true(
    (try? @moonflow.declared_change_impact_v1(source, ["step-0"])) is Err(_),
  )
}
