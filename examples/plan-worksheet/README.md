# Revise a four-step study with one worksheet

This synthetic example changes a root/left dependency and the left step's
request, criteria and timeout while keeping the other declarations unchanged.
The request files are placeholders for planning only. No adapter is invoked,
and these placeholder payloads are not qualified MoonMold inputs.

Copy this folder to an empty workspace, then use the native CLI:

```sh
moonflow plan export-worksheet WORKSPACE source-graph.json > WORKSPACE/worksheet.csv
```

Open the CSV using a spreadsheet's text-column import mode. In the `root` row,
set `depends_on` to `["left"]`. In the `left` row, set `depends_on` to `[]`,
`input_artifacts` to `["requests/left-v2.json"]`, `acceptance_criteria` to
`["Review the revised left artifact"]`, and `timeout_ms` to `90000`. Save CSV.
Those are cell values; the spreadsheet handles outer CSV quoting for you.

```sh
moonflow plan preview-worksheet WORKSPACE source-graph.json worksheet.csv revised-study 2026-07-31T00:00:00Z
moonflow plan from-worksheet WORKSPACE source-graph.json worksheet.csv revised-study 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE revised-study
moonflow compile-capability-catalog WORKSPACE/capability-source-bundle.json > WORKSPACE/catalog.json
moonflow plan prepare WORKSPACE revised-study catalog.json 2026-07-31T00:00:00Z
```

The preview names `root` and `left` as changed and keeps the exact original
operation/declaration identities. The prepared child keeps `right` dependent on
`root` and `join` dependent on both `left` and `right`. No run or attempt is
created by these commands. Health and dates in this example are synthetic;
use current evidence and evaluation time for real work.

The repository's verifier performs this complete flow, checks the CSV independently
with Python's standard CSV parser, saves/reopens/prepares the result, and imports
the prepared child to prove the existing runtime sees the edited declarations
with zero attempts. It keeps all workspaces and records every command/output.
It also checks changed-source, malformed edits, missing files and duplicate
save handling. Run it from the repository root:

```sh
python3 scripts/verify_plan_worksheet.py --cli /absolute/main.exe --workspace-parent /absolute/verification-workspaces
```

Ordinary verification compares the retained `outputs/` with actual output.
`--record` replaces expected outputs and is only for reviewed fixture changes.
The automated fixture includes Unicode, commas, quoted and multiline criteria,
BOM/CRLF, and sorted rows/columns. Export output is directly reusable; preview,
draft and preparation output provide reviewable reference examples.

[Format and limits](../../docs/PLAN_WORKSHEETS.md).
