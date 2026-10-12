# Rebind shared inputs in a declared workflow

When several steps use the same reference file, find every declared use before
switching to its revised path. The existing dependency map and change-impact
reports cannot reveal shared file references between parallel branches. This
operator client consumes the actual eight-column [plan worksheet](PLAN_WORKSHEETS.md),
groups exact input references by consuming steps, previews explicit replacements,
and writes a new worksheet for the existing native planning workflow.

This is a declaration-editing workflow for MF-W01/MF-W04 and MOONFLOW-B02/B09:
retain source identity and review every affected declaration before native
preparation. It does not determine checkpoint reuse or edit accepted history.

## Inspect, preview, save, then use the existing planner

Use Python 3.9+ with the standard library. No installation or server is needed.
From the repository, with a separately installed trusted native CLI:

```sh
moonflow plan export-worksheet WORKSPACE source-graph.json > WORKSPACE/worksheet.csv && \
  python3 -B scripts/input_rebindings.py inventory WORKSPACE/worksheet.csv --text
python3 -B scripts/input_rebindings.py inventory WORKSPACE/worksheet.csv
```

Check the native command's exit status: native diagnostics may use stdout. Shell
redirection can create a partial file before a command fails; use a fresh path
for the export. The Python client never invokes a native command itself.

Inventory JSON contains the exact `worksheet_sha256`, the reported original
`source_graph_digest`, and each input's consuming work IDs and products. References
and consumers are listed in first-occurrence worksheet order; row sorting can
change that presentation order. `shared:true` means more than one declared work
item uses that exact string. `--text` gives a readable inventory with JSON-quoted
labels, preserving visible whitespace and keeping embedded newlines unambiguous.
There are no glob, prefix, substring or filesystem-equivalence matches.

Create `rebindings.json` with the exact digest from the inventory you inspected:

```json
{
  "contract_id": "moonflow.input-rebindings.v1",
  "worksheet_sha256": "sha256:<64 lowercase hex characters from your inventory>",
  "replacements": [
    {"from": "references/finish-v1.json", "to": "references/finish-v2.json"}
  ]
}
```

Then preview the complete affected input lists and write a new CSV:

```sh
python3 -B scripts/input_rebindings.py preview WORKSPACE/worksheet.csv rebindings.json --text
python3 -B scripts/input_rebindings.py preview WORKSPACE/worksheet.csv rebindings.json
python3 -B scripts/input_rebindings.py rebind WORKSPACE/worksheet.csv rebindings.json WORKSPACE/rebound.csv
moonflow plan preview-worksheet WORKSPACE source-graph.json rebound.csv rebound-study RECORDED_AT
moonflow plan from-worksheet WORKSPACE source-graph.json rebound.csv rebound-study RECORDED_AT
moonflow plan inspect WORKSPACE rebound-study
moonflow plan prepare WORKSPACE rebound-study catalog.json EVALUATED_AT
```

`RECORDED_AT` and `EVALUATED_AT` are placeholders. Supply actual timestamps and
current catalog health for real work. Inspect the native preview before saving.
The native planner checks the worksheet's graph binding and operation identities,
full graph semantics, and existing workspace-contained files. Preparation checks
exact catalog health and returns its ordinary child graph/revision proposal.
The existing separate import or revision command remains an explicit decision;
this client performs neither. See [declared plan authoring](DECLARED_PLAN_AUTHORING.md).

## Exact edit semantics

- Each mapping applies once to the original input references in every worksheet
  row. `a → b` plus `b → c` does not turn an original `a` into `c`. Swaps work.
- Every `from` must occur and may appear only once in the mapping. No-op mappings
  fail. Multiple mappings can share a destination if they do not create duplicate
  inputs within any single work item; a collision is refused, never deduplicated.
- Input-array order stays unchanged. All cells other than changed
  `input_artifacts` cells retain their exact decoded text. Row and column order,
  source digest, IDs, dependencies, operation labels, criteria and timeout are
  preserved. Changed input arrays use compact JSON. The new CSV quotes every
  cell, uses LF, and omits a UTF-8 BOM; its raw bytes differ from the original.
- The map binds the exact original file bytes, including BOM, CSV quoting and
  line endings. If the sheet changes, inspect a fresh inventory and explicitly
  update the mapping. The retained source graph digest is the native declaration
  identity, not the raw worksheet hash and not authenticated by this client.
- Reference admissibility mirrors the current core's lexical predicate: inspect
  a trimmed copy with backslashes treated as separators, reject empty or absolute
  references and empty or `..` segments. The stored string is never trimmed or
  normalized. Dot segments, backslashes, spaces and colon-containing names can
  remain distinct references. This lexical check does not prove filesystem
  containment, path portability, existence or file equivalence.

For example, `references/a.json` and `references/./a.json` are separate declared
strings even if they resolve to one file. Hidden references inside payloads,
hard links and symlinks are not discovered. No file is moved or renamed, and no
payload bytes are opened or hashed. Prepare the replacement files separately
before asking the native planner to use them.

## Files, bounds and limits

Only the selected CSV and mapping are read. Inventory and preview print stdout;
rebind additionally creates exactly one explicit output file. Existing files,
including source/mapping aliases and symlinks, are refused by exclusive creation.
An interrupted write can leave a partial new output: inspect it and choose a new
filename. Source and mapping files are never rewritten. Success returns the
exact source, mapping and output SHA-256, output size and changed work IDs.

The reader accepts the eight native columns in any order, optional UTF-8 BOM,
quoted multiline cells and LF/CRLF. It checks a single source identity, distinct
work IDs, basic required cells, string-array shapes and the timeout range. It is
not a replacement for the native graph parser: graph membership, cycles,
source identity recomputation, catalog conformance and current file status are
left to native preview/preparation. CSV wrappers are read with Python's standard
CSV parser and emitted in the native-compatible quoted format; this does not
claim identical rejection behavior for every malformed CSV spelling.

Limits: 1..256 rows; 1,048,576 UTF-16 units per input/output worksheet; 4 MiB per
selected input file; 1..256 exact replacements. Output growth is bounded before
saving. Exported reports and worksheets contain all selected declarations and
may be private; generating them grants no permission to share them. Spreadsheet
applications can interpret formulas in label cells even when CSV-quoted. Import
all cells as text if opening the worksheet in such an application.

No run, draft, event, approval, input-file check, adapter or provider call is
created. An edited worksheet is not an executable plan, authorization, readiness
proof, review decision, accepted artifact or customer outcome.

## Focused verification

```sh
python3 -B scripts/test_input_rebindings.py
```

Twelve functional tests include the existing captured native worksheet export
and recorded native import fixture, independent CSV roundtrip, shared parallel
consumers, simultaneous swap/non-cascading mappings, exact Unicode/multiline
cells, bounded growth, preview without writes, and actual CLI create/reopen and
refusal to overwrite. The [synthetic example](../examples/input-rebindings/README.md)
is reproducible. The fixtures provide format evidence; the new output was not
submitted to a live native parser in this round. No Moon invocation, dependency
install, browser, MoonDesk, native engine or external adapter execution is
qualified. R50 remains the last fully verified cumulative baseline; R51–55 are
separate.
