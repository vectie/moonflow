# Turn parameter axes into editable request batches

Use a matrix when a study needs every combination of explicitly chosen values:
for example, two model labels × two unit systems × two coordinate frames. Supply
a declared source operation, its JSON request template, and a small matrix file.
Preview the exact requests before saving the normal editable plan and input files.

```sh
moonflow plan preview-matrix WORKSPACE source-graph.json matrix.json request-template.json study 2026-07-31T00:00:00Z
moonflow plan from-matrix WORKSPACE source-graph.json matrix.json request-template.json study 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE study
moonflow plan export WORKSPACE study
moonflow plan prepare WORKSPACE study catalog.json 2026-07-31T00:00:00Z
```

Use current evaluation time and matching current catalog health for real work.
The runnable [matrix example](../examples/matrix-plan/README.md) uses synthetic
July fixtures; it does not execute a product adapter. Check command exit status:
the inherited CLI prints failure diagnostics on stdout, which are not JSON receipts.

## Matrix and binding format

```json
{
  "contract_id": "moonflow.matrix-plan.v1",
  "item_prefix": "study",
  "template_work_item_id": "make-model",
  "axes": [
    {"name": "size", "values": [
      {"key": "small", "value": 12.5},
      {"key": "large", "value": 25}
    ]},
    {"name": "finish", "values": [
      {"key": "plain", "value": null},
      {"key": "red", "value": {"color": "red", "matte": true}}
    ]}
  ],
  "bindings": [
    {"target_pointer": "/request_id", "value_pointer": "/id"},
    {"target_pointer": "/idempotency_key", "value_pointer": "/id"},
    {"target_pointer": "/size", "value_pointer": "/parameters/size"},
    {"target_pointer": "/finish", "value_pointer": "/parameters/finish"}
  ]
}
```

This generates `study--small--plain`, `study--small--red`,
`study--large--plain`, and `study--large--red`, in that order. The last axis
varies fastest. Every axis participates; there is no zip, sampling, exclusion,
expression evaluation, coercion, interpolation, trimming, or inferred parameter.
Duplicate JSON values with different keys remain distinct declared combinations.
Each combination record contains:

- `id`: prefix plus the chosen keys, joined with `--`
- `keys`: axis names mapped to the chosen key strings
- `parameters`: axis names mapped to the exact chosen JSON values

Bindings use JSON Pointers into this record, such as `/id`, `/keys/finish`,
`/parameters/finish/color`, or an escaped nested object key. Targets address
existing request-template locations. Strings, numbers, booleans, nulls, arrays
and objects retain their types. Explicit null is a value; an absent `value`
field is an error. Unbound template fields are retained. The template must be
an object; root replacement, missing target locations, overlapping targets and
noncanonical array indices are refused by the existing payload materializer.
See [payload bindings](PAYLOAD_TEMPLATE_PLANS.md) for full pointer semantics.

Map `/id` into the operation's request/idempotency identity fields when distinct
jobs require distinct identities. Flow does not discover or rewrite domain IDs.
If bindings omit identity and produce equal payloads, those jobs share the same
content-addressed input bytes. Check that this is meaningful for the adapter.
No domain payload schema validation or effects occur during preview or save.

## Stable selection and editable output

Keys and prefix have 1–64 ASCII letters, digits, underscores or hyphens, cannot
contain `--`, and cannot start or end with a hyphen. Axis names have 1–64 ASCII
letters, digits or underscores, and must be distinct. Keys must be unique within
an axis, but can appear in different axes. Generated IDs must be at most 128
characters and distinct from all source item IDs. These constraints prevent
ambiguous joined identities, rather than silently escaping or truncating keys.

Reordering choices changes row order but preserves each combination's ID and
request bytes. Reordering axes changes the joined ID. Changing a value under a
key retains its logical item ID but changes its request bytes. Axis names and
values are not encoded into item IDs; choose a new prefix when reusing a name
would misrepresent the study. The matrix digest binds the complete ordered
specification using the existing plan identity helper, not a raw-file hash or
signature. JSON object field order does not affect this digest.

Every generated item clones the chosen source operation's exact product,
operation/version, schemas, authority, claim ceiling, criteria and timeout.
The batch replaces the original source item set. Source dependencies and input
paths are not copied: each new item starts independently with one generated
primary input. Matrix axes do not create work dependencies or dataflow. Use the
existing plan editor if a particular batch needs additional files, criteria,
timeouts or dependency edges; normal cycle/file checks still apply.

Preview creates no workspace state. Save uses the same content-addressed input
materialization as payload plans and publishes the draft last. Identical saves
are idempotent; a conflicting or edited saved draft is never replaced. Changed
matrix studies need a new draft ID, or deliberate edits of the existing plan.
An existing addressed object whose bytes differ is refused. A disk/process
failure may leave unreferenced input objects; this is not a multi-file transaction.

The receipt includes the ordered combination records, matrix/template digests,
exact request strings and hashes, and complete editable form. Retain it and the
inputs for provenance: the saved draft stores the materialized requests and
source graph, not a live matrix or separately persisted receipt. Later changes
to the matrix/template cannot silently update the saved plan.

## Limits and scope

1–8 axes; 1–256 choices per axis; at most 256 total combinations. The product
count is checked before any combination or request is materialized. Matrix
JSON and expanded record text each have a 1,048,576 UTF-16 code-unit limit;
matrix parsing depth is 64. Inherited payload limits also apply: 1–64 explicit
bindings, template size/depth bounds, 1 MiB per generated UTF-8 request and
8 MiB generated request bytes total. CLI inputs use existing contained-file
checks and 16 MiB read limits; file reads precede those size rejections.

Unknown matrix/axis/choice fields, empty axes, duplicate keys/names, malformed
pointers, unknown source template IDs and invalid generated declarations
reject the whole batch before save. No new dependencies were added.

Pure host API:
`declared_plan_from_matrix_v1(source_graph, matrix, request_template, draft_id, recorded_at)`.
It returns `MatrixPlanImportV1`, including combination records and the existing
`PayloadPlanImportV1`. Caller JSON is not mutated and returned values are detached
from the caller. Hosts own containment and materialization; the native CLI shares
the established payload save path. Preparation checks the existing catalog and
files. Conformant import, authority, dispatch and review remain later operations.
This focused workflow does not qualify live adapters, company-task return,
customer acceptance, payments, or the historical cumulative runtime.
