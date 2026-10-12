# Repeat a complete workflow from a table

Table plans turn an existing multi-step graph into independent per-row branches.
For example, a product-variant sheet can produce a model/companion pair for each
variant without hand-copying every operation and dependency. This complements
the single-operation [CSV workload importer](CSV_BATCH_PLANS.md).

## Inputs and commands

Supply an existing work graph, a template JSON file and a UTF-8 CSV. The CSV
requires a unique `key` column. Other column names contain only ASCII letters,
digits or underscore. Use commas, doubled quotes, LF or CRLF, and quoted cells
for commas or newlines. An optional UTF-8 BOM is accepted; cell edges are trimmed.

The template contract is `moonflow.table-plan-template.v1`. Its `item_bindings`
array contains exactly one binding per original work item:

```json
{
  "contract_id": "moonflow.table-plan-template.v1",
  "item_bindings": [{
    "template_work_item_id": "model",
    "input_artifacts": ["requests/{{key}}-{{locale}}.json"],
    "acceptance_criteria": ["Review {{label}} in {{locale}}"]
  }]
}
```

`{{column}}` substitutes one CSV cell. Substitution applies only to these two
text arrays. Values are inserted once, so braces inside a cell remain literal.
Each used value must be nonblank. Omit `acceptance_criteria` to retain the exact
source criteria. Bind every step's input files explicitly; files must already
exist inside the workspace. Payload content remains owned by its product.

```text
moonflow plan preview-table WORKSPACE source-graph.json template.json variants.csv study 2026-07-31T00:00:00Z
moonflow plan from-table WORKSPACE source-graph.json template.json variants.csv study 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE study
moonflow plan export WORKSPACE study
moonflow plan prepare WORKSPACE study catalog.json 2026-07-31T00:00:00Z
```

Preview returns the full editable form without saving. `from-table` saves a
normal declared-plan v2 draft. Use the existing `plan edit` command to adjust
one expanded item; use `plan export` for its `expected_draft`. An identical
reimport is idempotent; changed rows require a new draft ID or ordinary edits.
`prepare` produces the normal graph/proposal artifacts after current catalog
validation. The template is no longer needed to reopen or edit the saved draft.

## What gets expanded

- Each source step gets ID `key--original-step-id`, ordered by CSV row and then
  original graph order. IDs remain stable when table rows are reordered.
- Dependencies are rewritten to the same row. A diamond join waits on that
  row's left and right branches, never another row's branch.
- Exact operation, product, schemas, authority, claim and timeout are copied
  from each corresponding original step. The original template items disappear
  from the expanded draft. Added steps get fresh declaration lineage.
- All expanded items remain editable using existing plan tools. Import and
  progression use the existing engine; creating a plan does not dispatch it.

## Bounds and limitations

The table must contain 1–256 rows, at most 1,048,576 characters, and produce
at most 256 total work items. Keys use the normal safe identifier format and
cannot contain `..` or `--`. Expanded IDs must not collide with source IDs.
Bad placeholders, missing bindings, invalid paths, duplicate IDs or malformed
CSV reject the entire expansion before a draft is saved.

This is explicit row expansion, not a Cartesian-product generator, a scheduler
or a domain request generator. Shared setup steps and cross-row joins are not
inferred; create them with the existing plan form tools when needed. It does
not bind future output paths or assert that input payloads match a product's
schema. Source steps and every referenced file are supplied by the operator.
No adapter, network service or provider is invoked by these commands.

See the [complete paired design study](../examples/table-plan/README.md).
