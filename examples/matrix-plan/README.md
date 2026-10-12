# Eight explicit model variants

This synthetic study expands label (café/wide), units (mm/cm), and frame (z/y)
into eight JSON requests. It clones the declared MoonMold operation without
executing it. Make a writable copy of this directory for save/edit/prepare.

```sh
moonflow plan preview-matrix /absolute/copy source-graph.json matrix.json request-template.json study 2026-07-31T00:00:00Z
moonflow plan from-matrix /absolute/copy source-graph.json matrix.json request-template.json study 2026-07-31T00:00:00Z
moonflow plan inspect /absolute/copy study
moonflow compile-capability-catalog /absolute/copy/capability-source-bundle.json > /absolute/copy/catalog.json
moonflow plan prepare /absolute/copy study catalog.json 2026-07-31T00:00:00Z
```

The date is fixture time, not current production health. Check every exit code.
The source operation's old `requests/compact.json` need not exist: every matrix
variant gets a materialized primary request. Review request_id/idempotency_key,
model ID, label, units and coordinate frame in the preview before saving.
`plan export` returns the draft for the existing edit command's expected_draft;
`plan inspect` returns its editable form.

To run the self-contained native CLI verifier in a fresh retained workspace:

```sh
python3 scripts/verify_matrix_plan.py --cli /absolute/moonflow-cli --workspace-parent /absolute/evidence
```

See [MATRIX_PLANS](../../docs/MATRIX_PLANS.md) for the format, limits and identity
semantics. Validation covers declared import/edit/prepare only, with no dispatch.
