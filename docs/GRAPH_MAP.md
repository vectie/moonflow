# Explore declared dependencies

MoonFlow now exports an existing declared work graph as portable Graphviz DOT
or a versioned JSON topology report. This is a read-only view of the entire
graph, useful before selecting a subgraph or editing dependencies.

```sh
moonflow graph-map /absolute/workspace graphs/selected.json --dot > graph.dot
moonflow graph-map /absolute/workspace graphs/selected.json --json > graph-map.json
dot -Tsvg graph.dot -o graph.svg
```

`source-graph-ref` is a workspace-relative existing JSON file. The CLI checks
that the selected graph file is contained in the workspace, reads and validates
it completely, then prints the output. It writes no workspace state and does
not need referenced input artifact files, a catalog, a run, or an adapter.
Check the exit code before using redirected stdout: the inherited native error
handler prints diagnostics on stdout for failed commands. Such output is not a
valid report. Shell redirection may create a file even when the command fails.

For searchable, linked offline inspection without Graphviz, render the JSON
export with the [offline dependency explorer](GRAPH_EXPLORER.md). Its HTML
retains the full declared topology and offers selected prerequisite/consumer
closures; it does not create a plan or inspect runtime state.

## Read the map

- Each box contains work-item ID, product ID and exact declared operation.
- Arrows point from prerequisite to consumer, including shortcut edges.
- Same-rank boxes have the same longest prerequisite-path length from a root.
- Disconnected items remain visible. An isolated item is both root and leaf.
- Node order, layer membership order and root/leaf order follow the source.
- Duplicate prerequisite references collapse to one structural edge, preserving
  their first occurrence. The source itself is never rewritten.
- JSON contract `moonflow.declared-graph-map.v1` includes graph ID, source graph
  digest, nodes with unique ordered prerequisites and zero-based layer, ordered
  layers, roots, leaves and unique edge count.
- The digest uses the existing plan-authoring identity helper, also used by
  `plan impact`. It is not the raw-file SHA-256 or an RFC 8785 canonical hash.
- DOT uses generated node IDs and escaped plain quoted labels. Quotes,
  backslashes, Unicode and line breaks in labels remain text. No HTML labels,
  external images, URLs, remote renderer or Graphviz installation is required
  to export DOT. Rendering requires an independently installed Graphviz.

Layers describe structural dependencies only. They do not mean simultaneous
execution, readiness, authority, duration, critical path, completion or internal
acceptance. The command does not read event history or claim that declared
operations exist in a current catalog. Graph validation uses the existing work
model parser; up to 256 items are supported. Empty graphs, cycles, missing
prerequisites and duplicate item identities fail without partial report output.

Pure library APIs: `declared_graph_map_v1(source_graph)` and
`declared_graph_dot_v1(source_graph)`. The report owns its mutable arrays;
subsequent changes to caller JSON cannot alter an earlier report.

## Included example

Open `outputs/graph-map.svg` for a rendered synthetic graph. Its source is
`inputs/graph.json`; matching actual CLI outputs are `outputs/graph-map.json`
and `outputs/graph-map.dot`. It deliberately uses reversed item order, a
shortcut prerequisite, a disconnected item and quoted/Unicode labels. Its
referenced input files do not exist, demonstrating offline topology inspection.
No operations were executed. Other input files are negative examples.

From this kit directory, with a built MoonFlow CLI, Moon and Node.js:

```sh
export MOONFLOW_CLI=/absolute/path/to/moonflow-cli
moon run verify_graph_map.mbtx --target js --target-dir /absolute/private/script-target
```

The verifier also needs Graphviz `dot` with `-Tjson` and `-Tsvg` support. It checks
all JSON declarations and layer membership, the existing plan-identity digest,
every edge parsed by Graphviz, actually rendered escaped labels, negative
selections, unchanged input bytes and exact retained output reproduction.
The retained SVG was rendered using Graphviz 2.42.4. Layout and SVG bytes can
vary with Graphviz/font versions; use that version and matching fonts for the
exact SVG comparison. The topology and text checks are independent of layout.
Do not pass `--record` during ordinary verification; it regenerates this kit's
synthetic fixtures and expected outputs.

## Build from the exact source base and patch

Apply `round192.patch` to clean accepted MoonFlow commit
`0f6f487063296de180ce4ba2daba29c785d89e9a` using `git apply --check` then
`git apply`. Use its frozen dependency graph and the pinned Moon toolchain.
No dependencies or manifests were changed. With an external build directory:

```sh
moon test graph_map_test.mbt change_impact_test.mbt subgraph_plan_test.mbt --frozen --strip --target native -j 1 --target-dir /absolute/private/build-target
moon build cmd/main --frozen --strip --target native -j 1 --target-dir /absolute/private/build-target
```

Executable: `/absolute/private/build-target/native/debug/build/cmd/main/main.exe`.
In the recovery workspace, use the recovery toolchain, private HOME/XDG paths,
`MOON_DEP_CACHE=off`, `MOON_BUILD_CACHE=off`, and hold its shared native build
lock for native test/build commands. No binary or build cache is bundled.
