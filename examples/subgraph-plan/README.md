# Prepare just the chair from a furniture range

The synthetic source contains six declared steps. `frame` feeds `seat` and
`back`; both feed `chair`. Independent `lamp` and downstream `catalog` are
unneeded for the chair deliverable. Selecting `chair` creates a four-item draft
with the complete shared-frame diamond and leaves the other two out.

Copy this directory into an empty workspace. Put your compiled `moonflow` on
PATH and substitute that workspace's absolute path below:

```sh
moonflow compile-capability-catalog WORKSPACE/capability-source-bundle.json > WORKSPACE/catalog.json
moonflow plan preview-subgraph WORKSPACE source-graph.json chair-only 2026-07-31T00:00:00Z chair
moonflow plan from-subgraph WORKSPACE source-graph.json chair-only 2026-07-31T00:00:00Z chair
moonflow plan inspect WORKSPACE chair-only
moonflow plan export WORKSPACE chair-only > WORKSPACE/exported-draft.json
moonflow plan prepare WORKSPACE chair-only catalog.json 2026-07-31T00:00:00Z > WORKSPACE/preparation.json
```

The preview reports target `chair`, prerequisites `frame`, `seat`, `back`, and
omitted items `lamp`, `catalog`. Their missing request files are intentional:
only retained files are needed. Selecting `catalog` would require both missing
files as well as the chair branch.

To customize the chair, save `edit.json` containing the complete exported draft
as `expected_draft` and this complete object as `item_edit`:

```json
{
  "work_item_id": "chair",
  "input_artifacts": ["requests/chair.json"],
  "depends_on": ["seat", "back"],
  "acceptance_criteria": ["Review the chair silhouette and millimetre scale"],
  "timeout_ms": 120000
}
```

Run `moonflow plan edit WORKSPACE chair-only edit.json`, then prepare again.
The returned `graph_ref` and `prepared.preparation_id` identify the child:

```text
moonflow import-conformant-graph WORKSPACE WORKSPACE/GRAPH_REF WORKSPACE/catalog.json 2026-07-31T00:00:00Z
moonflow advance WORKSPACE PREPARATION_ID 2026-07-31T00:00:01Z
moonflow status WORKSPACE PREPARATION_ID
```

`frame` is ready; `seat`, `back`, and `chair` remain proposed until their
prerequisites are accepted. There are no attempts or approvals. This is useful
declared work for the existing execution path, not generated furniture geometry.
Requests intentionally reuse a synthetic MoonMold `mock-reference` request;
they are not a production furniture modeling recipe. The catalog's July health
window is synthetic, not evidence of a currently available adapter.

[Full format and limits](../../docs/SUBGRAPH_PLANS.md).
