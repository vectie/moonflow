# Two records, two complete request workflows

This example generates eight request files and two independent diamond-shaped
workflows: `chair.root → chair.left/right → chair.join`, then the equivalent
`table.*` declarations. Each step has its own JSON request template and bindings.
Nested values retain their types, and the final step gets record-specific review
criteria. No input files need to be hand-authored for the eight expanded steps.

Copy this directory to a fresh local workspace. With a trusted native `moonflow`
binary available, set `WORKSPACE` to that copy's absolute path:

```sh
moonflow plan preview-workflow-payloads "$WORKSPACE" source-graph.json workflow.json records.json study 2026-07-31T00:00:00Z
moonflow plan from-workflow-payloads "$WORKSPACE" source-graph.json workflow.json records.json study 2026-07-31T00:00:00Z
moonflow plan inspect "$WORKSPACE" study
moonflow compile-capability-catalog "$WORKSPACE/capability-source-bundle.json" > "$WORKSPACE/catalog.json"
moonflow plan prepare "$WORKSPACE" study catalog.json 2026-07-31T00:00:00Z
```

Use a fresh `catalog.json` destination and check every exit status; error output
is not JSON. Preparation returns `graph_ref`. An explicit subsequent import is:

```sh
moonflow import-conformant-graph "$WORKSPACE" "$WORKSPACE/RETURNED_GRAPH_REF" "$WORKSPACE/catalog.json" 2026-07-31T00:00:00Z
```

Replace `RETURNED_GRAPH_REF` with the actual returned reference. Import creates
normal durable declared state, with only `chair.root` and `table.root` runnable
and no attempts or approvals. Stop there for this example.

The source operation and July-dated catalog come from the existing synthetic
plan-worksheet fixture. Requests intentionally contain `fixture_only: true` and
are not valid MoonMold execution requests. This example demonstrates authoring,
typed materialization and graph import only. It does not execute product effects
or qualify production health. For real work, use product-owned valid requests,
current catalog evidence and timestamps, and separately authorized execution.
Dependency edges do not supply output data to later requests.

For automated verification from the repository:

```sh
moon run scripts/verify_workflow_payload_plan.mbtx --target native --strip -j 1 -- /absolute/trusted/moonflow /absolute/source /absolute/new-verification-workspace
```

Apply the normal external target, private HOME/XDG and native-build lock required
by your environment. The harness refuses an existing verification workspace,
retains all CLI outputs and checks save/reopen/edit/prepare/import plus failure
cases. See [the full guide](../../docs/WORKFLOW_PAYLOAD_PLANS.md).
