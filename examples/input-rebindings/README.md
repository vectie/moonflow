# Shared-reference update example

Two parallel declared steps, `left` and `right`, use `references/finish-v1.json`.
Inventory their shared use, inspect the exact changed input lists, then create a
new worksheet that switches both to `references/finish-v2.json`:

```sh
python3 -B scripts/input_rebindings.py inventory examples/input-rebindings/worksheet.csv --text
python3 -B scripts/input_rebindings.py preview examples/input-rebindings/worksheet.csv examples/input-rebindings/rebindings.json --text
python3 -B scripts/input_rebindings.py rebind examples/input-rebindings/worksheet.csv examples/input-rebindings/rebindings.json /tmp/moonflow-rebound-example.csv
```

Use a fresh output filename. The created bytes equal checked-in `rebound.csv`;
`inventory.json` and `preview.json` retain the deterministic reports. No payload
file exists for the synthetic shared reference; success demonstrates declaration
editing without file reads, not file readiness or successful native import.

`worksheet.csv` is an edited copy of the retained actual native export at
`../plan-worksheet/outputs/exported.csv`. It adds the shared reference to those
two rows while retaining the original source identity and other fields. The
associated original graph is `../plan-worksheet/source-graph.json`. The map
binds this edited copy's exact bytes. All work and file names are synthetic.

For a real workflow, begin with a fresh export of your selected source graph,
prepare the actual replacement files, and follow the exact native
`preview-worksheet`, `from-worksheet`, `inspect`, and `prepare` commands in
[the product guide](../../docs/INPUT_REBINDINGS.md). Current catalog health,
workspace containment and full graph validation remain native responsibilities.
