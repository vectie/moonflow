# Merge parallel plan edits

Two operators can edit copies of the same exported worksheet, then combine their
changes without manually re-entering them. The three-way merge retains every
source work item and its operation identity, combines independent field edits,
and asks for a choice when both operators changed the same field differently.
The resulting CSV goes directly into the existing native worksheet planner.

This implements a declaration-authoring workflow for MF-W01/MF-W04 and
MOONFLOW-B02/B09. It does not alter collaboration memberships, authenticate
editors, approve their edits, dispatch work, or change canonical run history.

## Export once, edit copies, and preview

Use Python 3.9+ and the standard library. Keep an unchanged common base. Both
branches must derive from that base; matching declared graph digests alone do
not prove common ancestry or authenticate the supplied files.

```sh
moonflow plan export-worksheet WORKSPACE source-graph.json > WORKSPACE/base.csv
# Check export exit status before using the file. Make left.csv and right.csv
# copies, then independently edit them using the native worksheet rules.
python3 -B scripts/worksheet_merge.py preview WORKSPACE/base.csv WORKSPACE/left.csv WORKSPACE/right.csv
```

Preview performs no writes. Its JSON gives exact byte hashes for all three
inputs, conflicts with the exact original/left/right cell strings, a resolution
template, and readiness to save. Exit 2 means a conflict or blocker remains;
when a merge report can be constructed it is still printed on stdout. Malformed
inputs are reported on stderr. Exit 0 means a locally valid candidate exists,
not that native validation or readiness has succeeded.

For a conflict-free merge:

```sh
python3 -B scripts/worksheet_merge.py save WORKSPACE/base.csv WORKSPACE/left.csv WORKSPACE/right.csv WORKSPACE/merged.csv
```

For conflicts, copy the complete `resolution_template` object from the preview
into a new JSON file. Set each `choice` from null to `base`, `left`, or `right`.
To supply a new cell, choose `custom` and add `value` containing the exact CSV
cell text as a JSON string. For example, a timeout resolution entry is:

```json
{"work_item_id":"left","field":"timeout_ms","choice":"custom","value":"150000"}
```

Array-valued cells use a string containing a JSON array, as in the worksheet.
Every conflict must appear exactly once. Do not change the three input hashes.
Selections for nonconflicts, extra fields, duplicate JSON keys, partial answers,
and stale input bytes are refused. Hashes detect changes to the three worksheets;
the resolution file itself is editable operator input, not signed approval.
Changing a valid choice intentionally changes the proposed output. The report
records the resolution file's hash for review, but cannot detect malicious edits
to that file before invocation. Review it in a trusted local workspace.

```sh
python3 -B scripts/worksheet_merge.py preview WORKSPACE/base.csv WORKSPACE/left.csv WORKSPACE/right.csv --resolutions choices.json
python3 -B scripts/worksheet_merge.py save WORKSPACE/base.csv WORKSPACE/left.csv WORKSPACE/right.csv WORKSPACE/merged.csv --resolutions choices.json
moonflow plan preview-worksheet WORKSPACE source-graph.json merged.csv merged-study RECORDED_AT
moonflow plan from-worksheet WORKSPACE source-graph.json merged.csv merged-study RECORDED_AT
moonflow plan inspect WORKSPACE merged-study
moonflow plan prepare WORKSPACE merged-study catalog.json EVALUATED_AT
```

Use actual timestamps and current catalog health for real work. Native preview
recomputes graph identity, validates the complete declaration and checks input
files and containment. Prepare follows ordinary capability checks and produces
the child graph/revision proposal. Existing separate revision/import authority
rules still apply. Nothing here submits a review, imports a graph or dispatches.

## Merge rules

- Only inputs, dependencies, acceptance criteria and timeout can change. Arrays
  are whole ordered values: there is no implicit union, deletion inference or
  concatenation of two reviewers' criteria.
- A field changed on only one side uses that side. Identical changes merge once.
  Different concurrent changes require an explicit choice, including choosing
  the base to discard both edits.
- Equality compares decoded ordered arrays and numeric timeout values. JSON
  whitespace and zero-padded timeouts alone do not create conflicts. Unchanged
  fields keep base cell text. Identical changed values choose left cell text.
- Columns/rows can be reordered; output follows base order. BOM and CRLF inputs
  are accepted. Output is UTF-8, LF, fully CSV-quoted, without BOM. Unedited cell
  text is preserved, but output file bytes are not an exact copy of any input.
- Work item deletion, addition, rename, duplicate identity or changed read-only
  identity is refused, even when another branch edits the deleted item. Use the
  native graph authoring workflow for structural membership changes.
- Each input graph must be a valid DAG over its declared IDs. Two valid branches
  can combine into a cycle; that blocks saving even without a field conflict.
  Revise the branch worksheets to resolve the cross-field dependency design,
  then preview again. Custom choices are also checked for cycles and bad cells.

Bounds reuse the native worksheet client: 1..256 items, 4 MiB per selected input,
1,048,576 UTF-16 units per worksheet including output, unique nonblank arrays,
nonempty inputs/criteria and timeouts 1..86,400,000. Input paths receive only the
existing lexical check; no payload is read and file existence is not inferred.
No network, provider, dependency installation or native compilation is needed.

Save exclusively creates one mode-0600 CSV in an existing directory. Existing
files and symlinks are refused, including source aliases. Sources and resolution
files remain unchanged. A failed final write can leave a partial new file; retain
it for inspection and choose a new filename. Work in a trusted directory without
concurrent file replacement. CSV quoting does not prevent spreadsheet formula
execution: import all columns as text in spreadsheet applications.

## Verification

```sh
python3 -B scripts/test_worksheet_merge.py
python3 -B scripts/test_input_rebindings.py
python3 -B scripts/verify_worksheet_merge.py --cli /trusted/moonflow --workspace-parent /new/test-fixtures
```

Functional tests run the actual implementation and CLI with conflict choices,
Unicode, reordered rows/columns, semantic equality, deletion/edit conflict,
duplicate IDs, stale bindings, unknown resolutions, custom invalid cells,
combined dependency cycles, and exclusive writes. Native integration uses the
existing R572 executable, whose native source/configuration files match this
round, to export, preview, save, reopen and prepare a synthetic merged plan.
It also verifies native rejection of stale graphs and missing inputs. The fixed
fixture timestamp exercises fixture catalog health only. No native rebuild,
adapter effect, live provider, browser, authority, restart or full-product
qualification is claimed.
