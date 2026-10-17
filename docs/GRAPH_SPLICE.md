# Replace a step with a reusable workflow

Expand one step in an existing declared plan into a complete reusable graph.
For example, replace a single design step with a setup, two parallel design
branches and their final join. Flow connects the replacement's prerequisites
and downstream consumers in one validated edit, so you do not have to rename
every inserted item and rebuild the surrounding edges by hand.

This exercises the declaration-validation slice of MOONFLOW-B02. It creates
new declared work only. It does not run adapters, copy acceptance, validate
product payload semantics, or qualify the full requirement or a live handoff.

## Preview and export

Place both graphs and a manifest in the same selected workspace:

```json
{
  "contract_id": "moonflow.graph-splice-manifest.v1",
  "graph_id": "expanded-study",
  "source_graph_ref": "source.json",
  "replace_item_id": "left",
  "module_graph_ref": "module.json",
  "alias": "detail",
  "recorded_at": "2026-07-31T00:00:00Z"
}
```

```sh
moonflow graph-splice /absolute/workspace splice.json --json
moonflow graph-splice /absolute/workspace splice.json --graph > /absolute/workspace/expanded.json
moonflow plan start /absolute/workspace expanded.json expanded-edit existing-graph 2026-07-31T00:00:00Z
moonflow plan inspect /absolute/workspace expanded-edit
moonflow plan prepare /absolute/workspace expanded-edit catalog.json 2026-07-31T00:00:00Z
```

Use actual timestamps and current catalog health outside the synthetic example.
The CLI prints errors on stdout; check exit status before treating redirected
output as a graph. Redirect only to a fresh filename, never over any input.
Both splice modes print a result and write no workspace state. Shell redirection
is your separate file write. Preparation and import remain explicit later steps.

The report includes the removed declaration in full, exact source/module graph
digests, new item/declaration mappings, all inserted roots and terminals, inherited
prerequisites, and each changed downstream dependency list. Inspect that report
before using the graph. `--graph` returns precisely the report's `graph` member.

## Boundary rules

- The removed step must exist exactly once. Both complete input graphs must
  already pass the ordinary declared-plan validator, including all dependencies.
- Module IDs become `alias.original-id`. Internal edges are renamed the same
  way. Every module root, meaning an item without prerequisites, inherits all
  prerequisites of the removed step.
- Every occurrence of the removed ID in a surviving item's dependency list is
  replaced by all module terminals, meaning items with no downstream consumers.
  Other prerequisites stay in place and retain their order. Input graphs with
  repeated dependency references are rejected by the ordinary validator; splice
  does not silently deduplicate invalid input.
- Multiple roots, multiple terminals and disconnected module components are
  supported. Every component starts behind the same inherited prerequisites;
  downstream work waits for all component terminals. A disconnected component
  is not silently omitted. Cycles and references outside the module are refused.
- Inserted items occupy the removed step's position in the host's item order.
  Their internal order follows the module, even when it is not topological.
  Surviving host item/declaration IDs remain unchanged. Every inserted declaration
  gets a fresh `splice:` identity bound to the complete request. All new IDs must
  be distinct from every original host ID, including the removed one.
- Only item/declaration IDs and the described dependency edges are rewritten.
  Operations, owners, authority, schemas, claim, criteria, timeouts, artifact
  references and opaque item extensions retain their exact values. The removed
  step's criteria and authority do not transfer to the module. Review the module's
  declarations before import; replacement does not authorize new operations.

Dependency edges declare ordering. They do not feed output files into input
files. Input paths stay relative to the selected workspace, rather than the
JSON file's directory. Opaque embedded IDs/paths are not renamed. No payload or
output file is copied. Customize declared inputs/criteria with the ordinary
plan editor and let the product adapter validate its own payloads.

The result uses the host's book ID, a distinct operator-selected graph ID,
revision `splice-v1`, the request digest as source digest, and the supplied
timestamp. Source top-level extensions are not merged. The result is a new
declaration, not an in-place amendment of the Book or an existing run. No events,
attempts, checkpoints, results, approvals or acceptance history are copied.
The ordinary `plan start` route shown here prepares a new run; it does not
automatically connect the result to an imported host run for checkpoint reuse.

## Prepare and explicitly import

Preparation checks workspace-contained input files, exact capability contracts
and fixture/current health through the existing planner. It returns `graph_ref`
and `proposal_ref`. A separate explicit import can use the prepared graph:

```sh
moonflow import-conformant-graph /absolute/workspace /absolute/workspace/RETURNED_GRAPH_REF /absolute/workspace/catalog.json 2026-07-31T00:00:00Z
```

Replace `RETURNED_GRAPH_REF` with the actual returned relative path. Import
creates the ordinary durable event history, without dispatching an attempt.
Fresh invocation-time authority and normal adapter/review rules still apply.

## Bounds and library API

Both sources and the result contain at most 256 items. The CLI reads contained
existing manifest/source/module references and caps their combined bytes at
2 MiB after each file read. The pure API has item bounds but no serialized byte
cap. Safe new graph IDs, aliases and inserted IDs use at most 128 ASCII letters,
digits, underscores, hyphens or dots; `.` and `..` are refused as in composition.

`splice_declared_graph_v1(request : Json) -> Json raise` uses
`moonflow.graph-splice-input.v1`; replace the manifest's two `*_graph_ref` fields
with embedded `graph` and `module` objects. The API is deterministic for identical
requests and detaches caller-owned mutable JSON. Its digest uses the existing
plan-authoring canonicalization helper, not RFC 8785 or an origin signature.

## Reproducible synthetic native journey

The integration harness builds its test workspace from the existing
`examples/plan-worksheet` source graph, declared inputs and capability bundle.
It uses that diamond again as a reusable module to replace `left`, producing
seven items. The historical timestamp applies only to that synthetic catalog.

```sh
moon test splice_graph_test.mbt --target native
moon build cmd/main --target native
moon run scripts/verify_graph_splice.mbtx --target native -- /absolute/trusted/moonflow /absolute/source /absolute/new-test-workspace
```

Use your normal external build target, private environment and native build
lock when required by your workspace. The harness refuses an existing workspace
and records every CLI call and output. It verifies repeatable preview/export,
no preview state writes, draft reopen, exact preparation, durable import/status
reopen, zero attempts and approvals, missing-target refusal, lexical/symlink
containment and missing-input rejection at preparation. Library tests cover
multiple boundaries, disconnected modules, cycles, collisions, payload fidelity,
caller immutability and the 256-item boundary.

This is native library/CLI qualification using synthetic catalog evidence.
No browser, installed application, live adapter/provider, physical hardware,
customer acceptance, migration reuse or release qualification is established.
