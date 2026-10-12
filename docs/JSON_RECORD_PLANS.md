# Import a nested JSON work queue

Import API exports or local JSON records directly as an editable declared batch.
An explicit mapping selects a record array and typed fields inside each record.
Nested input and dependency lists keep their order and exact strings without
CSV escaping, splitting, flattening, interpolation or handwritten work graphs.

```text
moonflow plan preview-records WORKSPACE source-graph.json mapping.json records.json batch 2026-07-31T00:00:00Z
moonflow plan from-records WORKSPACE source-graph.json mapping.json records.json batch 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE batch
moonflow plan export WORKSPACE batch
moonflow plan prepare WORKSPACE batch catalog.json 2026-07-31T00:00:00Z
```

The [complete synthetic sample](../examples/records-plan/README.md) includes a
source operation, nested export, mapping, capability bundle and input files.
Its July evaluation date matches fixture health, not current production health.

## Mapping

```json
{
  "contract_id": "moonflow.records-plan-mapping.v1",
  "records_pointer": "/data/jobs",
  "template_work_item_id": "make-model",
  "work_item_id_pointer": "/ticket/key",
  "input_artifacts_pointer": "/work/files",
  "depends_on_pointer": "/work/after",
  "acceptance_criteria_pointer": "/review/checklist",
  "timeout_ms_pointer": "/work/timeout_ms"
}
```

`records_pointer` addresses the export root. Every other pointer addresses each
record object independently. JSON Pointer syntax supports an empty pointer
(the root), slash-separated object keys, zero-based array indices, `~1` for a
literal slash and `~0` for a literal tilde. `/` selects an empty object key.
Array indices must be canonical decimal integers, so `01` and `-` are invalid.
There are no wildcard, JSONPath, URL-fragment or expression selectors.

- `work_item_id_pointer`: required, selects a string with a unique safe new
  work item ID, distinct from all source IDs.
- `input_artifacts_pointer`: required, selects a nonempty array of unique
  existing workspace-relative artifact path strings.
- `depends_on_pointer`: optional, selects an array of imported item IDs.
  Omit the selector for independent rows. Forward references are supported.
- `acceptance_criteria_pointer`: optional, selects a nonempty string array.
  Omit the selector to copy the exact template criteria.
- `timeout_ms_pointer`: optional, selects a JSON whole number in 1..86,400,000.
  Omit the selector to copy the template timeout. Numeric strings and fractional
  values are not coerced.

An omitted or null optional mapping selector uses the described default. Once
configured, a pointer must resolve in every record to the expected type;
missing/null data does not silently drop a record or fall back to a default.
Strings are not trimmed or split. Additional export fields are ignored.
Unknown mapping fields are rejected, so an operation or authority selector
cannot change the frozen source contract. Records must be objects.

## Result and next steps

Preview reads and validates the full batch and all selected local input paths,
then prints the expanded form without creating workspace state. Save performs
the same validation and persists one normal v2 draft. The receipt includes
ordered record IDs, export and mapping references, raw export SHA-256 and
canonical mapping SHA-256. Repeating an identical save is idempotent;
conflicting rows under an existing draft ID require reopening/editing that
draft or choosing a new ID.

The draft retains the exact source graph and materialized edits, so later
export or mapping changes do not silently change the saved plan. The source
bytes and import receipt are not separately archived by this command; retain
them when provenance matters. Whitespace changes to JSON alter the raw digest,
but identical materialized rows can still reopen the same draft.

Every record clones one original operation, with new declaration lineage and
unchanged product, operation version, schemas, authority and claim ceiling.
The batch replaces the source item set; source dependencies are not copied.
Only explicit batch dependencies are used. `plan edit` and `plan prepare`
continue normally; preparation checks current catalog health and input paths
and produces a content-addressed graph/proposal for conformant import.

## Boundaries and verification

The import accepts 1..256 records and at most 1,048,576 UTF-16 code units of JSON,
with parsing depth limited to 64. Malformed pointers, missing fields, wrong
types, unsafe input references, duplicate IDs, cycles and outside dependencies
reject the complete import before save. This is local JSON intake, not a live
API connector: no fetching, pagination, credentials or provider access occurs.
There is no JSON Lines/NDJSON parser. Product payloads are referenced, not
generated, merged, frozen or domain-validated. No runs, approvals or attempts
are created by preview/save, and no execution or customer acceptance is implied.

Focused library tests exercise nested fields, arrays, escaped keys, root arrays,
defaults, typed timeouts, forward dependencies, edits, preparation, deterministic
identities, exact operation preservation and the bounded malformed-input paths.
The compiled CLI journey previews, saves, repeats, exports, edits, prepares,
imports and advances a synthetic three-item batch. No external adapter, provider,
graphical UI, restart recovery or full-module qualification is claimed.
