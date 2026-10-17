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
rendering after a failed native export. In the default read-only mode the renderer never invokes the native CLI,
opens referenced product inputs or examines a workspace run store. The optional
source-backed authoring mode below invokes only native graph-map.

To try the included synthetic report without native tooling:

```sh
python3 scripts/graph_explorer.py examples/graph-explorer/graph-map.json /tmp/publication-explorer.html
```

For read-only export, Python 3.9+ is sufficient. There are no Python or JavaScript package installs.
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
source graph and selected target IDs. The read-only page creates no draft.
Dependency editing of the full graph is available in the optional mode below.

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

## Edit prerequisites from a verified full source graph

Use the same explorer in explicit authoring mode. The first positional input is
now the original complete work-model graph, not a report supplied by a caller:

```sh
python3 -B scripts/graph_explorer.py /absolute/workspace/source-graph.json /new/dependency-editor.html --author --cli /trusted/pinned/moonflow
```

Both flags are required together. Authoring requires Python 3.11+ for the
existing pin verifier (tested here with Python 3.12 and Node 24). Authoring verifies the executable SHA-256 and
all 1089 native source/configuration inputs with the existing
`verify_shared_table_native.py` / `shared_table_native_inputs.json` pin, then
invokes that executable with `graph-map SOURCE_PARENT SOURCE_FILENAME --json`.
It compares exact source bytes before and after graph-map and again immediately
before HTML output; source drift, native failure or report/source disagreement
blocks output. It does not accept an independently supplied report as provenance
or duplicate the native source-identity algorithm. The retained executable pin
is the accepted R760 release CLI, `e444ca1e59bbbfd0da0025438d8f461f5d671b82ef9ae438b80713fb98789a7c`.
A different engine/source version requires separately qualified pin maintenance,
not an override flag. This flow builds nothing and installs no dependencies.

Choose a work item using the existing selector or card, then choose another item
as a prerequisite and use **Add prerequisite** or **Remove prerequisite**.
Changes are pending until **Apply prerequisites** checks the complete candidate
DAG. Self-links, duplicate links, unknown items and dependency cycles are refused.
A rejected cycle remains pending so you can remove a link or cancel it. Changing
the selected work item cancels its pending edits and reports that cancellation.
**Cancel pending changes** retains all earlier applied edits.

After applying, cards, direct links, dependency depths, scopes and closure views
update immediately. The change review lists added/removed direct links and every
changed prerequisite closure against the original source, including downstream
effects. Filters do not trim this review or the downloaded graph. **Reset view**
only clears filters and selection. **Undo last edit** reverses up to the last 20
applied operations. **Reset all edits** discards pending changes and restores the
original graph; a reset of applied edits is itself undoable. No storage is used.
Reopening the page starts from its original source snapshot.

To retain work across sessions, download the form and use
[`--resume saved-form.json`](RESUME_PLAN_EDITOR.md) when generating a fresh editor
from the same original source. Its saved dependencies, inputs, timeout and
criteria return as applied changes.

**Download dependency plan form** becomes available only after applied changes
and with no pending edits. It downloads ordinary
`moonflow.declared-plan-form-input.v1` JSON. Every original work item appears once
in source order. Dependencies, input artifacts, acceptance criteria and timeout
can be explicitly edited; membership, IDs, operation, owner, schemas, authority
and claim remain the original declared values. The entire original graph JSON is included verbatim as `source_graph`,
including unknown annotations and numbers outside JavaScript's exact integer
range. This is not a reduced topology graph or a new graph identity. The source
file itself remains unchanged. Authoring source and downloaded form are each
bounded to 4 MiB; the native report remains bounded to 2 MiB / 256 nodes.

Move the form into the source graph's workspace, review it, then use the existing
native consumer. Paths remain relative to that workspace:

```sh
moonflow plan from-form /absolute/workspace moonflow-dependency-plan.json dependency-study RECORDED_AT
moonflow plan inspect /absolute/workspace dependency-study
moonflow plan prepare /absolute/workspace dependency-study capability-catalog.json EVALUATED_AT
```

Use current health evidence and actual timestamps for real work. Preparation
performs native capability and input checks and emits a separate child graph and
proposal. Download, draft creation and preparation neither dispatch nor approve
work. Source freshness is established only at HTML export; regenerate the page
when its source changes, and inspect the exact form before preparing it. Work in
a trusted local directory without concurrent source/executable replacement.
Sharing the HTML or form discloses the full source declarations and annotations,
including fields that are not displayed. It does not include artifact contents.

This is distinct from three-way worksheet merging and repeated CSV workflows:
it edits dependency links interactively on an existing full graph. Direct tested
PRD coverage is MOONFLOW-B02. MF-W01/W04/W05 and B09 are broader design grounding;
accepted history/checkpoint reuse is not qualified by these authoring checks.

```sh
python3 -B scripts/test_dependency_editor.py
python3 -B scripts/verify_dependency_editor.py --cli /trusted/pinned/moonflow --workspace-parent /existing/test-output
```

The verifier emits a page from the actual pinned native graph-map. Node executes
its real handlers under a small DOM adapter, captures its real Blob download,
and passes those exact form bytes through native from-form, inspect and prepare.
It tests a diamond, multiple edits, failed cycles/self/unknown links, duplicate
clicks, cancellation, navigation, undo/reset, source/frozen declaration
preservation, idempotent native retries and refusal of tampered dependencies,
unknown operations and expired synthetic catalog health. Logs are retained.
No real browser layout, file-dialog/OS download, accessibility tooling, live
provider, dispatch, accepted-checkpoint reuse, restart recovery or full-product
qualification is claimed. MoonBit sources and generated interfaces are unchanged;
Moon build/test/info/fmt are intentionally not run for this Python/JS-only change.

### Acceptance criteria editing

Select an item and edit the JSON array in **Acceptance criteria**. This keeps
multiple criteria separate and supports exact text, quotes, Unicode and escaped
newlines inside one criterion. Criteria must be distinct, nonblank strings of at
most 16384 Unicode scalar characters each, matching saved-form validation.
**Preview acceptance criteria** shows the exact pending values; **Apply pending
changes** retains them together with any staged dependencies, input paths or
timeout. Cancel, selection changes, Undo and Reset follow the same existing
editor semantics. Download preserves the original source graph verbatim and
includes the applied criteria in the v1 or v2 edits array. Reopen with
`--resume` to continue. The native planner imports and validates this declaration;
editing a criterion does not satisfy it or approve a result.

### Add and remove declared steps

Select an existing item, enter a new work item ID, and choose **Preview duplicate
declared operation**. Review the source template and new ID, then Apply. The new
step becomes selected and can have its inputs, prerequisites, criteria and timeout
edited. Its operation, owner, schemas, requested authority and claim remain those
of the original source template. Duplicating a copy still names its original
source template; native preparation assigns a fresh declaration identity.

**Preview removal of this step** refuses removal while other items depend on it.
Select each listed dependent and explicitly remove or replace its prerequisite,
then return and preview removal again. Removal never cascades or silently rewires
the graph. Keep at least one item, and no more than 256. New IDs use 1–128 ASCII
letters, digits, dots, hyphens or underscores; `.` and any `..` are refused.
Source IDs cannot be reused, even after removing that source item.

Step additions and removals use the same preview/cancel/apply, navigation-discard,
Undo and undoable Reset controls. Download uses
`moonflow.declared-plan-form-input.v2` with an explicit `added_templates` mapping
and the complete remaining child item set. Removal-only forms have an empty
mapping. Ordinary field edits retain v1 output. `--resume` accepts both forms,
validates the exact source and full edited topology, and restores added and removed
items before the first interaction. Reset restores the complete original source;
Undo reverses changes made in this session. Closing before download loses edits.

Focused regression coverage executes the actual emitted handlers via
`test_resume_editor.mjs steps` and `steps-resume`, including Blob download bytes.
`steps-native` checks retained actual native import, fresh-process inspect and
prepared-child outputs against that form. These tests do not qualify browser
layout, browser storage, native full-suite release gates or actual execution.
