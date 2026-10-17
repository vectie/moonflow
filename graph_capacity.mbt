///|
pub(all) struct GraphCapacityDemandV1 {
  resource_id : String
  units : Int
} derive(Debug, Eq, ToJson)

///|
pub(all) struct GraphCapacityResourceV1 {
  resource_id : String
  capacity : Int
  peak_units : Int
} derive(Debug, Eq, ToJson)

///|
pub(all) struct GraphCapacityItemV1 {
  work_item_id : String
  duration_seconds : Int
  dependency_ready_seconds : Int
  start_seconds : Int
  finish_seconds : Int
  resource_wait_seconds : Int
  demands : Array[GraphCapacityDemandV1]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct GraphCapacityV1 {
  contract_id : String
  graph_id : String
  source_graph_digest : String
  scenario_digest : String
  policy : String
  unlimited_capacity_lower_bound_seconds : Int
  scenario_duration_seconds : Int
  additional_seconds : Int
  start_order : Array[String]
  resources : Array[GraphCapacityResourceV1]
  items : Array[GraphCapacityItemV1]
} derive(Debug, Eq, ToJson)

///|
fn capacity_known_fields(
  fields : Map[String, Json],
  allowed : Array[String],
  context : String,
) -> Unit raise {
  for key, _ in fields {
    guard allowed.contains(key) else {
      fail("unknown \{context} field: \{key}")
    }
  }
}

///|
fn capacity_integer(value : Json, limit : Int, context : String) -> Int raise {
  guard value is Number(number, ..) &&
    number >= 1.0 &&
    number <= limit.to_double() &&
    number.to_int().to_double() == number else {
    fail("\{context} must be an integer in 1..\{limit}")
  }
  number.to_int()
}

///|
/// Explore a non-preemptive hypothetical allocation. At each finish event,
/// release all resources, then scan ready items in source order, starting every
/// item whose complete demand fits. A blocked earlier item does not reserve
/// resources or prevent later items from starting. This deterministic greedy
/// policy is feasible, not necessarily optimal, and never advances real work.
pub fn declared_graph_capacity_v1(
  source_graph : Json,
  scenario : Json,
) -> GraphCapacityV1 raise {
  let graph = declared_graph_map_v1(source_graph)
  let fields = wire_object(scenario, "capacity scenario")
  capacity_known_fields(
    fields,
    ["contract_id", "graph_id", "capacities", "items"],
    "capacity scenario",
  )
  guard wire_string(fields, "contract_id") == "moonflow.capacity-scenario.v1" else {
    fail("expected moonflow.capacity-scenario.v1")
  }
  guard wire_string(fields, "graph_id") == graph.graph_id else {
    fail("capacity scenario graph_id does not match source graph")
  }
  let capacities = match fields.get("capacities") {
    Some(Object(values)) => values
    _ => fail("capacities must be an object")
  }
  guard capacities.length() >= 1 && capacities.length() <= 32 else {
    fail("capacity scenario requires 1..32 resources")
  }
  let resource_ids = capacities.keys().to_array()
  resource_ids.sort_by((left, right) => left.lexical_compare(right))
  let limits : Map[String, Int] = {}
  for id in resource_ids {
    guard catalog_safe_identifier(id) else {
      fail("invalid resource identifier: \{id}")
    }
    limits[id] = capacity_integer(capacities[id], 256, "capacity for \{id}")
  }
  let specs = match fields.get("items") {
    Some(Object(values)) => values
    _ => fail("capacity scenario items must be an object")
  }
  let ids = graph.nodes.map(node => node.work_item_id)
  for id, _ in specs {
    guard ids.contains(id) else { fail("unknown capacity item: \{id}") }
  }
  let durations : Map[String, Int] = {}
  let demands : Map[String, Array[GraphCapacityDemandV1]] = {}
  let timing_durations : Map[String, Json] = {}
  for node in graph.nodes {
    let id = node.work_item_id
    let spec = match specs.get(id) {
      Some(Object(value)) => value
      _ => fail("capacity item \{id} must be an object")
    }
    capacity_known_fields(
      spec,
      ["duration_seconds", "demands"],
      "capacity item \{id}",
    )
    let duration = match spec.get("duration_seconds") {
      Some(value) => capacity_integer(value, 604800, "duration for \{id}")
      _ => fail("missing duration_seconds for \{id}")
    }
    durations[id] = duration
    timing_durations[id] = duration.to_json()
    let item_demands = match spec.get("demands") {
      Some(Object(value)) => value
      _ => fail("demands for \{id} must be an object; use {} for no resources")
    }
    for resource_id, _ in item_demands {
      guard limits.contains(resource_id) else {
        fail("unknown resource \{resource_id} for \{id}")
      }
    }
    let entries : Array[GraphCapacityDemandV1] = []
    for resource_id in resource_ids {
      if item_demands.get(resource_id) is Some(value) {
        let units = capacity_integer(
          value,
          256,
          "demand for \{id}/\{resource_id}",
        )
        guard units <= limits[resource_id] else {
          fail(
            "infeasible demand for \{id}/\{resource_id}: \{units} exceeds capacity \{limits[resource_id]}",
          )
        }
        entries.push({ resource_id, units, })
      }
    }
    demands[id] = entries
  }
  let lower_bound = declared_graph_timing_v1(source_graph, {
      "contract_id": "moonflow.duration-estimates.v1",
      "graph_id": graph.graph_id,
      "durations_seconds": timing_durations.to_json(),
    }).minimum_duration_seconds
  let used : Map[String, Int] = {}
  let peaks : Map[String, Int] = {}
  for id in resource_ids {
    used[id] = 0
    peaks[id] = 0
  }
  let scheduled : Map[String, GraphCapacityItemV1] = {}
  let completed : Map[String, Bool] = {}
  let start_order : Array[String] = []
  let mut now = 0
  while completed.length() < graph.nodes.length() {
    // Finish ties release together before any next allocation.
    for node in graph.nodes {
      let id = node.work_item_id
      if !completed.contains(id) &&
        scheduled.get(id) is Some(item) &&
        item.finish_seconds == now {
        completed[id] = true
        for demand in item.demands {
          used[demand.resource_id] = used[demand.resource_id] - demand.units
        }
      }
    }
    for node in graph.nodes {
      let id = node.work_item_id
      if !scheduled.contains(id) &&
        node.depends_on.all(dependency => completed.contains(dependency)) &&
        demands[id].all(demand => {
          used[demand.resource_id] + demand.units <= limits[demand.resource_id]
        }) {
        let mut dependency_ready = 0
        for dependency in node.depends_on {
          dependency_ready = dependency_ready.max(
            scheduled[dependency].finish_seconds,
          )
        }
        for demand in demands[id] {
          let resource = demand.resource_id
          used[resource] = used[resource] + demand.units
          peaks[resource] = peaks[resource].max(used[resource])
        }
        scheduled[id] = {
          work_item_id: id,
          duration_seconds: durations[id],
          dependency_ready_seconds: dependency_ready,
          start_seconds: now,
          finish_seconds: now + durations[id],
          resource_wait_seconds: now - dependency_ready,
          demands: demands[id].copy(),
        }
        start_order.push(id)
      }
    }
    if completed.length() < graph.nodes.length() {
      let mut next : Int? = None
      for _, item in scheduled {
        if item.finish_seconds > now {
          next = Some(
            match next {
              Some(value) => value.min(item.finish_seconds)
              None => item.finish_seconds
            },
          )
        }
      }
      guard next is Some(value) else {
        fail(
          "capacity scenario cannot advance; no feasible partial report returned",
        )
      }
      now = value
    }
  }
  {
    contract_id: "moonflow.graph-capacity.v1",
    graph_id: graph.graph_id,
    source_graph_digest: graph.source_graph_digest,
    scenario_digest: plan_digest(scenario),
    policy: "source-order-greedy-nonpreemptive-v1",
    unlimited_capacity_lower_bound_seconds: lower_bound,
    scenario_duration_seconds: now,
    additional_seconds: now - lower_bound,
    start_order,
    resources: resource_ids.map(id => {
      resource_id: id,
      capacity: limits[id],
      peak_units: peaks[id],
    }),
    items: graph.nodes.map(node => scheduled[node.work_item_id]),
  }
}

///|
/// One source-order row per item; demands are a JSON-array cell. CSV quoting
/// does not prevent spreadsheet formula evaluation: import identifiers as text.
pub fn graph_capacity_csv_v1(report : GraphCapacityV1) -> String {
  let lines = [
    "graph_id,work_item_id,duration_seconds,dependency_ready_seconds,start_seconds,finish_seconds,resource_wait_seconds,demands,scenario_duration_seconds,unlimited_capacity_lower_bound_seconds",
  ]
  for item in report.items {
    lines.push(
      [
        report.graph_id,
        item.work_item_id,
        item.duration_seconds.to_string(),
        item.dependency_ready_seconds.to_string(),
        item.start_seconds.to_string(),
        item.finish_seconds.to_string(),
        item.resource_wait_seconds.to_string(),
        item.demands.to_json().stringify(),
        report.scenario_duration_seconds.to_string(),
        report.unlimited_capacity_lower_bound_seconds.to_string(),
      ]
      .map(results_csv_cell)
      .join(","),
    )
  }
  lines.join("\n") + "\n"
}
