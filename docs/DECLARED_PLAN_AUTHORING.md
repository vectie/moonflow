# Declared plan authoring

MoonFlow now prepares a new declared graph from an existing graph or an
owning product's exact graph preset. This is explicit editing of declared
work, not automatic goal creation, approval, dispatch, or execution.

## Desk form and portable handoff

The Flow page in the matching MoonDesk source includes **Author a new declared
plan** beneath the composition canvas when the selected Book has a graph.
The local draft starts with all source items, independent of the canvas selection.
Use **Duplicate declared operation** to add a copy with a safe new item ID, or
**Remove this step** to omit a row from the child. Removal does not cascade:
repair dependent IDs explicitly before preparation. At least one item is required.
Operation, owner, schemas, requested authority and claim are shown/read-only.
Edit input artifact paths, dependency item IDs, acceptance criteria and timeout.
Lists use one entry per line. Save local plan draft accepts incomplete fields;
Reopen saved draft restores the exact-source draft in that browser. Concurrent
tab saves use an expected saved body and refuse to overwrite a newer save.
The browser storage limit is 655,360 characters for each key/body. Storage
failure leaves the visible draft intact and displays a warning.

The form boundary accepts existing `moonflow.declared-plan-form-input.v1` forms
unchanged and the explicit `moonflow.declared-plan-form-input.v2` extension.
V2 requires `added_templates`, an object mapping each added item ID to its
original source item ID. The edited list is the complete child item set;
omitted source items are removals. Templates cannot name another copy, invent
an operation, overwrite a source ID or bind an absent edited row. An empty
mapping is required for removal-only v2 forms. V1 still requires all original
items exactly once. Earlier saved v1 drafts remain readable.

Artifact references
must be relative to the workspace passed to the native CLI. For a source graph
whose paths are graph-relative, use its containing directory as workspace or
explicitly change the form's paths for the intended workspace.

The Desk execution-sandbox client remains deny-only. The normal Desk form uses
the bounded fixed native Flow planning bridge: **Prepare**, inspect the explicit
added/removed rows and field changes, then explicitly **Import this child plan**
or **Import this reviewed revision**. These actions never dispatch work.
Saved request identity supports explicit prepared-result reload after a lost
response. Source/catalog drift blocks import while retaining the packet.

Portable native forms can also use the existing CLI:

```
moonflow plan from-form WORKSPACE moonflow-plan-form.json my-edit 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE my-edit
moonflow plan export WORKSPACE my-edit
moonflow plan prepare WORKSPACE my-edit capability-catalog.json 2026-07-31T00:00:00Z
```

The timestamp above is an example: use the actual evaluation time with current
catalog health evidence. `from-form` validates the entire typed edit set, so a
batch dependency change is checked as one graph rather than partial steps.
Invalid dependencies/cycles, empty criteria/bindings, duplicate entries, unsafe
artifact references and timeouts outside 1..86,400,000 ms are rejected.
V2 additionally rejects unsafe new IDs, duplicate IDs, unknown templates and more than
256 items. It cannot silently remove dependents or rewire their dependencies.
New IDs use at most 128 ASCII letters, digits, hyphens, underscores or dots;
they cannot be `.` or contain `..`, matching the native CLI's conservative
identifier rule. Existing source-owned labels and v1 behavior are retained.
Fresh exact operation/schema/owner/authority/claim validation occurs on every
prepare, including repeat prepares. The CLI checks all input files exist and
remain inside its workspace before creating prepared output.

## Native-only drafting

`plan start WORKSPACE SOURCE_GRAPH_REF DRAFT_ID existing-graph RECORDED_AT`
starts from an existing graph. Use `product-preset` for a product-owned graph
preset; Flow supplies no domain-specific robot/mission schema.

`plan edit WORKSPACE DRAFT_ID EDIT_REF` reads a JSON object containing
`expected_draft` (the exact output of `plan export`) and `item_edit` with
`work_item_id`, `input_artifacts`, `depends_on`, `acceptance_criteria`, and
`timeout_ms`. Stale saves fail; repeating the same save is idempotent.
Drafts are atomically written under `.moonsuite/products/moonflow/plan-drafts`.

## Preparation, import and revision

Preparation returns workspace-relative `graph_ref` and `proposal_ref`, a
content-derived child graph/revision identity, and the existing capability
report. Files live under `.moonsuite/products/moonflow/prepared-plans`. Exact
retries retain identical graph/proposal bytes; a different artifact binding,
criterion, dependency or timeout changes child identity. Existing files with
different content are refused. Source graph and parent run bytes are untouched.

If the selected graph already has a run in this workspace, preparation also
returns a read-only migration preview from the existing `revise_run` API.
An exact accepted checkpoint remains eligible; changed operation, schemas,
claim, artifact paths, timeout, criteria, authority, owner, or dependency
declarations invalidate reuse. A changed/unreusable upstream checkpoint also
blocks downstream reuse. Preparation itself creates no run or attempt.
Each addition receives a deterministic fresh declaration identity bound to the
exact source graph digest, added item ID and original template ID. It is checked
against source declaration identities. Migration therefore treats a duplicate as
new work even when operation and inputs equal an accepted template. A subsequent
source revision changes this lineage binding. No source acceptance is copied.

Use the returned graph with existing `import-conformant-graph` for a new run,
or use the returned graph/proposal with `revise-run` for a child run. These
remain explicit separate operations; preparation does not authorize them.
The current `prepare-form` path captures declared input bytes and explicit Mold
spatial reference evidence, resolving copied operations through their original
template contract. Opaque contracts retain original references and revalidate
their selected bytes at apply; unknown nested dependencies and mutable runtime
state are not frozen. Product-owned payload validation and execution remain with
the product adapter and existing execution path.

## Qualification

Source checks and deterministic native/JS fixtures cover the form reducer,
rendered controls, local-storage reopen/conflicts, typed export, actual native
CLI preparation, exact graph import, and child revision without dispatch.
No live browser, installed desktop app, provider, physical hardware or adapter
execution is claimed. Browser download and local storage behavior are covered
with source/unit fixtures, not live browser qualification.
