# Generate requests for a complete repeated workflow

Turn each JSON record into a complete editable workflow with real request files
for every step. For example, each study can have setup, two parallel candidates,
and a final comparison. Each operation gets its own request template and explicit
typed bindings; dependencies are copied from the selected source graph.

[Table plans](TABLE_WORKFLOW_PLANS.md) already repeat a graph using existing
input files, while [payload plans](PAYLOAD_TEMPLATE_PLANS.md) generate requests
for one operation. This workflow joins those authoring primitives: one record
produces all the requests and same-record dependency edges together.

## Preview, save, edit, and prepare

```sh
moonflow plan preview-workflow-payloads WORKSPACE source-graph.json workflow.json records.json study 2026-07-31T00:00:00Z
moonflow plan from-workflow-payloads WORKSPACE source-graph.json workflow.json records.json study 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE study
moonflow plan export WORKSPACE study
moonflow plan prepare WORKSPACE study catalog.json 2026-07-31T00:00:00Z
```

Use actual timestamps and current catalog health for real work. The complete
[two-study example](../examples/workflow-payload-plan/README.md) uses the dated
synthetic catalog and explicitly non-executable fixture payloads. Check exit
status before parsing output: inherited CLI errors use stdout.

Preview prints the complete editable form and every exact generated JSON string,
path and digest. It writes no workspace state. Save validates the complete plan
and any ancillary files, checks saved-draft identity and existing input objects,
materializes missing request objects, and publishes the ordinary v2 draft last.
Identical saves reopen the same draft; a changed or edited draft is never replaced.
Choose a new draft ID for a different batch or use the existing plan editor.

Preparation checks the current exact catalog and input files and returns normal
`graph_ref` and `proposal_ref` artifacts. Use the existing explicit conformant
import or revision workflow afterward. Preview, save and prepare create no runs,
attempts, authority grants, adapter effects or accepted work.

## Explicit workflow specification

```json
{
  "contract_id": "moonflow.workflow-payload-plan.v1",
  "records_pointer": "/jobs",
  "record_id_pointer": "/key",
  "steps": [
    {
      "template_work_item_id": "check",
      "request_template": {"request_id": "", "parameters": null},
      "bindings": [
        {"target_pointer": "/request_id", "value_pointer": "/work_item_id"},
        {"target_pointer": "/parameters", "value_pointer": "/record/check_parameters"}
      ]
    }
  ]
}
```

Provide exactly one `steps` entry for every source work item. The example above
is sufficient only for a one-step source called `check`. A missing, duplicate,
unknown or extra step fails the whole batch. Step-entry order is irrelevant;
output follows record order, then original source item order. Source graphs may
be non-topological or contain disconnected components, but must pass ordinary
declared-plan validation, including known acyclic dependencies.

`records_pointer` selects a nonempty array. `record_id_pointer` selects a safe
unique string from each record, and every record must be an object. Generated
item IDs are `record_id.source_step_id`; all must be distinct, at most 128 ASCII
letters/digits/dots/hyphens/underscores, contain no `..`, and differ from every
source item ID. Ambiguous combinations such as `a` + `b.c` and `a.b` + `c` are
refused, never renamed. Values and identifiers are not trimmed or coerced.

Every step's `value_pointer` addresses this explicit binding context:

```json
{
  "record": {"key": "chair", "check_parameters": {"width": 42.5}},
  "record_id": "chair",
  "step_id": "check",
  "work_item_id": "chair.check"
}
```

`record` retains the complete original record. The three identity fields are
computed outside it, so record fields cannot override them. Map `work_item_id`
into domain request/idempotency fields when distinct steps require distinct
identities. Flow never discovers or changes embedded identifiers automatically.

Bindings use existing JSON Pointer semantics: `~0` and `~1` escapes, canonical
array indices, and no JSONPath, wildcards, expressions, interpolation or fallback.
Every target must already exist in the object request template. Root replacement,
duplicate/overlapping targets, missing fields and scalar traversal fail. Each
step requires 1..64 bindings. Selected objects, arrays, numbers, booleans, strings
and nulls retain their types; unselected template fields retain their values.
Output whitespace and object key order are canonicalized by the existing payload
writer. This is generated JSON, not a byte copy of the original template.

Optional per-step selectors, addressing the same context:

- `additional_input_artifacts_pointer`: a string array of existing files appended
  after the generated primary request
- `acceptance_criteria_pointer`: a nonempty string array replacing source criteria
- `timeout_ms_pointer`: a JSON integer in 1..86,400,000 replacing source timeout

Omitted or null selectors inherit criteria/timeout or add no ancillary files.
A configured selector must resolve in every record; missing/null/wrongly typed
values do not silently default. Unknown specification and step fields are refused.

## Dependency and identity rules

Every source step is copied once per record with its exact product, operation,
schemas, authority and claim ceiling. Fresh declaration lineage uses the existing
v2 template-binding contract. Opaque item extensions are retained, including any
embedded old IDs. Original primary and ancillary input paths are replaced by the
generated request and explicitly selected ancillary inputs. Criteria and timeout
are inherited unless mapped above.

Each source dependency is prefixed with that record's ID. A diamond remains a
diamond within each record; independent records remain independent. There are
no shared setup steps, cross-record edges, conditionals or inferred links in this
version. Source dependencies cannot be overridden in the import specification;
deliberate later edits use the ordinary plan editor and validation.

Dependency edges only order declared work. They do not feed one step's result
into another request. All inputs must already exist or be generated at save.
No output files, paths inside opaque payloads or product-specific schema rules
are inferred. Product adapters retain domain validation and execution ownership.

Generated bytes use the existing content-addressed `plan-inputs/<sha256>/artifact`
store. Equal request bytes share an object even across distinct steps. The saved
draft retains materialized paths and the source graph, rather than a live query
against the records or specification. Changed records never silently update it.
The printed receipt includes raw record-text SHA-256 and canonical workflow
digest; retain that receipt and original inputs if import provenance matters.
Digests are reproducible identities, not origin or authority proofs.

Save uses the established payload materializer: changed existing objects are
refused, not overwritten. A filesystem/process failure can leave unreferenced
objects before draft publication; identical retry can finish it. This is not a
multi-file transaction or a concurrent-filesystem-adversary guarantee. Preparation
uses the ordinary current-input behavior; materialization is not a perpetual
integrity monitor for files modified later by another actor.

## Bounds, API and qualification

The complete source has 1..256 steps and the expansion has at most 256 items.
The product count is checked before generating requests. Record text and workflow
specification each allow at most 1,048,576 UTF-16 code units with parsing depth 64.
Each per-step expanded binding-context export also obeys the payload importer's
1,048,576-code-unit limit; context wrappers count toward it. Request templates
and target semantics use the existing payload bounds. Generated requests allow
1 MiB per file and 8 MiB total, counting every item even when bytes are shared.
CLI source/specification/records together allow 4 MiB; reads occur before the
combined limit check and retain the existing 16 MiB per-file read limit.

Pure API:
`declared_plan_from_workflow_payloads_v1(source_graph, workflow, records_json, draft_id, recorded_at)`
returns `WorkflowPayloadPlanImportV1`, including detached artifacts and the normal
draft. Pure callers own filesystem containment/materialization. The native CLI
reuses existing regular-file, contained-path and payload publication helpers.

Focused native and JS library tests plus the native CLI journey exercise typed
data, identities, topology, editable save/reopen, request bytes, preparation and
import. The harness also checks late invalid records, missing ancillary inputs,
path escape/symlink refusal, conflicting saves, altered addressed objects and
expired health. These are bounded local authoring checks, not external adapter,
installed lifecycle, browser, company-task return or release qualification. The
historical broad native aggregate remains incomplete and is not upgraded here.
