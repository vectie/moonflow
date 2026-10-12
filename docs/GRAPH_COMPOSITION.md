# Compose reusable declared graphs

Combine independently authored work graphs into one new plan. Each source keeps
its operations, schemas, requested authority, claims, input paths, acceptance
criteria and timeouts. Explicit cross-source links declare ordering; Flow does
not infer data flow, approvals or missing work.

```sh
moonflow graph-compose /absolute/workspace compose.json --json > composition.json
moonflow graph-compose /absolute/workspace compose.json --graph > combined.json
moonflow graph-map /absolute/workspace combined.json --dot > combined.dot
moonflow plan start /absolute/workspace combined.json combined-edit existing-graph 2026-10-09T00:00:00Z
moonflow plan inspect /absolute/workspace combined-edit
```

Save `combined.json` inside the selected workspace for the later commands. Use
new output paths, never shell-redirect over an input. Check command exit status:
the existing CLI prints error diagnostics to stdout, which are not valid JSON.
Use an actual timestamp for a real preparation with current catalog health.

`compose.json` is a workspace-relative file:

```json
{
  "contract_id": "moonflow.graph-composition-manifest.v1",
  "graph_id": "release-plan",
  "book_id": "release-book",
  "recorded_at": "2026-10-09T00:00:00Z",
  "sources": [
    {"alias": "build", "graph_ref": "graphs/build.json"},
    {"alias": "report", "graph_ref": "graphs/report.json"}
  ],
  "links": [
    {"prerequisite": "build.finish", "dependent": "report.start"}
  ]
}
```

IDs become `alias.original-id`, including every internal dependency reference.
Order follows the manifest then each source's item order. Distinct aliases can
still generate the same ID when names contain dots; such collisions are refused.
Aliases, destination graph/book IDs and composed IDs contain at most 128 ASCII
letters, digits, dots, underscores or hyphens, excluding `.` and `..` anywhere.
Destination graph ID must differ from every source ID. A source graph may be
used twice under distinct aliases to explicitly declare two copies of work.

`links` must be present; `[]` leaves sources disconnected. Each link must name
two existing composed IDs from different sources. Duplicate links, unknown
endpoints and a combined cycle fail before any output. Internal dependencies
are copied in original order, including repeated references, while explicit
links append in request order. Item extensions are retained without interpreting
or rewriting opaque embedded IDs. This is not a universal adapter-payload
renamer: review product-specific opaque fields before preparing.

Input paths are unchanged and relative to the same selected workspace, not the
source JSON's directory. No files are copied, paths rebound, output references
inferred or input artifact existence checked by composition. Use the existing
plan editor to select different inputs and criteria. Preparation still checks
files, exact catalog contracts and current health; import and dispatch remain
separate authorized operations. A dependency link only orders work; it does
not feed one item's outputs into another's inputs.

## Identity and provenance

The JSON report includes source graph/book/revision IDs, source graph digests,
old-to-new item/declaration mappings, explicit links and the complete new graph.
All declarations get fresh IDs bound to the entire expanded composition request.
Changing any source, link, source order, destination identity or timestamp changes
that binding. No attempt, result, approval or accepted checkpoint is copied.
The new graph has explicit destination book/graph IDs, revision `composition-v1`,
and the composition digest as its source digest. Source top-level extensions are
not merged. Retain sources and report together for provenance.

The digest uses the existing plan-authoring canonicalization helper, not a
raw-file hash or an RFC 8785 claim. It is reproducible identity, not proof of
origin, freshness, authority or current adapter availability. Repeat identical
inputs produce identical output. Composition writes no workspace state.

Pure API: `compose_declared_graph_v1(request : Json) -> Json raise`. Its contract
is `moonflow.graph-composition-input.v1`; each `sources` entry has `alias` and an
embedded `graph` instead of `graph_ref`. Results and source mutable JSON trees
are detached. The CLI resolves contained existing source references first.

Bounds: 2–16 complete source graphs, 256 total items, 256 explicit links; CLI
manifest and source bytes together at most 2 MiB. Each file is read fully before
the byte limit check. Pure API has graph/link bounds but no serialized byte cap.
Existing declared-plan validation applies to each source and the combined graph.
No graphical UI, external adapter execution, company-task authorization,
checkpoint reuse or all-product integration is established by this feature.
