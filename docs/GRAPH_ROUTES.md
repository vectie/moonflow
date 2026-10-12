# Find the dependency routes between two work items

An operator asks “How can changing capture reach publish?” or “Which links
connect model to this output?” Inspect a pair of declared items without importing
runs, creating drafts, or reading their product input files:

```sh
moonflow graph-route examples/graph-route graph.json capture publish --text
moonflow graph-route examples/graph-route graph.json model publish --json
```

The first command finds both model and texture branches. The second finds the
model-to-publish link and lists capture, texture and license as other incoming
prerequisites. Those outside links matter: the connecting corridor alone is not
a dependency-complete executable subgraph. Use `plan preview-subgraph` when you
actually want a dependency-complete editable plan.

The report includes:

- `reachable`, `shortest_distance` (edge count) and one `shortest_path` witness.
- `corridor_item_ids`: every item on any declared path from start to destination,
  in source item order, including both endpoints when reachable.
- `corridor_edges`: all connecting prerequisite-to-consumer links.
- `outside_prerequisite_edges`: immediate incoming links from outside the
  corridor, including prerequisites of the starting item. This is not their
  transitive closure.
- The source graph digest and CLI input file SHA-256 and byte count.

Routes are directional. No route is a successful inspection with `reachable:
false`, a null distance and empty path/corridor/edge arrays. An item reaches itself
by a zero-edge path; its other prerequisites remain visible. Equal-length
witnesses use breadth-first discovery with source item order as the tie-break.
Items may be in non-topological source order. Repeated declared prerequisites
are one structural link. Changing source order may change the chosen witness
and graph digest while preserving the same structural corridor.

Both endpoints must exist. The complete graph must pass existing declaration
and topology validation, including branches outside the query. At most 256 items
and a 2 MiB source file are accepted. Input references use existing workspace
confinement. Text output JSON-quotes IDs; JSON output preserves exact strings.
The read-only command writes only stdout/stderr. Redirect output explicitly if
you need a file. Source input contents and runtime stores remain unchanged.

This report describes declared dependencies only. It does not claim runtime
readiness, timing, authority, acceptance, checkpoint reuse, or hidden data/file
relationships. It does not count or enumerate all possible paths. Library hosts
use `declared_graph_route_v1` and `declared_graph_route_text_v1`.
