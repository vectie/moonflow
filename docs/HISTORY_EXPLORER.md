# Explore recorded run transitions offline

An operator investigating a retry, unresolved result or review change can now
read a portable timeline instead of scanning raw JSON. This consumes the existing
`moonflow.run-history.v1` export; it complements the declaration-only graph explorer.
It implements a reading workflow for MF-W02–W04 and the product contract's
operator inspection job, without moving replay or execution authority into a viewer.

## Use

With your separately installed trusted native CLI, first export a timeline:

```
moonflow run-history /absolute/workspace release-run --json > /tmp/release-history.json && python3 -B scripts/history_explorer.py /tmp/release-history.json /tmp/release-history.html
```

The `&&` is important: native errors may appear on stdout. An optional item ID
on the native export limits the report; the viewer labels that retained scope
and never reconstructs omitted events. The viewer itself invokes no native CLI.
Use Python 3.9+; no packages or server are needed. The output parent must exist,
and the output must be new. Existing paths, including the input, are refused.
An interrupted write can leave a partial new file; inspect before retrying with
a new path. Success prints exact source/output SHA-256 identities and
`dispatched:false`, not browser or runtime success.

Open the HTML locally. Item and event-kind selectors intersect with literal
case-insensitive text search across every event and its snapshots. Reset restores
all exported rows. The live count and empty message explain filtering. Every
entry has a stable local sequence link, recorded time, item/run transitions,
changed-field table and expandable complete event/before/after JSON. Run-level
entries retain null item snapshots. The complete head and export counts are
always available. Without JavaScript, all entries remain readable; print styles
show all exported rows regardless of screen filters.

Use this dependency-free synthetic example:

```
python3 -B scripts/history_explorer.py examples/history-explorer/history.json /tmp/example-history.html
```

The checked-in JSON is a synthetic schema fixture, not captured runtime evidence
and not a claim that its event stream passes native replay. Its event keys are
checked against `runtime_event_json` in source. The retained HTML is actual
renderer output. Reversed recorded timestamps deliberately demonstrate sequence
order, not elapsed time. No source file is modified.

## Identity and limits

The reader checks UTF-8 JSON, duplicate keys, contract, basic head/count shapes,
unique ordered event identities, run/selection membership and unfiltered head
agreement. Maximum input is 8 MiB and 4,096 canonical events. This is export
shape validation, NOT engine replay, event-semantic validation, authentication,
authority validation, digest verification of referenced artifacts or evidence
that the snapshot is current. Use native replay to establish native validity.
Unknown JSON annotations remain visible in complete JSON and search as data.

The exact imported-file SHA-256 binds the full report bytes. The recorded source
identity in the head is merely reported. Snapshots contain cumulative retained
artifacts and approvals; they must not be attributed to the current event.
Changed-field cells use JSON null for an absent field as well as explicit null;
the complete snapshots disambiguate them. Fields that did not change remain in
the expandable complete snapshots. Links and commands inside evidence are text,
never fetched, executed or navigated. All source markup is escaped.

No network, storage, provider or current workspace access occurs. The page
contains all included private evidence even when filters hide it; export does
not authorize sharing. No decision form or run-control action is added.

## Checks and qualification

```
python3 -B scripts/test_history_explorer.py
node scripts/test_history_explorer.mjs
```

Six Python checks exercise the reader, evidence output, source-schema keys,
selected/empty exports, deterministic output and actual CLI creation/reopen.
The Node check executes the JavaScript extracted from the generated HTML with
a small DOM adapter to test filter intersections and reset. It is not a browser,
visual, accessibility, native engine or MoonDesk host qualification. No Moon
command, dependency install, schema version or MoonBit interface change occurs.
