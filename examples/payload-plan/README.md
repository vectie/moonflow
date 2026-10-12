# Three generated model requests

The JSON export names compact, wide and display jobs. One explicit request
template is materialized into three requests; display depends on both model
jobs. No pre-authored per-job requests are needed. Source input paths are only
a template declaration and need not exist for this import.

Build the native CLI and copy this example's JSON files into a new workspace.
Then use an absolute executable path:

```sh
"$MOONFLOW_CLI" plan preview-payloads "$WORKSPACE" source-graph.json mapping.json request-template.json records.json study 2026-07-31T00:00:00Z
"$MOONFLOW_CLI" plan from-payloads "$WORKSPACE" source-graph.json mapping.json request-template.json records.json study 2026-07-31T00:00:00Z
"$MOONFLOW_CLI" plan inspect "$WORKSPACE" study
"$MOONFLOW_CLI" compile-capability-catalog "$WORKSPACE/capability-source-bundle.json" > "$WORKSPACE/catalog.json"
"$MOONFLOW_CLI" plan prepare "$WORKSPACE" study catalog.json 2026-07-31T00:00:00Z
```

Review each receipt's exact request text, retained operation/authority, item IDs
and dependency list before preparing or executing anything. The timestamps and
catalog health are synthetic July fixtures, not current production evidence.
This sample prepares requests only; no MoonMold adapter is run.

The repository verifier exercises preview, save, repeat, reopen, preparation and
conformant import, checks content digests and zero attempts, and retains actual
stdout/stderr and result files in a fresh workspace:

```sh
python3 scripts/verify_payload_plan.py --cli "$MOONFLOW_CLI" --workspace-parent "$VERIFY_DIR"
```

See [the full contract](../../docs/PAYLOAD_TEMPLATE_PLANS.md) for typed bindings,
additional evidence files, limits, source identity and interrupted-save behavior.
