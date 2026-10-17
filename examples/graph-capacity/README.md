# Compare one design slot with two

Use this directory as the workspace. It contains the complete synthetic graph
and both explicit capacity scenarios. The graph has root → left/right → join.
All values are made-up relative seconds. No payload files or adapters are needed.

```sh
moonflow graph-capacity /absolute/path/to/examples/graph-capacity source-graph.json capacity-one.json --json
moonflow graph-capacity /absolute/path/to/examples/graph-capacity source-graph.json capacity-two.json --json
moonflow graph-capacity /absolute/path/to/examples/graph-capacity source-graph.json capacity-one.json --csv
```

Expected one-slot offsets: root 0–10, left 10–40, right 40–60, join 60–65.
Expected two-slot offsets: root 0–10, left 10–40, right 10–30, join 40–45.
The dependency-only lower bound is 45 in both cases. One slot causes right to
wait 30 seconds after its prerequisites finish; makespan increases by 20 seconds.
These describe different quantities and are not interchangeable.

Try changing left's estimate, or make left and right each require both design
and review. Keep each demand within its capacity. Inspect the JSON pool peaks
and item waits, then export CSV to a fresh filename if useful. Check the command's
exit status before parsing redirected data; inherited CLI errors use stdout.

This is offline exploration. The graph contains unchanged example declaration
references, but its input payload files are deliberately absent: this command
does not read them and the directory is not an executable/import-ready work pack.
No drafts, history or attempts are created. Read [the complete guide](../../docs/GRAPH_CAPACITY.md)
for deterministic priority, bounds and limits.

After building the native CLI, the reproducible process journey is:

```sh
moon --target-dir /absolute/external/script-target run scripts/verify_graph_capacity.mbtx --target native --strip -j 1 -- /absolute/native/moonflow /absolute/source/root /absolute/new/evidence-directory
```

Use the pinned toolchain and private HOME/XDG directories required by the host
workspace. The harness requires a new evidence directory, copies the sample,
records command output/status, compares both scenarios and CSV, tests invalid
inputs, and verifies no workspace files or bytes change during each command.
