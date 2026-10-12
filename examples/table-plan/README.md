# Three paired design studies from one table

This synthetic sample turns a two-step model/companion workflow into six
editable work items. Three main models can start independently. Each companion
waits only for its own main model to be accepted. The quoted café label shows
ordinary spreadsheet punctuation being retained in review criteria.

Copy this directory into an empty workspace. Use its absolute path below and
place the compiled `moonflow` executable on PATH:

```sh
moonflow compile-capability-catalog WORKSPACE/capability-source-bundle.json > WORKSPACE/catalog.json
moonflow plan preview-table WORKSPACE source-graph.json template.json variants.csv paired-study 2026-07-31T00:00:00Z
moonflow plan from-table WORKSPACE source-graph.json template.json variants.csv paired-study 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE paired-study
moonflow plan export WORKSPACE paired-study > WORKSPACE/exported-draft.json
moonflow plan prepare WORKSPACE paired-study catalog.json 2026-07-31T00:00:00Z > WORKSPACE/preparation.json
```

The preparation result includes `graph_ref` and `prepared.preparation_id`.
Substitute those exact returned values in the following optional local import:

```text
moonflow import-conformant-graph WORKSPACE WORKSPACE/GRAPH_REF WORKSPACE/catalog.json 2026-07-31T00:00:00Z
moonflow advance WORKSPACE PREPARATION_ID 2026-07-31T00:00:01Z
moonflow status WORKSPACE PREPARATION_ID
```

The expected ready items are `compact--model`, `wide--model` and `display--model`.
Each `--companion` remains proposed until its matching model is accepted.
There are zero attempts and no approvals. The fixture's July catalog health
window is intentionally synthetic; it is not current adapter health.

To customize a generated item, save `edit.json` with the complete exported
value as `expected_draft` and a complete `item_edit` object, for example:

```json
{
  "work_item_id": "wide--companion",
  "input_artifacts": ["requests/wide-companion.json"],
  "depends_on": ["wide--model"],
  "acceptance_criteria": ["Review the wide companion's silhouette and millimetre scale"],
  "timeout_ms": 120000
}
```

Run `moonflow plan edit WORKSPACE paired-study edit.json`, then prepare again.
The new graph identity reflects the edited plan. The original source and other
rows remain unchanged. Requests use the existing illustrative MoonMold
`mock-reference` create-model shape; this sample proves planning and dependency
projection, not external adapter execution or geometry results.

[Format and limits](../../docs/TABLE_WORKFLOW_PLANS.md).
