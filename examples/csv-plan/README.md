# CSV design-study batch

This complete synthetic planning sample creates three model-study work items
from a workload sheet. The compact and wide studies are independent. The
display study waits for their accepted results. Its inputs are illustrative
MoonMold `mock-reference` create-model requests; this walkthrough stops before
product execution and needs no provider, account or authority grant.

Copy this entire directory into an empty workspace. Use an absolute workspace
path below and a compiled `moonflow` on PATH. The catalog's July health window
is intentionally synthetic; use the shown fixture evaluation time, not a claim
that this fixture is current production health.

```sh
moonflow compile-capability-catalog WORKSPACE/capability-source-bundle.json > WORKSPACE/catalog.json
moonflow plan preview-csv WORKSPACE source-graph.json make-model workload.csv study-batch 2026-07-31T00:00:00Z
moonflow plan from-csv WORKSPACE source-graph.json make-model workload.csv study-batch 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE study-batch
moonflow plan export WORKSPACE study-batch > WORKSPACE/exported-draft.json
moonflow plan prepare WORKSPACE study-batch catalog.json 2026-07-31T00:00:00Z > WORKSPACE/preparation.json
```

The preview displays three expanded items and writes no draft. Inspect the
`depends_on` arrays and the copied operation/schema/authority fields. Blank
criteria and timeout cells on `wide-study` inherit the template values.

To revise a row before preparation, save `edit.json` containing the entire
`exported-draft.json` value as `expected_draft`, plus an `item_edit` object:

```json
{
  "work_item_id": "wide-study",
  "input_artifacts": ["requests/wide.json"],
  "depends_on": [],
  "acceptance_criteria": ["Review the wide model's name, millimetre units and coordinate frame"],
  "timeout_ms": 75000
}
```

Run `moonflow plan edit WORKSPACE study-batch edit.json`, then prepare again.
The returned `graph_ref` and `prepared.preparation_id` are the concrete graph
path and new run ID. Substitute their exact returned values in:

```text
moonflow import-conformant-graph WORKSPACE WORKSPACE/GRAPH_REF WORKSPACE/catalog.json 2026-07-31T00:00:00Z
moonflow advance WORKSPACE PREPARATION_ID 2026-07-31T00:00:01Z
moonflow owner-summary WORKSPACE PREPARATION_ID --text
```

The two independent rows are ready, the display row remains proposed/waiting,
and all three have zero attempts. The original `make-model` template is absent
from the new run. Execution and review use the existing separately authorized
engine path. [Full CSV reference](../../docs/CSV_BATCH_PLANS.md).
