# Compare recorded results across runs

Use two runs of the same book to see what changed after revising declared work:

```sh
moonflow compare-runs WORKSPACE release-run release-r2 --text
moonflow compare-runs WORKSPACE release-run release-r2 --json
```

The command replays each canonical `events.json` independently and writes only
stdout. It ignores cached `projection.json` and creates no run, attempt, receipt,
approval or artifact. Inputs need not exist for recorded references to be shown.

## Matching and direction

The first run is **before**, the second **after**. This is your chosen comparison,
not proof of parent-child ancestry or chronological ordering. Both runs must have
recorded source identity and the same `book_id`. Their exact revisions, source
digests, last event IDs/sequences, recorded timestamps and outcomes are shown.
Two distinct run IDs are required; timestamps are not used to order anything.

Items are matched by exact `declaration_id`, the stable identity used by revision
migration. A renamed `work_item_id` stays in the same row. A reused item name
with a different declaration becomes a removal and an addition. Ambiguous
repeated declaration IDs are refused rather than guessed. Rows follow before-run
registration order, then after-only declarations in after-run registration order.

Each row is `added`, `removed`, `changed` or `unchanged`. The JSON contract is
`moonflow.run-comparison.v1`. It includes counts, complete detached item snapshots
(`before`/`after`, with explicit null for absence), ordered `changed_fields`, and
exact `retained_artifacts_added` / `retained_artifacts_removed` reference lists.
For added/removed rows `changed_fields` is empty; the full present side describes
the item. Text prints every changed value and full added/removed snapshots.

## What is compared

The snapshots contain all current recorded declaration and runtime item fields:
work/declaration/product IDs, requested authority, criteria, operation, input and
output contracts, claim, input artifact references, timeout, raw dependency IDs,
status, attempt count/request/attempt/idempotency/external-job IDs, attempt
status, input/result/output identity, error, compensability, blocker, review
identity/artifact/reviewer, retained artifacts and recorded approvals.

Changed fields use that fixed order (excluding `declaration_id`, the match key).
Arrays are compared exactly, including order. Renamed raw dependency IDs are a
reported difference even if their declarations match; no semantic equivalence
is inferred. Run-head identity is shown separately and does not itself mark
every item changed. An unchanged item means identical recorded item fields,
not identical event history. Use `run-history` for every event and past attempt.

Artifact additions/removals are reference set differences in each side's retained
order. “Removed” means absent from this after-run record, never deleted from disk.
Retained references may include earlier attempts and review evidence. No file
contents or digests are freshly verified and equal paths do not prove equal
bytes. Recorded output digests remain visible even when paths are equal.

A checkpoint reuse remains `attempt_status=checkpoint-reused` with the existing
engine's attempt count and original receipt/review identities. A succeeded
attempt in `review` is not accepted. Internal acceptance establishes neither
customer acceptance nor payment. The comparison is never a retry, migration,
checkpoint eligibility or authority decision.

## Bounds and observation limits

Each side accepts at most 4096 supplied events (including duplicate deliveries)
and 256 items. Duplicate events use the existing replay contract: identical
copies collapse and conflicting copies fail. The full histories are validated
before output. A declared run with no items is valid; an empty event file has no
source identity and is refused. Both sides must pass independently.

CLI files are contained workspace-relative run stores with safe run IDs, at most
8 MiB each, valid UTF-8 JSON of maximum depth 64. The byte limit is checked after
a complete file read. Pure APIs have event/item bounds but no serialized byte
limit. The two reads are separate observations, not an atomic or live snapshot.
This cannot discover an unimported revision or a later unseen event. Unknown
JSON extension fields are not compared; this is not a backup or byte-level diff.

Public APIs: `compare_run_events_v1(before_run_id, before_events, after_run_id,
after_events)` and `run_comparison_text_v1(report)`. Reports own their mutable
snapshot arrays; mutating caller events later cannot rewrite a report.
