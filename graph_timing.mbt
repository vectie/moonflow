///|
pub(all) struct GraphTimingItemV1 {
  work_item_id : String
  duration_seconds : Int
  earliest_start_seconds : Int
  earliest_finish_seconds : Int
  latest_start_seconds : Int
  latest_finish_seconds : Int
  slack_seconds : Int
  critical : Bool
} derive(Debug, Eq, ToJson)

///|
pub(all) struct GraphTimingEdgeV1 {
  prerequisite_item_id : String
  consumer_item_id : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct GraphTimingV1 {
  contract_id : String
  graph_id : String
  source_graph_digest : String
  estimates_digest : String
  minimum_duration_seconds : Int
  items : Array[GraphTimingItemV1]
  critical_item_ids : Array[String]
  critical_edges : Array[GraphTimingEdgeV1]
} derive(Debug, Eq, ToJson)

///|
/// Offline critical-path analysis using caller-supplied estimates, unlimited
/// parallel capacity and no resource/authority/review delays. All offsets are
/// relative seconds, not scheduled wall-clock times or observed run state.
pub fn declared_graph_timing_v1(
  source_graph : Json,
  estimates : Json,
) -> GraphTimingV1 raise {
  let topology = declared_graph_map_v1(source_graph)
  let fields = wire_object(estimates, "duration estimates")
  guard wire_string(fields, "contract_id") == "moonflow.duration-estimates.v1" else {
    fail("expected moonflow.duration-estimates.v1")
  }
  guard wire_string(fields, "graph_id") == topology.graph_id else {
    fail("duration estimates graph_id does not match source graph")
  }
  let values = match fields.get("durations_seconds") {
    Some(Object(values)) => values
    _ => fail("durations_seconds must be an object")
  }
  let nodes : Map[String, DeclaredGraphNodeV1] = {}
  for node in topology.nodes {
    nodes[node.work_item_id] = node
  }
  for id, _ in values {
    guard nodes.contains(id) else { fail("unknown duration item: \{id}") }
  }
  let durations : Map[String, Int] = {}
  for node in topology.nodes {
    let id = node.work_item_id
    guard values.get(id) is Some(Number(value, ..)) &&
      value >= 0.0 &&
      value <= 604800.0 &&
      value.to_int().to_double() == value else {
      fail("duration for \{id} must be an integer in 0..604800 seconds")
    }
    durations[id] = value.to_int()
  }
  let starts : Map[String, Int] = {}
  let finishes : Map[String, Int] = {}
  let mut minimum = 0
  for layer in topology.layers {
    for id in layer {
      let mut start = 0
      for dependency in nodes[id].depends_on {
        if finishes[dependency] > start {
          start = finishes[dependency]
        }
      }
      starts[id] = start
      finishes[id] = start + durations[id]
      if finishes[id] > minimum {
        minimum = finishes[id]
      }
    }
  }
  let latest_starts : Map[String, Int] = {}
  let latest_finishes : Map[String, Int] = {}
  for index = topology.layers.length() - 1; index >= 0; index = index - 1 {
    for id in topology.layers[index] {
      let mut finish = minimum
      for consumer in topology.nodes {
        if consumer.depends_on.contains(id) &&
          latest_starts[consumer.work_item_id] < finish {
          finish = latest_starts[consumer.work_item_id]
        }
      }
      latest_finishes[id] = finish
      latest_starts[id] = finish - durations[id]
    }
  }
  let items = topology.nodes.map(node => {
    let id = node.work_item_id
    GraphTimingItemV1::{
      work_item_id: id,
      duration_seconds: durations[id],
      earliest_start_seconds: starts[id],
      earliest_finish_seconds: finishes[id],
      latest_start_seconds: latest_starts[id],
      latest_finish_seconds: latest_finishes[id],
      slack_seconds: latest_starts[id] - starts[id],
      critical: latest_starts[id] == starts[id],
    }
  })
  let critical_item_ids = items
    .filter(item => item.critical)
    .map(item => item.work_item_id)
  let critical_edges : Array[GraphTimingEdgeV1] = []
  for node in topology.nodes {
    for dependency in node.depends_on {
      if critical_item_ids.contains(node.work_item_id) &&
        critical_item_ids.contains(dependency) &&
        finishes[dependency] == starts[node.work_item_id] {
        critical_edges.push({
          prerequisite_item_id: dependency,
          consumer_item_id: node.work_item_id,
        })
      }
    }
  }
  {
    contract_id: "moonflow.graph-timing.v1",
    graph_id: topology.graph_id,
    source_graph_digest: topology.source_graph_digest,
    estimates_digest: plan_digest(estimates),
    minimum_duration_seconds: minimum,
    items,
    critical_item_ids,
    critical_edges,
  }
}

///|
/// Export one row per item, preserving source order. The graph-wide lower
/// bound is repeated to keep filtered spreadsheet rows interpretable.
pub fn graph_timing_csv_v1(report : GraphTimingV1) -> String {
  let lines = [
    "graph_id,work_item_id,duration_seconds,earliest_start_seconds,earliest_finish_seconds,latest_start_seconds,latest_finish_seconds,slack_seconds,critical,minimum_duration_seconds",
  ]
  for item in report.items {
    lines.push(
      [
        report.graph_id,
        item.work_item_id,
        item.duration_seconds.to_string(),
        item.earliest_start_seconds.to_string(),
        item.earliest_finish_seconds.to_string(),
        item.latest_start_seconds.to_string(),
        item.latest_finish_seconds.to_string(),
        item.slack_seconds.to_string(),
        item.critical.to_string(),
        report.minimum_duration_seconds.to_string(),
      ]
      .map(results_csv_cell)
      .join(","),
    )
  }
  lines.join("\n") + "\n"
}
