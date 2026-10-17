# Continue editing a saved plan

The offline graph editor can reopen a saved v1 plan form instead of starting
again from the original graph. Dependencies, timeouts and input artifacts return
as applied edits, so you can close one session and continue the same plan later.
Saved acceptance criteria are also retained and shown read-only. Nothing is
imported, dispatched or approved by opening the editor.

This closes an authoring continuity gap in the operator/revision journeys
MF-W04 and MF-W05. It is not runtime restart recovery, checkpoint reuse or closure
of the full MOONFLOW-B09/B10 release requirements.

## Save, close, resume

First generate a source-backed editor and download its plan form after applying
your edits, using the existing [graph explorer](GRAPH_EXPLORER.md):

```sh
python3 -B scripts/graph_explorer.py WORKSPACE/source-graph.json initial.html \
  --author --cli /trusted/pinned/moonflow
```

Later, supply that same original full source graph, the saved form and a new HTML
filename. The form may be anywhere readable; its input artifact paths still
refer to the eventual native preparation workspace.

```sh
python3 -B scripts/graph_explorer.py WORKSPACE/source-graph.json resumed.html \
  --author --cli /trusted/pinned/moonflow --resume saved-form.json
```

Open `resumed.html`. Its banner shows the saved file's exact SHA-256. Cards,
dependency depth, prerequisite/consumer navigation and change review immediately
reflect the restored plan. The header identifies counts for the original source
snapshot. Every restored edit remains visible against that original baseline.
You can download the same edits immediately or continue with the ordinary
preview/apply controls.

- Pending edits are still separate. Cancel or switching items discards only
  pending edits; saved and previously applied changes remain.
- Undo initially has no history. It reverses actions in this session, returning
  to the restored plan when you undo a new edit.
- Reset all edits deliberately returns to the original source graph, including
  original criteria. This reset can itself be undone.
- Reset view clears selection and filters without changing the plan.
- Reopening the generated HTML restores its embedded saved snapshot. Later edits
  only persist when downloaded; generate another resumed page from that download.

Current acceptance criteria are displayed literally for the selected item. If a
saved form changed them, the change review shows before and after. This page does
not edit criteria, and it never silently substitutes the original criteria when
downloading a resumed plan.

Without JavaScript the cards show the original source graph only, with an explicit
notice that resumed edits require JavaScript. No browser storage or network is used.

## Binding and supported forms

Resume accepts `moonflow.declared-plan-form-input.v1` with `source_kind` equal to
`existing-graph`. It retains all source work items exactly once and normalizes
edits to original source order, just as the native v1 planner does. Expanded v2
plans, drafts, worksheets and company-task source kinds are refused.

The existing pinned native `graph-map` verifies the selected full source before
rendering. The saved form must embed that complete source, including unknown
annotations. Comparison ignores JSON whitespace and object-key order but retains
array order, scalar types and exact numeric token spelling. For example, `1`,
`1.0` and `"1"` differ. Large integers and close decimals cannot collide through
floating-point rounding. The original selected source text is preserved verbatim
in every new download.

Duplicate decoded JSON keys, unknown form/edit fields, missing or duplicate work
items, invalid string lists, unsafe input paths, noninteger/out-of-range timeouts,
self/unknown links and cycles refuse the entire render. Strings must be nonblank
Unicode scalar text of at most 16,384 characters. The source and saved form each
remain bounded to 4 MiB; the native graph report remains limited to 256 nodes.
The source and form are reread before output, and drift blocks creation. Existing
output files are never overwritten. Work in a trusted local directory without
concurrent adversarial replacement; these checks are not an atomic filesystem
transaction or a cryptographic signature.

If the source differs, choose the original graph used by the saved form. Do not
retarget a saved form by copying over its embedded source. Prepare changes to a
new source through the normal revision/worksheet-merge workflow instead.

## Continue through the native planner

Put the new download in the intended workspace, retain the original referenced
input files, and choose a new draft ID if an existing draft has different edits:

```sh
moonflow plan from-form WORKSPACE continued-form.json resumed-study RECORDED_AT
moonflow plan inspect WORKSPACE resumed-study
moonflow plan prepare WORKSPACE resumed-study catalog.json EVALUATED_AT
```

Native preparation still owns current catalog health, input existence, capability
and authority validation. Resume does not access input artifacts or a run store.
Reusing saved declarations grants no authority and makes no completion claim.
HTML and forms include the full original source, not just displayed fields; keep
them private unless sharing is separately authorized.

Try the [saved four-step study](../examples/resume-plan/README.md).

## Focused verification

```sh
moon run --target native scripts/verify_resume_editor.mbtx -- \
  /trusted/pinned/moonflow /absolute/source /new/test-workspace
```

The verifier runs the changed renderer and actual emitted JavaScript event
handlers with a DOM adapter, captures real Blob bytes, restores them twice,
checks unchanged original inputs and exercises native save/inspect/prepare with
idempotent retries. Existing dependency, timeout, input-editor and read-only
explorer tests run too. Source mismatch, malformed saved forms and native cycle/
expired-health cases remain refusals.

All 412 native product source/configuration inputs and the retained R700 CLI
SHA-256 are checked before reuse. No product-native rebuild or API change is
claimed; the standalone verifier is compiled separately. These are focused local
development checks, not a real-browser, visual, accessibility, external-adapter,
installed-lifecycle, production or full-release qualification.
