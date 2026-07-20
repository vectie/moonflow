# Reinforcement capability loop

Moon Suite uses one governed software-improvement loop. It does not create a
second agent runtime and it does not let a language model deploy its own code.

```text
real delivery
  -> pack-owned outcome and reward evidence
  -> MoonBook Bookkeeper outcome history + Three Gap assessment
  -> reviewed capability proposal
  -> MoonCode implementation through the MoonClaw runtime
  -> tests and named-human adoption receipt
  -> separately reviewed MoonFlow activation request
  -> shadow/canary/full resolution on the next MoonClaw run
  -> MoonTown baseline/challenger evaluation
  -> named-human promote/rollback/hold settlement in MoonFlow
  -> later real delivery, beginning the next cycle
```

## Ownership

| Component | Owns | Must not own |
|---|---|---|
| Domain pack | acceptance criteria and reward semantics | generic activation machinery |
| MoonGate | attributable telemetry and outcome evidence | capability policy |
| MoonBook Bookkeeper | history, Three Gap assessment, review and immutable authorization receipts | activation or deployment side effects |
| MoonClaw / MoonCode | the single agent runtime and bounded implementation work | self-authorization |
| MoonFlow | deterministic activation, resolution, observation and settlement state | domain reward interpretation or another agent runtime |
| MoonTown | cohort assignment and baseline/challenger recommendation | applying promotion or rollback |
| MoonDesk | existing MoonBook Rabbita review UI | a separate Bookkeeper application |

## Activation contract

`CapabilityVersionReceipt::activation_request` projects a non-applying
MoonBook receipt into `moonbook.bookkeeper.capability_activation_request.v1`.
It requires a safe scope, exact old/new/rollback and experiment references, a
rollout mode, an observation budget, and a second named-human activation review.

MoonFlow persists the active projection under the selected MoonBook:

```text
.moonsuite/products/moonflow/capabilities/<scope-id>.json
```

The CLI surface is:

```text
moonflow activate-capability <workspace> <request.json> <activation-id> <activated-at>
moonflow resolve-capability <workspace> <scope-id> <participant-id>
moonflow observe-capability <workspace> <scope-id> <observation.json>
moonflow settle-capability <workspace> <scope-id> <settlement.json>
```

Activation is fail-closed. Canary observations must match the participant's
recorded assignment and exact capability version. Observation count cannot
exceed the reviewed budget. Promotion or rollback requires a versioned
experiment outcome, review evidence, and named reviewer authority.

## Runtime resolution

A MoonCode command opts into the governed capability through
`capability_scope_id`; it may provide `capability_participant_id`, otherwise the
bound MoonClaw session is the participant. Before planning, the existing native
runtime reads MoonFlow's projection and injects an `active_capability` record.

- `shadow`: baseline remains selected; challenger is observation-only.
- `canary`: only named challenger participants receive the new version.
- `full` or promoted: the new version is selected.
- rolled back: the old version is selected.
- missing or invalid projection: assignment is `unavailable`; MoonCode must not
  infer or invent a capability.

## Experiment and settlement

MoonTown deterministically binds enrolled participants to baseline or
challenger arms and evaluates immutable observations. Its outcome is only a
`promote`, `rollback`, or `hold` recommendation. A human-reviewed MoonFlow
settlement is still required to alter the active projection.

This closes the software edge of the loop. Production rollout still requires
MoonDesk to expose these existing contracts in the MoonBook Bookkeeper UI and a
scheduled adapter to persist repeated MoonTown evaluations; neither changes the
runtime or ownership model.
