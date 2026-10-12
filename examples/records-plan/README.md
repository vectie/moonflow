# JSON export to editable design-study plan

This synthetic export resembles a nested work-queue API response. `mapping.json`
selects its jobs and their nested fields without converting arrays to CSV.
Each record clones the exact `make-model` operation from the source graph.
The display study waits for the compact and wide studies, including a forward
reference to the later wide record. Inputs are illustrative MoonMold
`mock-reference` requests; the walkthrough stops before adapter execution.

Copy this whole directory into an empty workspace. With a compiled `moonflow`
on PATH and an absolute `WORKSPACE`, run:

```text
moonflow plan preview-records WORKSPACE source-graph.json mapping.json records.json export-batch 2026-07-31T00:00:00Z
moonflow plan from-records WORKSPACE source-graph.json mapping.json records.json export-batch 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE export-batch
moonflow plan export WORKSPACE export-batch
moonflow compile-capability-catalog WORKSPACE/capability-source-bundle.json
```

Save the last command's JSON output as `WORKSPACE/catalog.json`, then run:

```text
moonflow plan prepare WORKSPACE export-batch catalog.json 2026-07-31T00:00:00Z
```

The July evaluation time matches this synthetic catalog's health window; it is
not current production health. Use the preparation's exact `graph_ref` and
`prepared.preparation_id` in the existing workflow:

```text
moonflow import-conformant-graph WORKSPACE WORKSPACE/GRAPH_REF WORKSPACE/catalog.json 2026-07-31T00:00:00Z
moonflow advance WORKSPACE PREPARATION_ID 2026-07-31T00:00:01Z
moonflow owner-summary WORKSPACE PREPARATION_ID --text
```

Only compact and wide become ready. Display waits, all attempts remain zero,
and the source graph stays unchanged. `plan edit` can revise any imported row
before preparation. [Mapping and limits](../../docs/JSON_RECORD_PLANS.md).

`mapping-null-defaults.json` demonstrates explicit JSON null for all three
optional selectors. Use it instead of `mapping.json` with draft ID `null-batch`
to make independent rows with the source criteria and 60000 ms timeout. The
export's dependency/review/timeout values are intentionally not selected in
that variant. Null defaults are covered by both plain-JSON library tests and
the compiled preview/save/prepare journey.
