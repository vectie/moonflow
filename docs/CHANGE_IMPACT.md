# Explore downstream revision impact

Before editing a declared graph, inspect which consumers might need attention:

```sh
moonflow plan impact ./examples/subgraph-plan source-graph.json frame
moonflow plan impact ./examples/subgraph-plan source-graph.json seat lamp
```

The command prints a `moonflow.change-impact.v1` JSON report. It reads only the
source graph; referenced product inputs and a capability catalog are not needed.
It creates no draft, run, approval, attempt, or output file. Redirect stdout if
you want to retain the report. Normal source-reference workspace confinement
applies.

- `source_graph_digest` identifies the exact canonical source content.
- `changed_item_ids` are your explicit potential changes, in source order.
- `affected_items` are their transitive downstream consumers, in source order.
  Each includes its shortest `dependency_distance` from any changed item and
  all direct `impacted_prerequisite_ids` that are changed or downstream-affected.
- `unaffected_item_ids` are outside that declared downstream closure.

In the furniture sample, changing `frame` affects `seat`, `back`, `chair`, and
`catalog`; the independent `lamp` remains unaffected. Changing `chair` affects
only `catalog`. Selecting both an ancestor and a descendant keeps both in the
explicit-change list and calculates shortest distances from either one.

This is structural change exploration, not a revision or checkpoint invalidation
decision. Distances are not an execution schedule; joins can have other inputs.
“Unaffected” means only that no declared dependency path reaches the item. The
tool cannot detect hidden relationships in product payloads or shared files.
Runtime status, authority, catalog health, and result acceptance are untouched.

The complete source graph must pass the existing graph parser and topology
validation. One or more distinct, nonblank, known IDs are required. Graphs over
256 work items are refused. Results are deterministic for the same source and
selection regardless of selection order. Source array order is retained, even
when it is not topological; the source digest therefore changes with that order.

The library entry point is `declared_change_impact_v1(source_graph, changed_ids)`.
Its report arrays do not alias the caller's selection or mutate the source.
