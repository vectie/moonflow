# MoonFlow

MoonFlow is Moon Suite's generic durable orchestration capability and engine.
MoonClaw is the suite's single agent runtime: it owns the model loop, personas,
reasoning lifecycle, and agent execution, and may call MoonFlow to durably
advance declared work. MoonBook owns source intent; MoonFlow imports a
versioned Work graph, preserves its source linkage, evaluates dependencies,
records attempts and evidence, and projects recoverable orchestration state.

MoonFlow is not an agent and does not have a model loop, persona, autonomous
reasoning lifecycle, or self-scheduling behavior. Its library and command-line
surfaces perform explicit orchestration operations when invoked by MoonClaw or
an operator/developer.

## Constitutional boundary

- MoonFlow advances durable orchestration for declared intent when invoked; it
  does not author MoonBook goals or independently decide to run work.
- MoonFlow owns run events, attempts, policy decisions, and recovery state.
- Product adapters own their domain effects and return typed receipts.
- MoonTown may propose work but cannot mark MoonFlow items complete.
- Physical effects always require separately granted physical authority.

## Event stream v3

`moonflow.event-stream.v3` adds governed checkpoint reuse without weakening the
fresh execution contract. A
Work graph must provide:

- `book_id`, `declaration_revision`, and `source_digest`;
- a unique `declaration_id` for every Work item;
- canonical `requested_authority` values;
- non-empty `acceptance_criteria`;
- known, acyclic dependencies.

The importer fails closed instead of creating permanently waiting work when a
dependency is unknown or cyclic. Every event carries the immutable source
context, so replay rejects events from a different book revision or digest.

Canonical authority classes are `observe`, `cognitive-maintenance`,
`sandbox-execution`, `workspace-mutation`, `external-effect`, and
`physical-effect`.

## Adapter contract

The adapter boundary records capability, request, attempt, idempotency key,
input digest, requested authority, external job identity, terminal status,
output digest, artifacts, error classification, and compensability. Production
adapters must support reconciliation. Result import fails closed when request,
attempt, idempotency, or product identity differs.

Capability records also declare health, operations, authority classes,
input/output contracts, and a claim ceiling. The director selects an adapter
only when all dimensions match. Unknown outcomes reconcile before any retry;
quality rejection revises the input or procedure instead of repeating it.

`prepare-next` removes hand-authored dispatch requests. It derives each ready
item's requirement from its MoonBook execution binding, selects a healthy
compatible adapter, verifies and hashes the declared input artifacts, writes a
durable decision/request pair, and submits the attempt event. A rejected
selection is retained as a decision receipt and does not start work.
`complete-artifacts` performs the symmetric return path for local adapters: it
verifies workspace-relative output artifacts, derives their aggregate digest,
materializes the typed result receipt, and reconciles it into review state.

## Native revision and evidence lineage

`revise-run` creates a child run and never rewrites its parent. It reuses an
accepted checkpoint only when declaration identity, owner, authority,
acceptance criteria, evidence identity, and every dependency revalidate.
Changed checkpoints are explicitly marked invalidated in a
`moonflow.run-migration.v1` receipt. Reuse is represented by a durable
`checkpoint-reused` event and remains distinct from new execution.

`bundle-evidence` reads a workspace-relative descriptor, verifies every source
before mutation, hashes and stores immutable content-addressed objects, writes a
manifest, and verifies workspace containment again after mutation. The command
removes manual copying and hash transcription while retaining producer,
contract, claim, and result provenance.

## CLI

The CLI is an operator/developer surface for inspecting, driving, and
diagnosing the engine. It is not a separate agent process or agent runtime.

```text
moonflow import-graph <workspace> <graph.json>
moonflow status <workspace> <run-id>
moonflow transition <workspace> <run-id> <work-item-id> <action> <recorded-at> [detail]
moonflow advance <workspace> <run-id> <recorded-at>
moonflow submit-attempt <workspace> <run-id> <request.json>
moonflow reconcile-attempt <workspace> <run-id> <result.json>
moonflow review-outcome <workspace> <run-id> <workspace-relative-review-receipt>
moonflow revise-run <workspace> <parent-run-id> <child-graph-artifact> <proposal-artifact> <migration-id> <recorded-at>
moonflow select-adapter <workspace> <capabilities-artifact> <requirement-artifact>
moonflow prepare-next <workspace> <run-id> <capabilities-artifact> <recorded-at>
moonflow complete-artifacts <workspace> <run-id> <work-item-id> <recorded-at> <artifact>...
moonflow bundle-evidence <workspace> <bundle-spec-artifact> <recorded-at>
moonflow run-unattended <workspace> <graph-artifact> <capabilities-artifact> <manifest-artifact> <envelope-artifact> <usage-artifact> <recorded-at>
moonflow validate-capability <capability.json>
```

`run-unattended` requires a v3 manifest. Every attempt is authorized by
MoonGate before execution, its declared artifacts are digest-verified, a
distinct product attestor must turn the isolated agent draft into a separately
declared final artifact, and an independent reviewer must decide the immutable
criteria against that product-owned final path. Durable request, draft result,
attestation, and review receipts are recovery checkpoints: restarting after any
one of them does not repeat completed work or create a second attempt.

Install the cross-product unattended runtime reproducibly instead of copying
development build paths into a manifest:

```sh
scripts/install_moonsuite_runtime.sh ~/moonsuite
```

The installer builds the owning products, installs only runtime executables
under `~/moonsuite/bin`, and writes a content-addressed source/binary manifest
at `~/moonsuite/.moonsuite/runtime/installed-runtime.json`. Set
`MOON_SUITE_SOURCE_ROOT` only when the source repositories are not sibling
directories under `~/Workspace`.

The restart invariant is fault-injected at all three post-action boundaries:

```text
python3 scripts/unattended_recovery_smoke.py harness \
  _build/native/debug/build/cmd/main/main.exe
```

The first three launches are deliberately killed after result, product
attestation, and review persistence. The fourth resumes to accepted state and
the fifth proves terminal duplicate delivery is a no-op. The smoke test also
requires an unattended-qualified intervention scorecard and exactly one
attempt identity.

### Ordered HTTP JSON transport

The operator/developer CLI includes one domain-neutral transport utility for
transferring selected top-level fields from a fetched JSON object in a declared
order. The utility performs no reasoning and does not create an agent loop:

```bash
moon run cmd/main -- ordered-http-json \
  fixtures/ordered-http-json.config.json \
  /path/to/new-receipt.json
```

The configuration contract is `moonflow.ordered_http_json.v2`:

```json
{
  "contract_version": "moonflow.ordered_http_json.v2",
  "transfer_id": "example-ordered-transfer-v1",
  "source_url": "http://127.0.0.1:4100/api/bundles/example",
  "expected_source_digest": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "max_response_bytes": 1048576,
  "max_attempts": 3,
  "retry_delay_ms": 250,
  "steps": [
    {"field": "record", "destination_url": "http://127.0.0.1:4200/api/ingress/records"},
    {"field": "envelope", "destination_url": "http://127.0.0.1:4200/api/ingress/envelopes"}
  ]
}
```

The transport performs exactly one GET, requires its raw response digest to
match `expected_source_digest`, requires a top-level JSON object, and then
serializes and POSTs each configured field in array order. It accepts no header,
token, secret, cookie, username, password, query, or fragment configuration.
Every response is streamed under `max_response_bytes`, must be UTF-8 JSON with
a 2xx status, and must not carry a generic error signal (`error`, non-empty
`errors`, or false `ok`, `success`, or `accepted`).

Each POST is retried at most `max_attempts` times with `retry_delay_ms` between
failures. Every attempt for one step carries the same `Idempotency-Key`, derived
only from the transfer ID, step ordinal, selected field, destination, and exact
request digest. Re-running the same immutable transfer therefore uses the same
keys; changing the source bytes, payload, destination, or order changes them.

On complete success the command refuses to overwrite the receipt path, writes
one compact canonical receipt with mode `0600`, and prints the same value. The
receipt binds the source response digest and every ordered request body,
destination, idempotency key, attempt count, status, and exact raw response
digest; `receipt_digest` hashes the canonical receipt core. A failed step stops
later steps and emits no success receipt. Because later steps cannot start until
the prior step returns a successful JSON receipt, `record` followed by
`envelope` in the configuration is a strict delivery boundary.
See `fixtures/ordered-http-json.config.schema.json` for the strict schema.

Adapter success moves Work to review; it never implies acceptance. The only
CLI acceptance path is `review-outcome`, whose typed receipt must match the
persisted run, declaration, result, attempt, and output digest, review every
original criterion in order, and cite evidence already attached to the Work
item.

If execution reveals that a criterion belongs to the wrong product, MoonBook
compiles a new declaration revision and `revise-run` performs checkpoint
migration. The old event history remains unchanged; invalid evidence is never
reinterpreted in place.

All durable orchestration state is stored under
`<workspace>/.moonsuite/products/moonflow/runs/<run-id>`. Artifact transitions
accept only existing workspace-relative paths and reject canonical path escape.

## Verification

```text
moon check --target native --deny-warn
moon test --target native --deny-warn
moon info
moon fmt
```
