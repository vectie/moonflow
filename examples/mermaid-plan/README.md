# Turn a diagram into an editable plan

This synthetic design study imports three declared nodes. `compact` and `wide`
are independent prerequisites of `compare`. Every node is explicitly bound to
the supplied original `make-model` operation. The labels neither select an
operation nor infer payloads or output wiring.

Use this directory as `WORKSPACE`, preferably a copy for your own experiment:

```text
moonflow plan preview-mermaid WORKSPACE source-graph.json bindings.json design.mmd study 2026-07-31T00:00:00Z
moonflow plan from-mermaid WORKSPACE source-graph.json bindings.json design.mmd study 2026-07-31T00:00:00Z
moonflow plan inspect WORKSPACE study
moonflow plan export WORKSPACE study
moonflow compile-capability-catalog WORKSPACE/capability-source-bundle.json > WORKSPACE/catalog.json
moonflow plan prepare WORKSPACE study catalog.json 2026-07-31T00:00:00Z
```

The example date is intentional: it lies within the synthetic bundle's health
period. For your own data, use actual current health and evaluation time.
Preparation checks file existence and catalog eligibility; it does not validate
these placeholder payloads as MoonMold requests or execute an adapter.

Inspect the preview's nodes, labels, edge direction and complete form. Save
retains the exact original three input texts and their digests in
`.moonsuite/products/moonflow/plan-drafts/study.mermaid-import.json` alongside
the normal draft. Repeat the exact save idempotently. Changed diagram bytes,
bindings, references, time or an edited draft require a new draft ID.

To revise a saved item, export the draft and use existing `plan edit` with an
`expected_draft` and complete `item_edit`; see [the guide](../../docs/MERMAID_PLANS.md).
The original import receipt stays unchanged when the draft is later edited.
No run, approval, attempt, provider request or customer acceptance is created.
