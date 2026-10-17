# Prepare workflows from jobs and reference data

Join a jobs export to a separate model, catalog or settings export before preparing
all the requests for each job. Keep shared reference data in one place, inspect
the exact matched records and payloads, then save a normal editable plan. No
spreadsheet formulas or repeated manual copying into each request are needed.

```sh
moonflow plan preview-joined-workflow WORKSPACE source-graph.json workflow.json join.json jobs.json models.json study 2026-07-31T00:00:00Z
moonflow plan from-joined-workflow WORKSPACE source-graph.json workflow.json join.json jobs.json models.json study 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE study
moonflow plan export WORKSPACE study
moonflow plan prepare WORKSPACE study catalog.json 2026-07-31T00:00:00Z
```

The [two-job example](../examples/joined-workflow/README.md) has four steps per
job and a reusable seating model. Dates there match the synthetic catalog only;
use current catalog health and real timestamps in actual work.

## Explicit matching

The `moonflow.workflow-record-join.v1` specification contains exactly
`primary_records_pointer`, `lookup_records_pointer`, `primary_key_pointer`,
`lookup_key_pointer`, and `unmatched`, alongside `contract_id`. Dataset pointers
select arrays; key pointers address each record separately. Both datasets must
contain objects. Pointers use the existing RFC 6901 rules, including `~0` and
`~1` escapes and canonical array indices.

Keys are non-null JSON strings, numbers or booleans. Types do not coerce: string
`"1"`, number `1` and boolean `true` differ. Number keys use exact source token
spelling: `1.0` and `1` differ, as do large integers and close decimal fractions.
The raw JSON reader preserves those tokens through generated requests and
rejects duplicate decoded object keys. No arithmetic, rounding, case folding,
trimming or fuzzy matching is added. Prefer string identifiers for external
systems with their own numeric conventions.

Each lookup key must be unique across the whole reference array, including
unused rows. Duplicate matches reject the complete preparation. Multiple jobs
may deliberately reuse the same lookup row. Output preserves primary order;
lookup order has no effect on matching. No fan-out or automatic row dropping
occurs. Select the desired reference row explicitly in the input if multiple
versions share an identifier.

Set `unmatched` to `error` to require a match for every job. Set it to `null`
to retain unmatched jobs with `lookup: null`. Preview lists their one-based
primary row numbers and unused lookup row numbers. Missing keys and null keys
remain errors in either mode. An empty reference dataset is allowed; an empty
primary batch is refused.

## Map joined data into requests

Each output record has precisely `{"primary": <original job>, "lookup":
<matched reference or null>}`. Original objects are retained without field
merging, so colliding names cannot overwrite one another. The workflow uses
`records_pointer: ""` and typically `record_id_pointer: "/primary/key"`.
Step binding paths are `/record/primary/...` or `/record/lookup/...`, inside
the ordinary workflow context. The complete joined records and every generated
request appear in preview, alongside original dataset digests.

A null-mode workflow must explicitly handle the nullable shape: binding the
whole `/record/lookup` is supported; dereferencing a child of null fails. There
are no expressions, fallback values, hidden filters or conditional steps.

## Save, reopen and continue

Preview validates all generated requests and ancillary paths without changing
workspace state. Save materializes ordinary content-addressed requests and
publishes the existing v2 draft. Identical retry reopens the draft; conflicting
data never replaces a saved or manually edited draft. Reopen it with `plan
inspect`, use normal `plan edit` operations, then prepare against the current
catalog. To re-import changed job/reference data, choose a new draft ID.

The saved plan contains fixed records/requests, not a live lookup. Retain input
files and the printed receipt if join provenance matters. Existing preparation,
explicit import/revision, authority, execution and review gates remain unchanged.
No runs, attempts, grants, external calls or adapter effects occur in preview/save.
Dependency edges retain each source step's same-job topology; they do not pass
runtime outputs into later requests.

## Supported scope and verification

Primary arrays allow 1..256 records, reference arrays 0..4096. Each raw dataset
allows 1,048,576 UTF-16 code units and parse depth 64. Joined data must fit the
existing workflow's 1,048,576-code-unit bound and at most 256 expanded items;
generated requests retain the existing per-file 1 MiB and total 8 MiB limits.
CLI inputs together allow 4 MiB; contained reads retain the pre-existing 16 MiB
per-file limit before the aggregate check. These are in-memory local exports,
not a connector, streaming processor or database join engine.

The API `declared_plan_from_joined_workflow_v1` returns detached matched data
and a `WorkflowPayloadPlanImportV1`. Native/JS focused tests and the native CLI
journey cover matching, repeated and ambiguous keys, missing rows, scalar types,
real request bytes, editing, current catalog preparation and explicit import.
They do not qualify external adapter execution, graphical hosts, installed
lifecycle, restart behavior or the full authored release gates.
