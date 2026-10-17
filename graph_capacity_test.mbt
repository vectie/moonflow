///|
fn capacity_scenario(capacity : Int) -> Json {
  {
    "contract_id": "moonflow.capacity-scenario.v1",
    "graph_id": "diamond-r1",
    "capacities": { "design": capacity, "review": 1 },
    "items": {
      "root": { "duration_seconds": 10, "demands": {} },
      "left": { "duration_seconds": 30, "demands": { "design": 1 } },
      "right": { "duration_seconds": 20, "demands": { "design": 1 } },
      "join": { "duration_seconds": 5, "demands": { "review": 1 } },
    },
  }
}

///|
fn capacity_replace_item(
  scenario : Json,
  id : String,
  replacement : Json,
) -> Unit raise {
  guard scenario is Object(fields) && fields["items"] is Object(items) else {
    fail("scenario fixture")
  }
  items[id] = replacement
}

///|
test "capacity scenario contrasts scarce and expanded capacity without mutation" {
  let graph = plan_diamond_graph()
  let scenario = capacity_scenario(1)
  let before = graph.stringify()
  let before_scenario = scenario.stringify()
  let report = @moonflow.declared_graph_capacity_v1(graph, scenario)
  assert_eq(report.unlimited_capacity_lower_bound_seconds, 45)
  assert_eq(report.scenario_duration_seconds, 65)
  assert_eq(report.additional_seconds, 20)
  assert_eq(report.items.map(item => item.start_seconds), [0, 10, 40, 60])
  assert_eq(report.items.map(item => item.dependency_ready_seconds), [
    0, 10, 10, 60,
  ])
  assert_eq(report.items.map(item => item.resource_wait_seconds), [0, 0, 30, 0])
  assert_eq(report.start_order, ["root", "left", "right", "join"])
  assert_eq(report.resources.map(resource => resource.peak_units), [1, 1])
  assert_eq(report, @moonflow.declared_graph_capacity_v1(graph, scenario))
  assert_eq(graph.stringify(), before)
  assert_eq(scenario.stringify(), before_scenario)
  let expanded = @moonflow.declared_graph_capacity_v1(
    graph,
    capacity_scenario(2),
  )
  assert_eq(expanded.scenario_duration_seconds, 45)
  assert_eq(expanded.additional_seconds, 0)
  assert_eq(expanded.items.map(item => item.start_seconds), [0, 10, 10, 40])
  assert_eq(expanded.resources.map(resource => resource.peak_units), [2, 1])
  assert_true(report.source_graph_digest.starts_with("sha256:"))
  assert_true(report.scenario_digest != expanded.scenario_digest)
  report.items[1].demands.push({ resource_id: "caller-only", units: 1, })
  assert_eq(scenario.stringify(), before_scenario)
}

///|
test "capacity allocation atomically fits multiple pools and skips blocked earlier work" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) && fields["items"] is Array(items) else {
    fail("graph fixture")
  }
  for item in items {
    guard item is Object(values) else { fail("item fixture") }
    values["depends_on"] = ([] : Array[String]).to_json()
  }
  let scenario : Json = {
    "contract_id": "moonflow.capacity-scenario.v1",
    "graph_id": "diamond-r1",
    "capacities": { "cpu": 3, "license": 1, "unused": 2 },
    "items": {
      "root": { "duration_seconds": 10, "demands": { "cpu": 2, "license": 1 } },
      "left": { "duration_seconds": 5, "demands": { "cpu": 1, "license": 1 } },
      "right": { "duration_seconds": 4, "demands": { "cpu": 1 } },
      "join": { "duration_seconds": 2, "demands": {} },
    },
  }
  let report = @moonflow.declared_graph_capacity_v1(graph, scenario)
  assert_eq(report.start_order, ["root", "right", "join", "left"])
  assert_eq(report.items.map(item => item.start_seconds), [0, 10, 0, 0])
  assert_eq(report.resources.map(resource => resource.resource_id), [
    "cpu", "license", "unused",
  ])
  assert_eq(report.resources.map(resource => resource.peak_units), [3, 1, 0])
  assert_eq(report.scenario_duration_seconds, 15)
}

///|
test "capacity allocation releases finish ties together and accepts non-topological input" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) && fields["items"] is Array(items) else {
    fail("graph")
  }
  fields["items"] = [items[3], items[2], items[1], items[0]].to_json()
  let scenario = capacity_scenario(2)
  capacity_replace_item(scenario, "right", {
    "duration_seconds": 30,
    "demands": { "design": 1 },
  })
  capacity_replace_item(scenario, "join", {
    "duration_seconds": 5,
    "demands": { "design": 2 },
  })
  let report = @moonflow.declared_graph_capacity_v1(graph, scenario)
  assert_eq(report.start_order, ["root", "right", "left", "join"])
  assert_eq(report.items.map(item => item.work_item_id), [
    "join", "right", "left", "root",
  ])
  assert_eq(report.items.map(item => item.start_seconds), [40, 10, 10, 0])
  assert_eq(report.scenario_duration_seconds, 45)
}

///|
test "capacity scenario refuses malformed infeasible and unknown demands" {
  for
    demands in (
      [
        { "design": 3 },
        { "typo": 1 },
        { "design": 0 },
        { "design": -1 },
        { "design": 0.5 },
        { "design": "1" },
        { "design": null },
        [],
        null,
      ] : Array[Json]) {
    let scenario = capacity_scenario(2)
    capacity_replace_item(scenario, "left", {
      "duration_seconds": 10,
      "demands": demands,
    })
    assert_true(
      (try? @moonflow.declared_graph_capacity_v1(plan_diamond_graph(), scenario))
      is Err(_),
    )
  }
  for value in ([0, -1, 0.5, 604801, "10", null] : Array[Json]) {
    let scenario = capacity_scenario(2)
    capacity_replace_item(scenario, "left", {
      "duration_seconds": value,
      "demands": {},
    })
    assert_true(
      (try? @moonflow.declared_graph_capacity_v1(plan_diamond_graph(), scenario))
      is Err(_),
    )
  }
}

///|
test "capacity scenario refuses missing extra and unrelated items and fields" {
  for
    replacement in (
      [
        {},
        { "duration_seconds": 5 },
        { "demands": {} },
        { "duration_seconds": 5, "demands": {}, "typo": 1 },
        null,
      ] : Array[Json]) {
    let scenario = capacity_scenario(2)
    capacity_replace_item(scenario, "left", replacement)
    assert_true(
      (try? @moonflow.declared_graph_capacity_v1(plan_diamond_graph(), scenario))
      is Err(_),
    )
  }
  for key in ["contract_id", "graph_id", "typo"] {
    let scenario = capacity_scenario(2)
    guard scenario is Object(fields) else { fail("scenario") }
    fields[key] = "wrong".to_json()
    assert_true(
      (try? @moonflow.declared_graph_capacity_v1(plan_diamond_graph(), scenario))
      is Err(_),
    )
  }
  for key in ["left", "extra"] {
    let scenario = capacity_scenario(2)
    guard scenario is Object(fields) && fields["items"] is Object(items) else {
      fail("scenario")
    }
    if key == "left" {
      items.remove(key)
    } else {
      items[key] = items["left"]
    }
    assert_true(
      (try? @moonflow.declared_graph_capacity_v1(plan_diamond_graph(), scenario))
      is Err(_),
    )
  }
}

///|
test "capacity scenario refuses invalid resources and capacity limits" {
  for
    capacities in (
      [
        {},
        [],
        { "design": 0 },
        { "design": 257 },
        { "design": 1.5 },
        { "design": "2" },
        { "../unsafe": 2 },
        { "": 2 },
      ] : Array[Json]) {
    let scenario = capacity_scenario(2)
    guard scenario is Object(fields) else { fail("scenario") }
    fields["capacities"] = capacities
    assert_true(
      (try? @moonflow.declared_graph_capacity_v1(plan_diamond_graph(), scenario))
      is Err(_),
    )
  }
  let scenario = capacity_scenario(2)
  guard scenario is Object(fields) else { fail("scenario") }
  let resources : Map[String, Json] = {}
  for i in 0..<33 {
    resources["resource-\{i}"] = (1 : Int).to_json()
  }
  fields["capacities"] = resources.to_json()
  assert_true(
    (try? @moonflow.declared_graph_capacity_v1(plan_diamond_graph(), scenario))
    is Err(_),
  )
}

///|
test "capacity scenario refuses invalid source graphs before reporting allocations" {
  for dependencies in [["missing"], ["join"], ["root"]] {
    let graph = plan_diamond_graph()
    guard graph is Object(fields) &&
      fields["items"] is Array(items) &&
      items[0] is Object(root) else {
      fail("graph")
    }
    root["depends_on"] = dependencies.to_json()
    assert_true(
      (try? @moonflow.declared_graph_capacity_v1(graph, capacity_scenario(2)))
      is Err(_),
    )
  }
}

///|
test "capacity maximum serial horizon stays bounded and rejects 257 items" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) && fields["items"] is Array(items) else {
    fail("graph")
  }
  let template = items[0].stringify()
  let specs : Map[String, Json] = {}
  let nodes = Array::makei(256, index => {
    let item = @json.parse(template)
    guard item is Object(values) else { fail("item") }
    let id = "step-\{index}"
    values["work_item_id"] = id.to_json()
    specs[id] = { "duration_seconds": 604800, "demands": { "machine": 256 } }
    item
  })
  fields["items"] = nodes.to_json()
  let scenario : Json = {
    "contract_id": "moonflow.capacity-scenario.v1",
    "graph_id": "diamond-r1",
    "capacities": { "machine": 256 },
    "items": specs.to_json(),
  }
  let report = @moonflow.declared_graph_capacity_v1(graph, scenario)
  assert_eq(report.scenario_duration_seconds, 154828800)
  assert_eq(report.unlimited_capacity_lower_bound_seconds, 604800)
  assert_eq(report.resources[0].peak_units, 256)
  let last = @json.parse(template)
  guard last is Object(last_fields) else { fail("last") }
  last_fields["work_item_id"] = "step-extra".to_json()
  nodes.push(last)
  fields["items"] = nodes.to_json()
  assert_true(
    (try? @moonflow.declared_graph_capacity_v1(graph, scenario)) is Err(_),
  )
}

///|
test "capacity allocations satisfy resource and dependency invariants across generated DAGs" {
  let template = plan_diamond_graph()
  guard template is Object(template_fields) &&
    template_fields["items"] is Array(items) else {
    fail("template")
  }
  let item_template = items[0].stringify()
  for seed in 1..<=24 {
    let graph = @json.parse(template.stringify())
    guard graph is Object(fields) else { fail("graph") }
    let specs : Map[String, Json] = {}
    let dependencies : Map[String, Array[String]] = {}
    let nodes = Array::makei(12, index => {
      let node = @json.parse(item_template)
      guard node is Object(values) else { fail("node") }
      let id = "n\{index}"
      let deps : Array[String] = []
      for previous in 0..<index {
        if (seed + index * 7 + previous * 11) % 5 == 0 {
          deps.push("n\{previous}")
        }
      }
      dependencies[id] = deps
      values["work_item_id"] = id.to_json()
      values["depends_on"] = deps.to_json()
      specs[id] = {
        "duration_seconds": 1 + (seed * 3 + index * 5) % 9,
        "demands": {
          "a": 1 + (seed + index) % 3,
          "b": 1 + (seed * 2 + index) % 2,
        },
      }
      node
    })
    fields["items"] = nodes.to_json()
    let scenario : Json = {
      "contract_id": "moonflow.capacity-scenario.v1",
      "graph_id": "diamond-r1",
      "capacities": { "a": 4, "b": 3 },
      "items": specs.to_json(),
    }
    let report = @moonflow.declared_graph_capacity_v1(graph, scenario)
    assert_eq(report.items.length(), 12)
    assert_eq(report.start_order.length(), 12)
    assert_true(report.additional_seconds >= 0)
    for item in report.items {
      for dependency in dependencies[item.work_item_id] {
        let parent = report.items.filter(other => {
            other.work_item_id == dependency
          })[0]
        assert_true(item.start_seconds >= parent.finish_seconds)
      }
      assert_eq(item.finish_seconds - item.start_seconds, item.duration_seconds)
    }
    for instant in 0..<report.scenario_duration_seconds {
      let mut a = 0
      let mut b = 0
      for item in report.items {
        if item.start_seconds <= instant && instant < item.finish_seconds {
          a += item.demands[0].units
          b += item.demands[1].units
        }
      }
      assert_true(a <= 4 && b <= 3)
    }
  }
}

///|
test "capacity CSV carries every item and hypothetical context with quoted demands" {
  let report = @moonflow.declared_graph_capacity_v1(
    plan_diamond_graph(),
    capacity_scenario(1),
  )
  let csv = @moonflow.graph_capacity_csv_v1(report)
  assert_eq(csv.split("\n").to_array().length(), 6)
  assert_true(
    csv.contains("\"diamond-r1\",\"right\",\"20\",\"10\",\"40\",\"60\",\"30\""),
  )
  assert_true(csv.contains("\"\"resource_id\"\":\"\"design\"\""))
  assert_true(csv.contains(",\"65\",\"45\"\n"))
}
