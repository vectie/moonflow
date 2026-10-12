# Offline publication dependency explorer

This synthetic `moonflow.declared-graph-map.v1` fixture mirrors the declared
items in `../graph-route/graph.json`: capture feeds model and texture, both
feed publish alongside license, and independent has no links. The report uses
the public topology semantics in `graph_map.mbt`; it was assembled for renderer
tests and is not retained output of a native CLI invocation in this round.
The reported source digest is the fixture graph's sorted-key compact JSON
SHA-256, matching the simple source's plan-identity representation.

From the repository root:

```sh
python3 scripts/graph_explorer.py examples/graph-explorer/graph-map.json /tmp/publication-explorer.html
```

Open the new HTML. Select `publish`, then **Selected + all prerequisites**:
five items remain, including license. Select `capture` and **Selected + all
downstream consumers**: capture, model, texture and publish remain. Select
`independent` in either scope: only independent remains. No operation runs.
See the [complete guide](../../docs/GRAPH_EXPLORER.md) for live export commands,
filter behavior, source/report identity distinctions and qualification limits.
