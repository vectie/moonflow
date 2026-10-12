# Inspect a proposed workflow revision before importing it

Compare two declared graph files while they are still editable. See exactly
which declarations changed and which downstream work deserves another look,
without first importing either graph as a run:

```sh
moonflow compare-graphs WORKSPACE before.json after.json --text
moonflow compare-graphs WORKSPACE before.json after.json --json
```

Both commands read contained workspace-relative files and write only stdout.
No input artifact needs to exist, and no `.moonsuite` store, draft, event,
approval, dispatch, accepted review or checkpoint is created. Keep the JSON
receipt or readable text beside the proposed edit. Check the process exit code
before using redirected output: inherited CLI errors are printed to stdout.

The [example](../examples/graph-comparison/README.md) changes one model input and
its timeout; the report identifies the unchanged downstream `publish` item as
potentially affected, while `capture` and `independent` remain outside the change.
For recorded execution/results instead, use [compare-runs](RUN_COMPARISON.md).

## Matching and field differences

The first file is before, the second is after. This is the user's chosen
comparison; the command does not infer ancestry, chronology or readiness. Both
complete graphs must pass existing graph validation, have the same `book_id`,
and contain unique nonblank `declaration_id` values. Each side accepts 1–256
items and whole-number timeouts in 1–86,400,000 ms. Invalid cycles, missing
prerequisites, ambiguous declarations or malformed later items fail the whole
comparison. No catalog health or capability-conformance check is implied.

Items match by exact `declaration_id`, consistent with revision lineage.
Renaming `work_item_id` is a change in the matched row. Reusing a work name with
a new declaration is a removal plus an addition. Rows follow before-file item
order, then after-only declarations in after-file order. The report contains
full detached `before` and `after` item snapshots (JSON null for an absent side),
a status (`added`, `removed`, `changed`, `unchanged`) and ordered field changes.

Each top-level item field is compared, including product, operation, schemas,
authority, input paths, criteria, timeout, dependencies and unknown metadata.
Nested values remain complete JSON values. Object key order is ignored; arrays
retain order, duplicates, JSON types and literal string content. Field names
are sorted lexically by UTF-16 code units. Absent and explicit null differ,
using separate `before_present`/`after_present` flags. No domain equivalence,
default-value normalization or metadata interpretation is inferred. Extension
metadata changes therefore conservatively mark the item changed too.

Graph-level fields other than `items` are compared separately. Changing only
`graph_id`, revision, time or graph metadata does not mark every item changed.
`declaration_order_changed` compares the ordered declaration-ID lists, including
additions/removals. Reordering otherwise equal items is visible there but does
not itself seed downstream impact. Equality of recorded input paths says
nothing about the current bytes at those paths.

## Potential impact in both versions

Changed and removed declarations seed the before graph; changed and added
ones seed the after graph. The existing declared-impact traversal returns the
changed work IDs, reachable downstream IDs with shortest dependency distances,
and unaffected IDs, each in that side's source order. New or removed edges can
therefore change the affected set. Changed nodes are listed as seeds, not again
as downstream entries. Graph-level-only changes do not seed either graph.

These are structural dependency effects, not runtime state, a scheduling order,
checkpoint invalidation, a retry instruction or an authority decision. Review
changed input contents and operation contracts through the normal preparation,
conformance and execution workflows before any dispatch. This report cannot
prove that a downstream result is stale or reusable.

## Identity, bounds and host API

The contract is `moonflow.declared-graph-comparison.v1`. Both graph digests use
Flow's existing canonical JSON helper, which recursively sorts object keys by
MoonBit's shortlex String ordering and preserves array order. This is Flow
identity, not an RFC 8785 claim; JSON number serialization follows the existing
helper. The original graph's declared `source_digest` remains available among
the compared graph fields and is never substituted for the calculated digest.

The CLI additionally records both relative file references, exact read byte
counts and SHA-256 digests in `input_files`, including whitespace and encoding
bytes. Text includes the same records. File reads are separate observations,
not an atomic filesystem snapshot. Each file is limited to 2,097,152 bytes,
checked after a full read. Parsed graph text is limited to 1,048,576 UTF-16 code
units and nesting depth 64. Serialization may normalize input JSON formatting;
raw-file SHA-256 distinguishes those exact source bytes.

Library calls:

- `compare_declared_graphs_v1(before_graph, after_graph)` returns
  `DeclaredGraphComparisonV1` with detached values and impact reports.
- `declared_graph_comparison_text_v1(report)` renders quoted/escaped values,
  including absence markers and complete additions/removals.

Library reports do not add file records because the library never reads files.
The caller owns file containment and input acquisition. There is no new
provider, dependency, approval workflow, file-content verification or runtime
qualification. Cumulative qualification remains R50; this is focused authoring
and exploration acceptance.
