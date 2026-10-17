# Execute one imported digital Mold item

This opt-in native path executes exactly one selected ready item in an already
imported run. It does not import a graph, run the unattended supervisor, publish
dependent handoffs, accept a review, or advance another item.

```text
moonflow execute-one <workspace> <run-id> <item-id> <request-id> <configuration-ref> <recorded-at>
moonflow reconcile-one <workspace> <run-id> <item-id> <request-id> <configuration-ref> <recorded-at>
```

`request-id` identifies the UI action. Flow creates and retains the distinct
adapter request, attempt and idempotency lineage. Adapter request and attempt IDs
hash a length-prefixed run/item/attempt-number tuple because native Mold's durable
attempt store is workspace-wide. Hyphenated identifiers cannot alias each other.

## Trusted configuration and authority

Only a trusted host should supply the workspace, configuration reference and
current UTC time. Desk resolves the workspace from its selected registered Book.
Its browser request contains identifiers and a fixed action, never a program,
command line, authority envelope, or config body.

```json
{
  "contract_id": "moonflow.single-step-config.v2",
  "capability_ref": "trusted/capability-catalog.json",
  "envelope_ref": ".moonsuite/products/moongate/autonomy/EXISTING-APPROVED/envelope.json",
  "usage_ref": "trusted/usage.json",
  "gate_executable": "/canonical/native/moongate",
  "gate_sha256": "sha256:EXACT_BINARY_SHA256",
  "adapter_executable": "/canonical/native/moonmold-adapter",
  "adapter_sha256": "sha256:EXACT_BINARY_SHA256"
}
```

The config is host-owned and must not be placed in browser-editable drafts or
exports. The generic route retains a `workspace-mutation` / `digital-artifact`
ceiling, a fresh conformant catalog and hash-bound native health evidence. The
pinned pack verifier accepts only its exact operation and schemas. Mold's
verifier requires `moonmold-pack-local-v1`,
`moonmold/spatial.operation.execute@0.2.0` and `mock-reference`; no Node or Blender
route is used. Program paths are absolute/canonical and checked against their configured
SHA256 before execution. Child processes receive no ambient environment.

Version 1 configurations require an explicit migration. The pack-owned
`moonmold-adapter migrate-single-step-config <legacy-config.json>` prints a
version 2 configuration while preserving every authority reference, program
path and program hash. It writes no configuration or grant. Review and retain
the translated host configuration. Existing terminal action records remain
readable. A legacy pending action can only use `reconcile-one`: the pinned owner
verifier must explicitly recognize and bind its exact original request and
attempt. Flow retains the exact old action bytes before recording the new proof,
rechecks Gate authority, and never invokes or retries that legacy attempt.

The existing approved Gate envelope must bind the actual canonical workspace and
the imported run's source digest. Each effectful call goes through the fixed
native `suite autonomy-check` command. Missing, expired, revoked, source-mismatched,
workspace-mismatched or otherwise denied authority prevents product invocation.
Mold's attempt directory, semantic journal and any declared representation export
must fit that authority. A run's pause/cancel/narrowed-authority control is also
honored. This command never creates a grant or claims that a production grant
exists.

Each call reserves one tool call and 1 MiB of storage conservatively, plus one
attempt for initial execution and zero for reconciliation. A crash does not roll
usage back. Reconciliation may consume additional tool/storage budget.

## Durable execution and restart

Flow takes a workspace-scoped native writer lock covering the full one-item
operation. The lock is automatically released on process death. It atomically
persists the UI action identity before recording the adapter submission and
before any possible Mold invocation. Request identities cannot silently switch
items, and a second action identity cannot replace an existing item's attempt.

Repeated `execute-one` returns the persisted action and never invokes Mold again.
Any unknown or interrupted outcome stays `reconcile-required`. Only
`reconcile-one` may call the product again, with native `reconcile-report` and the
original adapter request. Even a `not-applied` report does not authorize a retry
through this route. Reconciliation rechecks current authority and health.

When the locked path proves no selected action or attempt exists, a setup or
authority failure returns the correlated `moonflow.single-step-blocker.v1` with
`no_attempt_created=true`. Desk can retain and retry the same UI request after
repair. Missing, malformed or transport-failed responses never imply retry
safety; they remain reconciliation-only.

Action and evidence files are in:

```text
.moonsuite/products/moonflow/runs/<run>/single-step/<item>.action.json
.moonsuite/products/moonflow/runs/<run>/single-step/<item>.request.json
.moonsuite/products/moonflow/runs/<run>/single-step/<item>.result.json
.moonsuite/products/moonflow/runs/<run>/single-step/<item>.evidence.json
```

The action record is the source for restoring the original UI request ID on
reopen. Process failures and malformed/wrong-correlated results retain the
attempt for reconciliation and cannot start a fresh attempt.

## Receipt and Review boundary

The unchanged native Mold protocol returns JSON on stdout. Flow checks request,
attempt, idempotency and product correlation. Its output digest is the SHA256 of
the exact native operation receipt bytes, not the unattended manifest's aggregate
output digest convention. Flow calls the pinned adapter's fixed read-only
`verify-single-step` command before Gate authorization and again before durable
result import. Each proof binds the SHA256 of the exact verification exchange,
selected capability, request, attempt and input digest. The pack owns receipt
operation/outcome/schema and qualification checks. Flow independently checks
generic correlation, exact receipt/artifact hashes, canonical nonsymlinked
paths and equality with the preauthorized write policy. It retains the hashes
of every reported artifact.

The catalog compiler also retains versioned owner-declared input capture
policies. Preparation requires explicit policies for every catalog operation;
recompile older source bundles instead of silently treating nested inputs as
opaque. The pack declares its exact payload contract and explicit root
reference-array field. Flow captures and rebinds that bounded array, retains
original and rebound bytes, and revalidates them before applying the plan.
Opaque policies keep their original bindings and disclose that limited scope.

A verified success appends exactly the existing reconciliation event and stops
at `Review`. There is no reviewer, observer, acceptance receipt or dependent
dispatch. Another ready item remains untouched. The result explicitly retains
`fixture-reference-only`, `production_qualified=false`, `blender_evidence=false`
and `physical_authority=false`.

## Qualification

R23 verification uses isolated synthetic workspaces and explicitly synthetic
approved Gate fixtures. The positive path crosses the compiled Desk UI and native
Desk host, native Flow, native Gate, and unchanged native Mold. The harness also
checks concurrent/repeated actions, denial cases, incorrect results, process
death after product mutation and recovery of the original attempt. Journal-only
interruption evidence is an explicitly labeled fixture simulation.

These checks do not establish live Blender/provider execution, engineering
fitness, production authority or physical readiness. The existing unattended
manifest contract and Desk's generic deny-by-default executor are unchanged.
