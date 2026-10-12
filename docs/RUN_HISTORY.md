# Inspect a run's recorded timeline

Find out how work reached its current state without manually reading event JSON:

```sh
moonflow run-history /absolute/workspace release-run --text
moonflow run-history /absolute/workspace release-run --json > release-history.json
moonflow run-history /absolute/workspace release-run --text verify-red
```

The optional last argument selects one exact work-item ID. The command always
replays the entire canonical `events.json`, including unselected items, before
printing anything. Invalid history, an unknown selection, a missing store or an
unsupported format fails with no partial report. Cached `projection.json` is
ignored. No files, runs, attempts, decisions or approvals are written. Shell
redirection can still create a file: use a fresh destination and check exit
status before consuming it. The inherited CLI error handler prints diagnostics
to stdout, so failed stdout is not a timeline report.

## Reading the timeline

Each row contains the normalized recorded event, the affected item's state
immediately before and after that event, and the whole-run outcome before and
after. This makes earlier attempts, unknown results, reconciliation, review
rejection, acceptance and checkpoint reuse inspectable in one sequence.

- Rows follow canonical sequence, never timestamp sorting. Timestamps remain
  recorded values; they need not increase and are not elapsed-time measurements.
- The event object contains only that event's known contract fields. Blank
  identity or evidence fields remain blank; later attempt or review fields are
  never attributed backward to earlier events. Decoder defaults are normalized;
  unknown JSON extensions and original byte formatting are not preserved.
- Item snapshots contain declaration/product/operation identity, status, attempt
  count and correlation, result and digests, error/blocker, review identity,
  retained artifacts and recorded approvals. Arrays are detached snapshots.
- `before: null` means no affected item existed yet. Both snapshots are null for
  a run-level event. Registration has a null before and proposed after state.
- Snapshots' retained artifacts/approvals are cumulative state, including older
  evidence. They are not a claim that the current event produced those files.
  Use `event.output_artifacts`, `event.artifact_id` and `event.authority_id` for
  evidence recorded by that event.
- Replayed identical duplicate deliveries produce no extra timeline row.
  Conflicting duplicate IDs remain errors. Counts include all supplied events,
  all canonical applied events, and omitted exact duplicate deliveries.
- An item filter affects rows only. The head and outcomes still describe the
  complete run. Run-created rows are omitted by an item filter; run/book/revision
  source context remains in the report head. Other items' later events can mean
  the head is newer than the last selected row.

Text output is compact: it displays state transitions, event correlation and
recorded evidence, plus recorded review identity when present. Arbitrary text is
JSON-quoted so control characters and newlines remain values, not timeline rows.
Use JSON for complete normalized events and all snapshot fields.

## Portable report and limits

The JSON contract is `moonflow.run-history.v1`: `head` names the run, book,
declaration revision, source digest, latest sequence/event/time and current
outcome. `selected_work_item_id` is null for all items. `entries` contains
`event`, `before`, `after`, `run_outcome_before` and `run_outcome_after`.
The pure APIs are `run_history_v1(run_id, events, work_item_id?)` and
`run_history_text_v1(history)`.

At most 4,096 supplied events, including duplicate deliveries, are supported.
The CLI accepts at most 8,388,608 bytes of UTF-8 JSON and nesting depth 64. Files
are read fully before the byte limit is checked. The pure API has the event
count bound but no serialized byte limit. An empty event array yields an empty
report with an explicit run ID, blank source/head strings and last sequence -1;
it is not evidence that a graph was imported or work was completed.

This is a read-only observation of one file read, not a live monitor, wall-clock
freshness guarantee, backup/restore qualification or external adapter journey.
Artifacts are references only: files need not exist, hashes are not recalculated,
and adapter outcomes are recorded claims. Internal accepted work does not
establish customer approval, payment, current execution permission or a safe
retry. The feature changes no replay, transition or authority policy.
