///|
pub(all) struct DeclaredRouteEdgeV1 {
  prerequisite_id : String
  consumer_id : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct DeclaredGraphRouteV1 {
  contract_id : String
  graph_id : String
  source_graph_digest : String
  from_item_id : String
  to_item_id : String
  reachable : Bool
  shortest_distance : Int?
  shortest_path : Array[String]
  corridor_item_ids : Array[String]
  corridor_edges : Array[DeclaredRouteEdgeV1]
  outside_prerequisite_edges : Array[DeclaredRouteEdgeV1]
} derive(Debug, Eq)

///|
pub impl ToJson for DeclaredGraphRouteV1 with fn to_json(self) -> Json {
  {
    "contract_id": self.contract_id,
    "graph_id": self.graph_id,
    "source_graph_digest": self.source_graph_digest,
    "from_item_id": self.from_item_id,
    "to_item_id": self.to_item_id,
    "reachable": self.reachable,
    "shortest_distance": self.shortest_distance
    .map(n => n.to_json())
    .unwrap_or(Json::null()),
    "shortest_path": self.shortest_path.to_json(),
    "corridor_item_ids": self.corridor_item_ids.to_json(),
    "corridor_edges": self.corridor_edges.to_json(),
    "outside_prerequisite_edges": self.outside_prerequisite_edges.to_json(),
  }
}

///|
/// Explain declared prerequisite-to-consumer routes between two items. The
/// corridor contains every item on any connecting route; it is not an executable
/// subgraph. Breadth-first ties use source item order. No paths are enumerated.
pub fn declared_graph_route_v1(
  source_graph : Json,
  from_item_id : String,
  to_item_id : String,
) -> DeclaredGraphRouteV1 raise {
  let graph = declared_graph_map_v1(source_graph)
  let ids = graph.nodes.map(node => node.work_item_id)
  guard ids.contains(from_item_id) else {
    fail("Unknown route start item: " + from_item_id)
  }
  guard ids.contains(to_item_id) else {
    fail("Unknown route destination item: " + to_item_id)
  }
  let distance : Map[String, Int] = {}
  distance[from_item_id] = 0
  let previous : Map[String, String] = {}
  let queue = [from_item_id]
  let mut cursor = 0
  while cursor < queue.length() {
    let current = queue[cursor]
    cursor += 1
    for node in graph.nodes {
      if node.depends_on.contains(current) &&
        !distance.contains(node.work_item_id) {
        distance[node.work_item_id] = distance[current] + 1
        previous[node.work_item_id] = current
        queue.push(node.work_item_id)
      }
    }
  }
  let reachable = distance.contains(to_item_id)
  let ancestors : Map[String, Bool] = {}
  ancestors[to_item_id] = true
  let backward = [to_item_id]
  cursor = 0
  while cursor < backward.length() {
    let current = backward[cursor]
    cursor += 1
    for node in graph.nodes {
      if node.work_item_id == current {
        for prerequisite in node.depends_on {
          if !ancestors.contains(prerequisite) {
            ancestors[prerequisite] = true
            backward.push(prerequisite)
          }
        }
      }
    }
  }
  let corridor = ids.filter(id => {
    distance.contains(id) && ancestors.contains(id)
  })
  let path : Array[String] = []
  if reachable {
    let mut current = to_item_id
    path.push(current)
    while current != from_item_id {
      current = previous[current]
      path.push(current)
    }
  }
  let edges : Array[DeclaredRouteEdgeV1] = []
  let outside : Array[DeclaredRouteEdgeV1] = []
  for node in graph.nodes {
    if corridor.contains(node.work_item_id) {
      for prerequisite in node.depends_on {
        let edge = DeclaredRouteEdgeV1::{
          prerequisite_id: prerequisite,
          consumer_id: node.work_item_id,
        }
        if corridor.contains(prerequisite) {
          edges.push(edge)
        } else {
          outside.push(edge)
        }
      }
    }
  }
  {
    contract_id: "moonflow.declared-graph-route.v1",
    graph_id: graph.graph_id,
    source_graph_digest: graph.source_graph_digest,
    from_item_id,
    to_item_id,
    reachable,
    shortest_distance: distance.get(to_item_id),
    shortest_path: path.rev(),
    corridor_item_ids: corridor,
    corridor_edges: edges,
    outside_prerequisite_edges: outside,
  }
}

///|
pub fn declared_graph_route_text_v1(report : DeclaredGraphRouteV1) -> String {
  let lines = [
    "Declared dependency route (not execution readiness)",
    "From: " + report.from_item_id.to_json().stringify(),
    "To: " + report.to_item_id.to_json().stringify(),
  ]
  if report.reachable {
    lines.push("Shortest path: " + report.shortest_path.to_json().stringify())
    lines.push(
      "Connecting items: " + report.corridor_item_ids.to_json().stringify(),
    )
    lines.push(
      "Connecting links: " + report.corridor_edges.to_json().stringify(),
    )
    lines.push(
      "Other prerequisites: " +
      report.outside_prerequisite_edges.to_json().stringify(),
    )
  } else {
    lines.push(
      "No declared dependency route connects these items in this direction.",
    )
  }
  lines.join("\n")
}
