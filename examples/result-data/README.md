# Compare two recorded synthetic variants

These are synthetic local event histories and result JSON, not external adapter
qualification. `study-a` has an accepted result and pending work; `study-b` has
a review-pending result and an unknown attempt. A's success was preceded by an
unknown outcome and includes an identical result redelivery. Its retained
artifacts also include unrelated review notes that the worksheet must ignore.

With a built native CLI:

```sh
python3 scripts/verify_result_data.py \
  --cli /absolute/path/to/main.exe \
  --workspace-parent /absolute/path/to/verification-workspaces
```

The verifier creates a fresh workspace, retains all raw command output and
checks typed JSON/CSV values, exact observed byte hashes, output ordering,
unknown/pending rows, canonical replay, ignored projection caches and errors.
It does not delete its fixtures or dispatch any adapter.

To inspect the sample manually, create an empty WORKSPACE, copy `a.json` and
`b.json` to `WORKSPACE/outputs/`, and `mapping.json` to its root. Copy
`study-a.events.json` to
`WORKSPACE/.moonsuite/products/moonflow/runs/study-a/events.json`, and similarly
for study-b. Then run:

```sh
moonflow result-data WORKSPACE mapping.json --json study-a study-b
moonflow result-data WORKSPACE mapping.json --csv study-a study-b
```

The selected output index is 1. Unselected preview files and old retained
artifacts intentionally do not exist: only exact selected result files are
read. The scores are 9.5 and 8, and the worksheet preserves acceptance as a
separate recorded fact. Do not treat these synthetic fixture identities as a
real workflow or import them over an existing run.
