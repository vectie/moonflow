# Explore a workflow's critical path

Use explicit duration estimates to see which declared steps control an idealized
completion time and how much other steps can slip without changing that time.
This is an offline planning worksheet: no run, catalog, adapter or input artifact
files are required, and no execution or saved plan is created.

Create `estimates.json` beside your graph inside the workspace:

```json
{
  "contract_id": "moonflow.duration-estimates.v1",
  "graph_id": "diamond-r1",
  "durations_seconds": {"root": 10, "left": 20, "right": 5, "join": 3}
}
```

Every graph item needs exactly one numeric whole-second estimate in 0..604800
(seven days). Zero represents a milestone. Unknown or missing item IDs fail;
there are no default estimates and `timeout_ms` is never used as a duration.
The estimates' graph ID must match the selected graph. Choose realistic values
for your declared operations; this tool does not infer them from past runs.

```sh
moonflow graph-timing /absolute/workspace graph.json estimates.json --json
moonflow graph-timing /absolute/workspace graph.json estimates.json --csv
```

The diamond example finishes no earlier than 33 estimated seconds. `root`,
`left`, and `join` have zero slack; `right` can slip 15 seconds. Change `right`
to 40 seconds and rerun to see a 53-second lower bound and a different critical
branch. Export CSV to compare the rows or discuss a bottleneck with an operator.

## Interpret the worksheet

- `earliest_start_seconds` and `earliest_finish_seconds` are offsets from an
  assumed common time zero, following every declared prerequisite.
- `latest_start_seconds` and `latest_finish_seconds` are the latest offsets
  that preserve the entire graph's minimum completion horizon.
- `slack_seconds` is latest start minus earliest start. `critical` means zero
  slack. Multiple critical paths and tied branches are retained.
- JSON `critical_edges` contains precisely the declared edges participating
  in critical paths. A shortcut between critical items is not critical unless
  its prerequisite finish equals its consumer start. Duplicate dependencies
  collapse to one edge. No exponential enumeration of paths is returned.
- Disconnected branches share the same completion horizon. An isolated short
  task may have slack. All-zero workflows have zero horizon and all items
  critical under this mathematical convention.
- Items and critical IDs remain in source order, even if the source is not
  topologically ordered. Edges follow consumer source order and dependency order.
- JSON includes the selected source digest and estimates digest. These use the
  existing plan canonicalization helper, not raw-file hashes or RFC 8785.
  A report owns its arrays and does not mutate either input JSON value.

The model assumes unlimited parallel capacity, immediate starts after all
prerequisites finish, and no resource contention, calendar breaks, queuing,
authority/review delays, retries or uncertain effects. It is a lower-bound
estimate, not a promised deadline, actual elapsed duration, dispatch schedule,
readiness decision or evidence of accepted work. Review the graph and estimates
again after either changes; a matching graph ID alone does not prove freshness.

CSV contains one row per item and repeats the graph-wide minimum duration.
Cells are quoted, including graph/item labels. Import untrusted labels as text
in a spreadsheet: CSV quoting does not prevent formula evaluation. JSON retains
identity digests and critical edges; CSV intentionally focuses on timing rows.

The CLI reads workspace-contained JSON files and prints only after complete
validation. Check its exit status: the existing CLI error handler can print an
error on stdout, and shell redirection can create an empty/diagnostic output
file even when a command fails. The source graph must pass the existing graph
parser and contain 1..256 items. Maximum summed duration is 154828800 seconds,
within the implementation's integer range.

Library APIs are `declared_graph_timing_v1(source_graph, estimates)` and
`graph_timing_csv_v1(report)`. The CLI uses the same library calculation. Focused
native tests cover a diamond, unequal and tied paths, zero milestones, reverse
source order, shortcut/duplicate edges, disconnected branches, malformed
estimates and the maximum chain. `scripts/verify_graph_timing.py` additionally
checks real CLI JSON/CSV against an independent exhaustive-path oracle, changed
estimates, refusals and unchanged workspace bytes. Fixtures and logs are
retained by the verifier under its explicit workspace-parent argument.
