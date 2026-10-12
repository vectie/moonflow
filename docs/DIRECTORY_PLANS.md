# Turn a request folder into an editable batch

Use an existing folder of product-owned request files directly. Select a source
operation, literal file suffixes and whether to include subfolders. MoonFlow
lists the selected files in UTF-16 lexical order and creates one independent declared
work item per file. You do not need to hand-write a CSV or JSON file inventory.

```sh
moonflow plan preview-directory WORKSPACE source-graph.json selection.json folder-study 2026-07-31T00:00:00Z
moonflow plan from-directory WORKSPACE source-graph.json selection.json folder-study 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE folder-study
moonflow plan prepare WORKSPACE folder-study catalog.json 2026-07-31T00:00:00Z
```

Use actual evaluation time and current catalog health for real work. The
[synthetic example](../examples/directory-plan/README.md) uses the July-dated
fixtures above; it does not qualify a live adapter.

## Explicit file selection

`selection.json` is a workspace-relative file containing all six fields:

```json
{
  "contract_id": "moonflow.directory-plan-selection.v1",
  "directory_ref": "requests",
  "template_work_item_id": "make-model",
  "suffixes": [".json", ".request"],
  "recursive": true,
  "id_prefix": "model"
}
```

- `directory_ref` names an existing canonical, non-hidden directory inside the
  workspace. It cannot be the workspace root, an absolute path, a symlink, or
  contain empty, dot, parent, backslash or hidden components.
- `template_work_item_id` names one original item in the source graph. Its exact
  operation, product, schemas, requested authority, claim, criteria and timeout
  are copied. The batch replaces the source item set.
- `suffixes` contains 1..16 distinct, case-sensitive literal extensions such as
  `.json` or `.request.json`. No globs, regular expressions or content sniffing.
  Each suffix starts with a dot, has 2..64 ASCII letters/digits/dots/hyphens/
  underscores, and overlapping suffixes select a file only once.
- `recursive: false` selects direct files only; `true` includes visible nested
  directories. Hidden files/directories are always skipped. Directory names
  ending in a selected suffix are still directories, never inputs.
- `id_prefix` is a safe ASCII identifier of 1..63 characters. Each generated ID
  is `id_prefix-` followed by the full SHA-256 hex digest of the UTF-8
  workspace-relative artifact path. Same-name files in different folders remain
  distinct. Adding an earlier-sorted file does not renumber existing items.

All source/selection references and selected files must be regular, confined
files. Symlinked directories are never followed. A visible symlink or special
file whose name matches a suffix fails the whole import; nonmatching symlinks
are skipped and listed in `skipped_symlink_refs`. The CLI examines at most 8192
entries, at most 16 nested directory levels, and requires 1..256 matching files.
If a limit is exceeded, choose a narrower folder or more selective suffixes.
The entry limit includes hidden/nonmatching entries in visited directories.
No payload file contents are read or interpreted by directory intake.

## Preview, save, edit and prepare

Preview prints the exact sorted `entries`, selection, path-inventory digest,
scan count and complete editable form. It creates no workspace state. Save
repeats that scan and full validation before saving one ordinary v2 draft.
Repeating identical source/paths, draft ID and timestamp is idempotent. If the
folder gains or loses matching paths, the old draft is refused rather than
rewritten; choose a new draft ID or use the existing plan editor.

A saved draft stores explicit paths, not a live folder query. Reopening it does
not rescan or silently add new files. The inventory digest covers the sorted
path array using Flow's existing canonical JSON digest, not file contents.
Changing bytes at the same path does not change this inventory or the saved
draft. Ordinary preparation rechecks inputs; see the existing [captured-input preparation workflow](DESK_PLAN_PREPARATION.md)
when you need retained input bytes. Intake does not freeze
bytes or claim a concurrent-filesystem snapshot. Avoid changing the folder
while scanning. Re-preview before saving if another process is editing it.

Each item starts with one primary input, no dependencies, inherited criteria
and timeout, and fresh declaration lineage. Original ancillary inputs and
source dependency edges are not copied. Use `plan export`/`plan edit` to add
explicit ancillary references, dependencies or review criteria after saving.
Nothing in a filename is treated as an operation, permission or dependency.

`plan prepare` checks the current exact catalog and returns a child graph and
proposal. The returned graph can be imported using the existing conformant
import command. File selection and preparation never dispatch adapters, create
approvals, infer payload validity, accept results or report customer success.
Check every CLI exit code before parsing or redirecting output; the inherited
CLI writes error diagnostics to stdout.

## Library hosts

`decode_directory_plan_selection_v1` validates the selection document.
`declared_plan_from_directory_v1` accepts the source, selection, selected path
array, draft ID and timestamp. It validates membership, suffixes/depth,
canonical paths, duplicates, bounds and generated identity collisions, sorts
the supplied copy, then returns a `DirectoryPlanImportV1`. Host applications
must perform their own regular-file discovery and filesystem checks. The pure
API neither reads files nor verifies that an inventory is exhaustive.
