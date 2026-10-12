# Import a mixed JSONL work queue

Use `plan preview-queue` to inspect a UTF-8 JSON Lines/NDJSON export and
`plan from-queue` to save the same editable plan. Unlike the fixed-template
JSON-array records importer, each queue object explicitly selects an original
source work item as its template. This lets an operator combine verification,
reporting, or other declared job types without hand-converting an export or
splitting it into separate plans.

```sh
moonflow plan preview-queue WORKSPACE source-graph.json mapping.json queue.jsonl release-queue 2026-10-10T00:00:00Z
moonflow plan from-queue WORKSPACE source-graph.json mapping.json queue.jsonl release-queue 2026-10-10T00:00:00Z
moonflow plan inspect WORKSPACE release-queue
moonflow plan export WORKSPACE release-queue
```

All references are existing paths relative to one workspace. Preview validates
all selected artifact paths but creates no workspace state. Save validates the
whole batch before writing; a bad late record cannot save a partial draft.
Repeating an identical save is idempotent. A different draft at the same ID is
refused instead of overwritten. Use a new ID or the existing plan editor.

## Mapping and queue

```json
{
  "contract_id": "moonflow.queue-plan-mapping.v1",
  "template_work_item_id_pointer": "/template",
  "work_item_id_pointer": "/job/id",
  "input_artifacts_pointer": "/job/files",
  "depends_on_pointer": "/job/after"
}
```

Each physical line is one complete JSON object:

```jsonl
{"template":"report-template","job":{"id":"report","files":["requests/report.json"],"after":["check"]}}
{"template":"verify-template","job":{"id":"check","files":["requests/café.json"],"after":[]}}
```

Both templates must exist in `source-graph.json`. Input ordering is preserved;
forward dependency references are valid. The original source items are replaced
by the queue items, rather than added to the batch. Dependencies refer only to
new queue IDs; original template dependencies are not implicitly inherited.
Every selected operation, product, schema, authority, and claim stays attached
to that exact source template. Unmapped queue fields, even `operation` or
`requested_authority`, cannot change those declarations.

Pointers use the same JSON Pointer rules as record plans: `/`-separated keys,
`~1` for slash, `~0` for tilde, canonical zero-based array indices, and an empty
pointer for the whole record. No wildcards, JSONPath, expressions, or inferred
fields. The required selectors must yield a template ID string, a new item ID
string, and a nonempty array of artifact-path strings. Unknown mapping fields
are refused.

Optional selectors:

- `depends_on_pointer`: array of new queue IDs; omission/null means no dependencies
- `acceptance_criteria_pointer`: nonempty string array; omission/null inherits the selected template's criteria
- `timeout_ms_pointer`: integer JSON number in 1..86,400,000; omission/null inherits the selected template's timeout

Configured selectors must resolve in every record. Missing, null, and mistyped
record values are errors. Values are not trimmed or split. IDs, duplicate
artifacts/dependencies, missing dependency targets and cycles use normal plan
validation. Original source IDs cannot be reused as new queue IDs.

## Provenance and boundaries

The receipt includes the raw queue's SHA-256, canonical mapping digest, and an
ordered list of physical line numbers, new work item IDs, and selected template
IDs. Parser/selector errors name the physical line; graph-wide errors name the
batch and relevant item/dependency. LF, CRLF, and one terminal newline are
accepted. Blank lines, a UTF-8 BOM, and non-object lines are refused; no records
are silently skipped. Escaped newlines within a JSON string are ordinary data.

Identical materialized plans remain identical even if line endings or trailing
newline change; the receipt's raw queue digest distinguishes those exports.
The mapping digest uses Flow's existing canonical plan digest, not an origin or
authorization proof. The saved draft retains its source graph, template bindings
and edits. It does not archive the queue or receipt; keep both for audit context.

Bounds: 1..256 object lines, queue <=1,048,576 UTF-8 bytes, JSON depth 64. CLI
source graph + mapping + queue <=2,097,152 bytes. Files are fully read before
these byte checks. Pure API `declared_plan_from_queue_v1` bounds queue bytes and
records; its source graph/mapping JSON values have no serialized byte limit.

Preparation still checks current input files and exact catalog health. Import,
authority decisions and dispatch remain separate. This feature creates no runs,
attempts, approvals, external effects, payload files, or accepted work. It does
not consume/delete a queue, tail a stream, acknowledge jobs, fetch a network
queue, provide live health, or perform autonomous scheduling. Fixed-template
`plan preview-records` / `plan from-records` remain unchanged.
