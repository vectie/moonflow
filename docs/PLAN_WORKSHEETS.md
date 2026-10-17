# Edit an existing workflow in a CSV worksheet

Export all declared steps, change several inputs, dependencies, review criteria
or timeouts together, then preview and save an ordinary editable plan. This is
useful when a heterogeneous workflow already exists and a sheet is easier to
edit than a JSON form. Unlike batch CSV/table imports, it retains the existing
steps and exact operation/declaration identities.

```sh
moonflow plan export-worksheet WORKSPACE source-graph.json > worksheet.csv
# Put the edited CSV inside WORKSPACE, then:
moonflow plan preview-worksheet WORKSPACE source-graph.json worksheet.csv revised-study 2026-07-31T00:00:00Z
moonflow plan from-worksheet WORKSPACE source-graph.json worksheet.csv revised-study 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE revised-study
moonflow plan prepare WORKSPACE revised-study catalog.json 2026-07-31T00:00:00Z
```

Use actual evaluation time and current catalog health for real work. Export
writes only stdout and requires no catalog or referenced input files. Preview
validates all selected input files inside the workspace but writes no draft.
Save creates a normal v1 plan; preparation and conformant import/revision use
the existing commands. Neither worksheet import nor preparation dispatches work.
Check the process exit code before using redirected output: the inherited CLI
prints errors on stdout and the shell may create a file even on failure.

## Spreadsheet columns

Import all columns as text. CSV quoting alone does not stop spreadsheet formula
evaluation of untrusted identifiers or operation labels.

Keep these columns unchanged:

- `source_graph_digest`: binds each row to the exact selected graph using the
  existing plan identity digest (not a raw-file digest or RFC 8785 claim).
- `work_item_id`: every original step must appear once, with its exact ID.
- `product_id`, `operation`: context for the editor; both are read-only.

Edit these columns:

- `input_artifacts`: JSON array of existing workspace-relative paths, e.g.
  `["requests/left-v2.json","references/room.json"]`.
- `depends_on`: JSON array of prerequisite IDs; `[]` means no prerequisites.
- `acceptance_criteria`: nonempty JSON array of review statements, e.g.
  `["Review the revised shape","Check dimensions"]`.
- `timeout_ms`: whole number from 1 through 86,400,000.

Type the JSON array as the cell value, without outer CSV quotes. Your spreadsheet
adds CSV quoting when saving. JSON strings use `\"` for quotes, `\\` for a
literal backslash and `\n` for a newline. Using arrays preserves spaces,
Unicode, commas, quotes, newlines and individual list entries exactly. Blank
array cells do not mean defaults and are refused. No list entries are trimmed.

Reorder columns or sort rows freely. Imports restore original source order,
so sorting does not change the draft or prepared identity. Optional UTF-8 BOM,
LF and CRLF are supported. A changed source graph requires a fresh export.
The receipt names `changed_item_ids` in original order and includes the complete
editable form for inspection. Its `csv_digest` hashes the actual CSV input,
so a different line-ending convention can change that digest without changing
the resulting plan. Repeating an identical save is idempotent. A conflicting
saved draft is never replaced: use a new draft ID or existing `plan edit`.

## Complete edits and limits

All edits are checked as one graph. You can reverse a dependency between two
steps in a single worksheet without an invalid intermediate saved graph.
Cycles, missing prerequisites, duplicate entries, unsafe artifact paths and
missing files fail before saving. Source graphs and accepted history remain
unchanged; ordinary revision rules determine which checkpoints are reusable.
Schemas, owner, authority and claim stay exactly as declared in the source.

The sheet requires exactly the eight named columns and 1–256 rows, with at
most 1,048,576 characters. Rows cannot add, remove or rename work items; use
existing plan forms, subgraph or composition tools for those changes. Native
file reads happen before the character bound is checked. Array JSON must parse
as string arrays. There is no automatic product payload generation, adapter
execution, catalog installation or spreadsheet application integration.

Library APIs: `declared_plan_worksheet_csv_v1(source_graph)` and
`declared_plan_from_worksheet_v1(source_graph, csv, draft_id, recorded_at)`.
The latter returns `PlanWorksheetImportV1` and an ordinary detached plan draft.
File existence/containment belongs to the native CLI or embedding host.

See [the runnable example](../examples/plan-worksheet/README.md). Native/unit
checks verify declared editing and preparation, not external effects, live
spreadsheet applications, customer acceptance, payment or cumulative runtime
qualification beyond the separately stated R50 baseline.

For repeated input-path edits, [shared input rebindings](INPUT_REBINDINGS.md)
can inventory every declared consumer of each exact path and export a fresh
worksheet after a source-bound simultaneous replacement preview. It leaves the
same native validation, preparation and revision workflow in place.

When two operators edit copies of the same export, use the
[three-way worksheet merge](WORKSHEET_MERGE.md) to combine independent field
changes, explicitly resolve conflicts and check the combined dependency graph
before native preview and preparation.
