# Browse a declared graph offline

Turn an existing MoonFlow graph-map JSON export into one portable HTML page.
Search work IDs, product names and operation names, narrow to a product, and
select a work item to trace all its prerequisites or downstream consumers.
The page carries its own styles, data and script; it needs no web server,
Graphviz installation, external assets, network access or product adapter.

This extends the existing [graph-map export](GRAPH_MAP.md). It does not replace
work-model import, the native graph parser, or MoonDesk's live run surface.
MoonFlow's [product contract](PRODUCT_CONTRACT.md) calls for operator inspection;
this viewer makes its existing declaration snapshot readable and explorable in
an ordinary browser before choosing a subgraph or editing a plan.

## Export and open

From the MoonFlow repository, using an already installed trusted MoonFlow CLI:

```sh
moonflow graph-map /absolute/workspace graphs/selected.json --json > /tmp/selected-map.json && \
  python3 scripts/graph_explorer.py /tmp/selected-map.json /tmp/selected-explorer.html
```

Open `/tmp/selected-explorer.html` in your browser. The renderer accepts the
`moonflow.declared-graph-map.v1` report, not the original work-model graph, DOT,
status projection, draft or a native diagnostic. Check the native command's
exit status: its diagnostics may be printed to stdout. The `&&` above prevents
rendering after a failed native export. The renderer itself never invokes the
native CLI, opens referenced product inputs or examines a workspace run store.

To try the included synthetic report without native tooling:

```sh
python3 scripts/graph_explorer.py examples/graph-explorer/graph-map.json /tmp/publication-explorer.html
```

Python 3.9+ is sufficient. There are no Python or JavaScript package installs.
Supply a new output filename in an existing folder. The CLI refuses every
existing output, including the source file, and returns status 2 on error.
On success it prints a JSON receipt containing graph ID, node count, exact
input-file and output-file SHA-256 and `dispatched:false`. Success does not
mean that a browser has opened or rendered the file. Identical report bytes
and renderer assets produce identical HTML bytes; no clock or local path is
embedded in the page. A write failure can leave a partial output file: inspect
it and choose a new output name rather than assuming a successful export.

## Explore the page

- Search is a literal, case-insensitive substring of each work ID, product ID
  or operation. Spaces remain part of the query. No regex or query language.
- Product filters match the full declared product identity. Search, product and
  dependency-scope filters intersect; the count shows how many items remain.
- Choose a work item from the selector or its **Explore this item** button.
  The details list direct prerequisites/consumers and each transitive closure
  separately. Each transitive list contains unique items in source order.
- **Selected + all prerequisites** includes the selected work and the complete
  prerequisite closure. **Selected + all downstream consumers** follows links
  in the opposite direction. These are read-only views, not saved subgraphs.
- Relationship buttons navigate to that item and clear search/product filters
  so the new selection is visible. Static relationship links do the same when
  JavaScript is active, then follow their local fragment. Your selected dependency
  scope is retained.
  A selection made in the dropdown does not clear filters; its details remain
  available even if its card is filtered out.
- Selecting **Choose an item** removes dependency scope. **Reset view** clears
  the entire selection and all filters. No selection is written to storage.
- Empty results say so. Every relationship in the detail panel comes from the
  full report, even if a product/search filter hides that work's card.

Cards are grouped by longest prerequisite-path depth, preserving source order
within each depth. An isolated node appears as both a root and a leaf. Text
links on static cards navigate to direct prerequisites and consumers. Without
JavaScript the complete graph and those links remain readable; search,
selection and transitive views are unavailable. Print styles include the
complete graph, regardless of the screen's filters.

For a dependency-complete editable plan, use the existing
[preview-subgraph/from-subgraph workflow](SUBGRAPH_PLANS.md) with the original
source graph and selected target IDs. This page intentionally creates no draft.

## Identities and limits

The input report is bounded to 2 MiB of UTF-8 JSON and 1..256 nodes. The renderer
checks unique IDs, declared prerequisite targets, acyclicity, unique exported
edges, longest-path layers, source-ordered roots/leaves and edge counts. Each
ID/product/operation is a nonblank Unicode string of at most 16,384 characters.
Duplicate JSON keys and invalid JSON numbers are rejected. Extra report/node
annotations are ignored rather than rendered. This is validation of the
exported topology, not validation of the omitted full work-model declaration.

**Source graph identity (reported)** is the existing native plan-identity
hash carried in the report. The renderer cannot authenticate that claim or
recompute it without the original graph. **Exact imported graph-map file
SHA-256** binds the raw file read for this export, including whitespace. These
are identities, not signatures, proof of execution, or acceptance evidence.
Changing whitespace alone changes the raw report digest and output page.

A depth is not an execution schedule. The export contains no attempts,
events, readiness, timings, authority grants, input contents, catalog health,
acceptance status or hidden dependencies. It cannot tell whether an operation
is presently executable. Exported labels remain text, not links to services,
HTML, commands or executable JavaScript. The page requests no network access
and stores no preferences. Sharing the file would disclose all included work
IDs, product/operation declarations and dependency relationships, regardless
of filters; exporting does not share it with anyone.

## Focused checks

```sh
python3 -B scripts/test_graph_explorer.py
node scripts/test_graph_explorer.mjs
```

The Python checks exercise the real renderer and subprocess CLI, schema shape
against the existing publication example, deterministic output receipts,
non-topological graphs, full 256-item chains, static links and literal labels.
The Node checks execute the script extracted from the actual emitted HTML under
a small DOM adapter, covering search/product intersections, closure selection,
relationship navigation, reset, empty results and Unicode text. These are not
real-browser, visual, file-picker, assistive-technology or native MoonFlow
qualification. This change runs no Moon command, modifies no MoonBit API or
dependency, and claims no live MoonDesk integration or full-product pass.
