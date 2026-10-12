///|
fn timing_estimates(durations : Json) -> Json {
  {
    "contract_id": "moonflow.duration-estimates.v1",
    "graph_id": "diamond",
    "durations_seconds": durations,
  }
}

///|
test "timing diamond uses explicit estimates and identifies slack" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) else { fail("fixture") }
  fields["graph_id"] = "diamond".to_json()
  let estimates = timing_estimates({
    "root": 10,
    "left": 20,
    "right": 5,
    "join": 3,
  })
  let before = graph.stringify()
  let report = @moonflow.declared_graph_timing_v1(graph, estimates)
  assert_eq(report.minimum_duration_seconds, 33)
  assert_eq(report.items.map(item => item.earliest_start_seconds), [
    0, 10, 10, 30,
  ])
  assert_eq(report.items.map(item => item.latest_start_seconds), [0, 10, 25, 30])
  assert_eq(report.items.map(item => item.slack_seconds), [0, 0, 15, 0])
  assert_eq(report.critical_item_ids, ["root", "left", "join"])
  assert_eq(
    report.critical_edges.map(edge => {
      edge.prerequisite_item_id + ":" + edge.consumer_item_id
    }),
    ["root:left", "left:join"],
  )
  assert_eq(graph.stringify(), before)
  assert_true(report.source_graph_digest.starts_with("sha256:"))
  assert_true(report.estimates_digest.starts_with("sha256:"))
  assert_true(
    @moonflow.graph_timing_csv_v1(report).contains(
      "\"right\",\"5\",\"10\",\"15\",\"25\",\"30\",\"15\",\"false\",\"33\"",
    ),
  )
}

///|
test "timing ties zero milestones reversed order and shortcut edges" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) &&
    fields["items"] is Array(items) &&
    items[3] is Object(join) else {
    fail("fixture")
  }
  fields["graph_id"] = "diamond".to_json()
  join["depends_on"] = ["root", "left", "left", "right"].to_json()
  fields["items"] = [items[3], items[2], items[1], items[0]].to_json()
  let report = @moonflow.declared_graph_timing_v1(
    graph,
    timing_estimates({ "root": 0, "left": 20, "right": 20, "join": 0 }),
  )
  assert_eq(report.minimum_duration_seconds, 20)
  assert_eq(report.critical_item_ids, ["join", "right", "left", "root"])
  assert_eq(report.critical_edges.length(), 4)
  assert_eq(report.items.map(item => item.earliest_start_seconds), [20, 0, 0, 0])
  let zero = @moonflow.declared_graph_timing_v1(
    graph,
    timing_estimates({ "root": 0, "left": 0, "right": 0, "join": 0 }),
  )
  assert_eq(zero.minimum_duration_seconds, 0)
  assert_eq(zero.critical_edges.length(), 5)
}

///|
test "timing disconnected branches share a completion horizon" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) &&
    fields["items"] is Array(items) &&
    items[2] is Object(right) &&
    items[3] is Object(join) else {
    fail("fixture")
  }
  fields["graph_id"] = "diamond".to_json()
  right["depends_on"] = ([] : Array[String]).to_json()
  join["depends_on"] = ["left"].to_json()
  let report = @moonflow.declared_graph_timing_v1(
    graph,
    timing_estimates({ "root": 10, "left": 20, "right": 40, "join": 3 }),
  )
  assert_eq(report.minimum_duration_seconds, 40)
  assert_eq(report.items.map(item => item.slack_seconds), [7, 7, 0, 7])
  assert_eq(report.critical_item_ids, ["right"])
  assert_eq(report.critical_edges.length(), 0)
}

///|
test "timing refuses incomplete malformed and unrelated estimates" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) else { fail("fixture") }
  fields["graph_id"] = "diamond".to_json()
  for
    durations in (
      [
        { "root": 10, "left": 20, "join": 3 },
        { "root": 10, "left": 20, "right": 5, "join": 3, "typo": 1 },
        { "root": -1, "left": 20, "right": 5, "join": 3 },
        { "root": 0.5, "left": 20, "right": 5, "join": 3 },
        { "root": 604801, "left": 20, "right": 5, "join": 3 },
        { "root": "10", "left": 20, "right": 5, "join": 3 },
        { "root": null, "left": 20, "right": 5, "join": 3 },
        [],
      ] : Array[Json]) {
    assert_true(
      (try? @moonflow.declared_graph_timing_v1(
        graph,
        timing_estimates(durations),
      ))
      is Err(_),
    )
  }
  let estimates = timing_estimates({
    "root": 10,
    "left": 20,
    "right": 5,
    "join": 3,
  })
  guard estimates is Object(values) else { fail("fixture") }
  values["graph_id"] = "unrelated".to_json()
  assert_true(
    (try? @moonflow.declared_graph_timing_v1(graph, estimates)) is Err(_),
  )
  values["graph_id"] = "diamond".to_json()
  values["contract_id"] = "unknown".to_json()
  assert_true(
    (try? @moonflow.declared_graph_timing_v1(graph, estimates)) is Err(_),
  )
}

///|
test "timing handles maximum 256 node seven day chain without overflow" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) && fields["items"] is Array(items) else {
    fail("fixture")
  }
  fields["graph_id"] = "diamond".to_json()
  let template = items[0].stringify()
  let durations : Map[String, Json] = {}
  fields["items"] = Array::makei(256, index => {
    let value = @json.parse(template)
    guard value is Object(item) else { fail("fixture") }
    let id = "step-\{index}"
    item["work_item_id"] = id.to_json()
    item["depends_on"] = (
      if index == 0 {
        []
      } else {
        ["step-\{index - 1}"]
      } : Array[String]).to_json()
    durations[id] = (604800 : Int).to_json()
    value
  }).to_json()
  let report = @moonflow.declared_graph_timing_v1(
    graph,
    timing_estimates(durations.to_json()),
  )
  assert_eq(report.minimum_duration_seconds, 154828800)
  assert_eq(report.critical_item_ids.length(), 256)
  assert_eq(report.critical_edges.length(), 255)
}
