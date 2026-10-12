# Compare a model input revision

The two synthetic graphs declare capture → model → publish, plus an independent
branch. The after graph changes only the model's request path and timeout, and
its graph revision labels. Request files intentionally do not exist: comparison
is useful before creating or importing executable work.

```sh
moonflow compare-graphs /absolute/path/to/examples/graph-comparison before.json after.json --text
moonflow compare-graphs /absolute/path/to/examples/graph-comparison before.json after.json --json
```

Expect `model` changed, `publish` downstream in both graphs, and `capture` plus
`independent` unaffected. No work is dispatched or state written. The fixture
clock and source-digest label are synthetic and confer no catalog health.

See `docs/GRAPH_COMPARISON.md` for lineage, field comparison, raw input identity,
limits and the separate meanings of declared dependency impact and actual
checkpoint eligibility.
