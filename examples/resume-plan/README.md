# Resume a saved four-step study

`saved-form.json` is an actual Blob download from the shipped editor's event
handlers, exercised under the focused DOM adapter. It embeds the complete
`../plan-worksheet/source-graph.json`. The left step now depends on right, reads
`requests/right.json`, and declares a 45,000 ms timeout. Other declarations remain
unchanged. The inputs are synthetic planning fixtures, not qualified adapter
requests.

From the repository root:

```sh
python3 -B scripts/graph_explorer.py examples/plan-worksheet/source-graph.json \
  /new/resumed-study.html --author --cli /trusted/pinned/moonflow \
  --resume examples/resume-plan/saved-form.json
```

Open the new page, select left and inspect the restored fields and changed
prerequisite closure. Select right, preview a 90,000 ms timeout, apply it and
download the continued form. Regenerate another HTML page with that form to
continue again. Undo only affects actions made since opening; Reset all edits
returns to the original source and can be undone.

Use a new native workspace containing the original source, `requests/` and
catalog fixture from `examples/plan-worksheet`, then feed the exact download
through `plan from-form`, `inspect` and `prepare`. Use the fixture's synthetic
2026-07-31 timestamp only for this example; real work needs current health and
timestamps. Nothing here dispatches work or accepts a result.

See [the complete workflow and limits](../../docs/RESUME_PLAN_EDITOR.md).
