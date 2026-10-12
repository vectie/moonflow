# Synthetic request-folder batch

This fixture contains three product request files, including a nested file, plus
one source operation and its dated catalog bundle. Use the fixture directory as
WORKSPACE, or copy its source files into a new writable workspace. Do not run
these commands in an authoritative checkout.

With a built MoonFlow CLI:

```sh
moonflow plan preview-directory WORKSPACE source-graph.json selection.json folder-study 2026-07-31T00:00:00Z
moonflow plan from-directory WORKSPACE source-graph.json selection.json folder-study 2026-07-31T00:00:00Z
moonflow compile-capability-catalog WORKSPACE/capability-source-bundle.json > WORKSPACE/catalog.json
moonflow plan prepare WORKSPACE folder-study catalog.json 2026-07-31T00:00:00Z
```

Inspect the three path-to-ID entries in the preview. Change `recursive` to false
in a separate selection file to select only `compact.json` and `wide.json`.
The generated IDs are stable path hashes, so adding another request does not
rename existing work. Saved plans are snapshots of references, not folder
watchers. No adapter executes; the timestamp intentionally matches synthetic
fixture health rather than current production health.

Run `scripts/verify_directory_plan.py --cli /absolute/main.exe
--workspace-parent /absolute/external-verification` for an automated native CLI
journey. It keeps its generated workspace and logs, checks sorting, preview and
repeat-save behavior, edits a saved plan, prepares/imports with zero attempts,
and exercises file selection errors and traversal bounds.

See [the full directory intake guide](../../docs/DIRECTORY_PLANS.md).
