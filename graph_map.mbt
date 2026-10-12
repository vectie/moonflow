///|
pub(all) struct DeclaredGraphNodeV1 {
  work_item_id : String
  product_id : String
  operation : String
  depends_on : Array[String]
  layer : Int
} derive(Debug, Eq, ToJson)

///|
pub(all) struct DeclaredGraphMapV1 {
  contract_id : String
  graph_id : String
  source_graph_digest : String
  nodes : Array[DeclaredGraphNodeV1]
  layers : Array[Array[String]]
  root_item_ids : Array[String]
  leaf_item_ids : Array[String]
  edge_count : Int
} derive(Debug, Eq, ToJson)

///|
/// Inspect declared topology only. Layers are longest prerequisite-path
/// lengths, not execution readiness, elapsed time, or a parallelism promise.
/// Node and within-layer order follow the source; arrays are detached.
pub fn declared_graph_map_v1(source_graph : Json) -> DeclaredGraphMapV1 raise {
  let events = events_from_work_graph(source_graph).filter(event => {
    event.kind == ItemRegistered
  })
  guard events.length() <= 256 else {
    fail("graph map source must contain at most 256 work items")
  }
  let depths : Map[String, Int] = {}
  let layers : Array[Array[String]] = []
  while depths.length() < events.length() {
    let frontier = events.filter(event => {
      !depths.contains(event.work_item_id) &&
      event.depends_on.all(id => depths.contains(id))
    })
    guard !frontier.is_empty() else { fail("graph map contains a cycle") }
    layers.push(frontier.map(event => event.work_item_id))
    for event in frontier {
      depths[event.work_item_id] = layers.length() - 1
    }
  }
  let consumers : Map[String, Bool] = {}
  let mut edge_count = 0
  for event in events {
    // Repeated prerequisites are one structural edge.
    let seen : Array[String] = []
    for id in event.depends_on {
      consumers[id] = true
      if !seen.contains(id) {
        seen.push(id)
        edge_count += 1
      }
    }
  }
  {
    contract_id: "moonflow.declared-graph-map.v1",
    graph_id: wire_string(wire_object(source_graph, "graph"), "graph_id"),
    source_graph_digest: plan_digest(source_graph),
    nodes: events.map(event => {
      let dependencies : Array[String] = []
      for id in event.depends_on {
        if !dependencies.contains(id) {
          dependencies.push(id)
        }
      }
      DeclaredGraphNodeV1::{
        work_item_id: event.work_item_id,
        product_id: event.product_id,
        operation: event.operation,
        depends_on: dependencies,
        layer: depths[event.work_item_id],
      }
    }),
    layers,
    root_item_ids: events
    .filter(event => event.depends_on.is_empty())
    .map(event => event.work_item_id),
    leaf_item_ids: events
    .filter(event => !consumers.contains(event.work_item_id))
    .map(event => event.work_item_id),
    edge_count,
  }
}

///|
fn graph_dot_quote(value : String) -> String {
  "\"" +
  value
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\r", new="\\r")
  .replace_all(old="\n", new="\\n") +
  "\""
}

///|
/// Portable Graphviz DOT; prerequisite arrows point to consumers. Generated
/// node IDs and quoted plain labels prevent declarations becoming DOT syntax.
/// No URLs, HTML labels, external images, status or execution claims are added.
pub fn declared_graph_dot_v1(source_graph : Json) -> String raise {
  let report = declared_graph_map_v1(source_graph)
  let lines = [
    "digraph moonflow {",
    "  rankdir=LR;",
    "  graph [label=" +
    graph_dot_quote(report.graph_id + "\nDeclared dependencies only") +
    ", labelloc=t];",
    "  node [shape=box];",
  ]
  let indexes : Map[String, Int] = {}
  for index, node in report.nodes {
    indexes[node.work_item_id] = index
    let label = graph_dot_quote(
      node.work_item_id + "\n" + node.product_id + "\n" + node.operation,
    )
    lines.push("  n\{index} [label=\{label}];")
  }
  for layer in report.layers {
    let ids = layer.map(id => "n\{indexes[id]};").join(" ")
    lines.push("  { rank=same; \{ids} }")
  }
  for index, node in report.nodes {
    for dependency in node.depends_on {
      let from = indexes[dependency]
      lines.push("  n\{from} -> n\{index};")
    }
  }
  lines.push("}")
  lines.join("\n")
}
