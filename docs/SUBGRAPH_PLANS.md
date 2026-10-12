# Select a dependency-complete part of a workflow

Use a subgraph plan when you need one deliverable from a larger declared graph.
Name the desired work item IDs. MoonFlow keeps those targets and every transitive
prerequisite, so you do not have to manually remove unrelated rows or reconstruct
a diamond join. Selection follows only declared `depends_on` edges.

```text
moonflow plan preview-subgraph WORKSPACE source-graph.json chair-only 2026-07-31T00:00:00Z chair
moonflow plan from-subgraph WORKSPACE source-graph.json chair-only 2026-07-31T00:00:00Z chair
moonflow plan inspect WORKSPACE chair-only
moonflow plan export WORKSPACE chair-only
moonflow plan prepare WORKSPACE chair-only catalog.json 2026-07-31T00:00:00Z
```

Use actual evaluation time and current catalog health for real work. These July
timestamps are for the [synthetic furniture sample](../examples/subgraph-plan/README.md).
Pass more target IDs at the end to select several outputs in one plan.

## Preview, customize, and use

The receipt lists `target_item_ids`, automatically included
`prerequisite_item_ids`, and `omitted_item_ids`, plus the complete editable form.
All lists and items retain source order, even when targets are supplied in a
different order. Shared prerequisites appear once. Selecting a prerequisite as
an explicit target moves it into the target list without changing the graph.

Preview writes nothing. `from-subgraph` saves an ordinary removal-only v2 plan
draft; it retains the original graph and its digest. Repeating the same selection
with the same draft ID and timestamp is idempotent. A different saved draft is
not overwritten. Use a new ID for a different selection or use existing
`plan edit` with an exported `expected_draft` to customize retained input files,
criteria, timeouts, or dependencies.

`plan prepare` performs the existing current capability checks and produces a
child graph and proposal. Import the returned graph with
`import-conformant-graph`, or use `revise-run` for an existing parent run.
Checkpoint eligibility is evaluated by the existing revision path; selecting
items does not copy approvals or imply that prerequisites already ran.

## Exact scope

- The source must be a valid graph of at most 256 items. At least one distinct,
  existing target is required. Unknown targets, duplicate IDs and an invalid
  source graph are refused, including cycles in an omitted branch.
- Every target and its dependencies are retained. Downstream consumers,
  unrelated siblings, and independent branches are omitted unless requested.
  The dependency closure works even if source order is not topological.
- Exact item/declaration IDs, operations, schemas, owners, requested authority,
  claims, artifact paths, criteria and timeouts are preserved. No new operation
  or input content is authored. The source is never changed.
- Native preview/save require retained input files to exist inside the
  workspace. Omitted branches' files are not read or required. Payload schema
  validation remains with the owning adapter.
- Selection does not infer data dependencies from paths, prune completed work,
  create a runtime or dispatch attempts. It is CLI/library authoring; there is
  no new canvas control or adapter execution in this workflow.

Library hosts can call `declared_plan_from_subgraph_v1` and use the returned
`SubgraphPlanSelectionV1`. The pure function validates graph declarations;
workspace-file checks belong to the native CLI or embedding host.
