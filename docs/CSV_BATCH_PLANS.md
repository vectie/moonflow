# Turn a workload sheet into a declared batch

Use an existing operation repeatedly without hand-editing a graph for every
input file. Export a UTF-8 CSV from a spreadsheet, select an original work item
as the operation template, preview the whole batch, then save an ordinary plan
draft. The same draft can be inspected, edited, prepared and imported with the
existing plan commands.

```text
moonflow plan preview-csv WORKSPACE source-graph.json make-model workload.csv study-batch 2026-07-31T00:00:00Z
moonflow plan from-csv WORKSPACE source-graph.json make-model workload.csv study-batch 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE study-batch
moonflow plan export WORKSPACE study-batch
moonflow plan prepare WORKSPACE study-batch catalog.json 2026-07-31T00:00:00Z
```

The dates above match the synthetic runnable fixture in
[`examples/csv-plan`](../examples/csv-plan/README.md). Real work needs the actual
evaluation time and current adapter health.

## Sheet columns

- `work_item_id` (required): a new unique item ID, distinct from every source
  item ID. Use ASCII letters, digits, dots, hyphens or underscores, at most 128
  characters, excluding `.` and `..` sequences.
- `input_artifacts` (required): one or more existing workspace-relative input
  paths. Put multiple paths on separate lines within the spreadsheet cell.
- `depends_on` (optional): new batch item IDs, one per line. Blank means this
  row has no dependencies. References may point to a later row.
- `acceptance_criteria` (optional): one criterion per line. Blank inherits the
  template's complete criteria list.
- `timeout_ms` (optional): a whole number from 1 to 86,400,000. Blank inherits
  the template timeout.

Column order is flexible. CSV supports quoted commas, doubled quotes, quoted
multiline cells, LF/CRLF and an optional UTF-8 BOM. Lists use newlines, not
semicolon/comma splitting. Surrounding whitespace is trimmed; blank records,
blank entries inside a list, unknown columns and inconsistent row widths are
errors. Export values, rather than spreadsheet formulas. Maximum: 256 work
items and 1,048,576 UTF-16 code units.

## Preview, editing and output

`preview-csv` reads and validates the complete graph and every selected input
path, prints the expanded form and raw CSV SHA-256, and writes nothing.
`from-csv` performs the same checks, then saves one draft under
`.moonsuite/products/moonflow/plan-drafts`. Retrying the same draft is idempotent;
different content needs a new draft ID or the existing `plan edit` workflow.
The receipt identifies the CSV path and digest. The draft stores the expanded
rows and exact source graph, so reopening does not depend on the sheet staying
unchanged. It does not retain a separate copy of the CSV bytes.

The batch replaces the source item set with the CSV rows. Every row copies the
selected original item's product, exact operation, schemas, authority and claim
ceiling. Source dependencies are not copied. Each row gets fresh declaration
lineage through the existing v2 authoring path. Only the explicit batch
dependencies are used; a dependent becomes ready after all predecessors have
accepted outcomes, following the normal engine rules.

The output is a normal editable draft and, after `plan prepare`, a
content-addressed child graph/proposal. Use the returned `graph_ref` with
`import-conformant-graph`, then inspect/advance it through the existing engine.
Preparation checks fresh catalog compatibility and current input paths. Input
payloads remain owned by their products; CSV import neither synthesizes nor
validates domain payloads. It does not freeze file bytes, execute operations,
transfer outputs between rows, approve work or alter an existing source run.

## Qualification

Native tests cover tabular expansion, multiline/multi-artifact rows, graph
dependencies, ordinary draft edits, deterministic preparation and preserving
the template contract. A compiled CLI journey copies the realistic synthetic
sample into a new workspace, previews without writes, saves/reopens/edits it,
prepares/imports the child and advances only the two independent rows. No
product adapter, provider, browser or physical hardware is executed.
