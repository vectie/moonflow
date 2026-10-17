# Two jobs from one shared model

All inputs are synthetic, digital-only fixtures. Copy this directory to a fresh
workspace and use a trusted native `moonflow` CLI. Preview then save:

```sh
moonflow plan preview-joined-workflow /absolute/workspace source-graph.json workflow.json join.json jobs.json models.json study 2026-07-31T00:00:00Z
moonflow plan from-joined-workflow /absolute/workspace source-graph.json workflow.json join.json jobs.json models.json study 2026-07-31T00:00:00Z
moonflow plan inspect /absolute/workspace study
moonflow plan export /absolute/workspace study
moonflow compile-capability-catalog /absolute/workspace/capability-source-bundle.json > /absolute/workspace/catalog.json
moonflow plan prepare /absolute/workspace study catalog.json 2026-07-31T00:00:00Z
```

Both `chair` and `stool` match `seating`. Eight requests preserve the four-step
diamond for each study. Reference row 1 (`tables`) is visibly unused. Try changing
one model key to see a no-match refusal, or duplicating `seating` to see the
ambiguous-reference refusal. Neither operation silently loses work.

The dated fixture catalog is for this test only. Requests are synthetic examples,
not valid production MoonMold requests. Preparation is not execution. Follow
[the guide](../../docs/JOINED_WORKFLOW_PLANS.md) for normal edit/prepare/revision
boundaries and use current actual capability contracts for real work.
