# Desk preparation and explicit adoption

The native planning bridge adds two fixed operations. It does not invoke an
adapter, submit an attempt, grant authority, or enable a generic executor.

```
moonflow plan prepare-form <workspace> <form-ref> <catalog-ref> <draft-id> <recorded-at>
moonflow plan apply-prepared <workspace> <preparation-id> <catalog-ref> <evaluated-at>
```

All references are workspace-relative. Desk supplies its selected source file
as `source_ref` in the existing `moonflow.declared-plan-form-input.v1` object.
The source JSON must equal the form's source graph. Its exact bytes, form bytes,
catalog bytes, and selected input bytes are retained by Flow. The pre-existing
`plan from-form`, `plan prepare`, import and revision commands are unchanged.

## Inspect before applying

Preparation returns `moonflow.declared-plan-preparation-receipt.v1` with the
existing prepared graph/proposal and capability report, their references, and
`migration_preview` (null for an import, a receipt object for a child revision).
Migration decisions identify `child_work_item_id`, `source_work_item_id`,
`declaration_id`, `decision`, `reason`, and `evidence_refs`.

`input_captures` lists exact `original_ref`, retained `captured_ref`, SHA-256,
byte length, item, role and binding mode. The input capture digest participates
in this new path's child identity. New bytes cannot silently reuse a prepared
identity even when an opaque payload keeps its original reference.

For the supported Mold spatial request contract, the typed primary input and
explicit workspace-relative `reference_artifacts` evidence are rebound to
content-addressed captures. Original primary bytes and any derived, rebound
primary are both retained. Evidence bytes are retained without lossy decoding.
These references are evidence, not arbitrary recursively executable payloads.

Other contracts remain supported with their original artifact references and
exact top-level byte snapshots. Their receipt explicitly reports
`original-reference-revalidated`: original bytes must still equal the captured
bytes at apply. Unknown nested dependencies are not inferred or advertised as
frozen. Product/runtime state, model journals, providers and later execution
are outside this planning capture. A frozen declaration is not a promise of
reproducible product execution.

## Explicit apply, retry and reopen

Apply revalidates source, form, catalog, current health, retained input bytes,
original input bytes, prepared graph/proposal bytes, and the exact parent event
history. It recomputes the saved migration preview before any run persistence.
The unchanged revision engine still requires accepted checkpoints and exact
owner, authority, schema, criteria, input bindings and dependency eligibility.
Opaque original bindings additionally compare captured bytes with the accepted
input digest; mismatches invalidate rather than inherit an accepted checkpoint.

Flow writes the supported conformant import or child-revision event set and
projection, with zero submitted attempts. The result is a stable
`moonflow.declared-plan-apply-receipt.v1` containing `projection`, `migration`,
`preparation_id`, `applied_at`, and `dispatched:false`. Repeated calls return the
same retained result after fresh validation. They never reset an advanced run.

The planning writer lock is process-owned and released by the operating system
on exit. Retained files use atomic writes. An apply intent is saved before run
persistence; retry after a lost reply completes the same intent. Changed input,
source, catalog, parent history, or expired health blocks the old apply while
leaving the old packet available for inspection. Prepare a new request and
review its new graph and migration preview.

The new path rejects missing artifacts, traversal and symlinks. It bounds each
retained artifact to 16 MiB and each item's explicit input/reference list to 64.
It performs no recursive workspace copy, network access, provider execution,
credential lookup or physical work.
