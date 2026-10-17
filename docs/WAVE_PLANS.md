# Bounded execution waves

An operator with a wide approved graph can prepare an execution plan that makes
at most N work items eligible at once. This is useful for limiting review load or
rolling out a batch gradually without manually wiring every prerequisite.

```
moonflow plan preview-waves <workspace> <source-graph-ref> <draft-id> <recorded-at> <max-parallel>
moonflow plan from-waves <workspace> <source-graph-ref> <draft-id> <recorded-at> <max-parallel>
moonflow plan inspect <workspace> <draft-id>
moonflow plan prepare <workspace> <draft-id> <catalog-ref> <evaluated-at>
```

Preview reports the waves, exact added dependency edges and ordinary editable
plan form. `from-waves` saves that same draft, with existing identity collision
protection. Preparation uses the existing capability checks and returns the child
graph and proposal. Use the existing conformant import and authorized operator
execution workflow; neither preview nor saving grants authority or dispatches.

The wave width must be 1..256, with at most 256 source items. Each wave selects
source-order items whose original prerequisites are in earlier waves. Every item
in the following wave additionally depends on every item in the preceding wave.
All original edges and operation/schema/authority/claim fields remain unchanged.
The source graph is not rewritten. A source with unknown or cyclic dependencies
is refused. All input paths must be present and workspace-contained before save.

A later wave waits for acceptance of the entire preceding wave, including review.
A failed, unknown, or unreviewed item therefore holds later waves. These barriers
are deliberately conservative and may reduce throughput. This is a static bound
within this graph, not a global worker semaphore, rate limit or autonomous
scheduler. Editing dependencies later can change the bound. Re-importing a new
revision still follows existing migration/reuse and authority policy; this
transform does not automatically rerun accepted effects.

## Focused verification

Run `scripts/test_wave_plan.sh` from any working directory. It runs the core tests,
builds the native CLI, and exercises preview, save/reopen, identity collisions,
prepare, conformant import and fail-closed negative cases in a retained synthetic
workspace. It requires the approved toolchain and restored exact dependencies.
No product adapters or external services are executed.
