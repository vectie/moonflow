# Generic Operator Receiver Loop

MoonFlow’s operator receiver loop connects a declared Work item to a
pack-owned application without creating another agent runtime. MoonClaw
remains the only agent runtime; MoonFlow owns orchestration and replay;
MoonDesk resolves configured pack manifests and exposes the local same-origin
transport.

The loop is domain-neutral. Product names, finance concepts, media concepts,
robotics concepts, and product-specific decisions do not enter MoonFlow or
MoonDesk.

## Published handoff

For each ready Work item whose declared input artifacts can be verified,
MoonFlow writes:

- `operator-handoffs/<action-id>.json` with contract
  `moonflow.operator-handoff.v2`;
- `operator-actions.json` with contract `moonflow.operator-actions.v2`,
  version `2.1.0`.

The handoff has two parts:

- `payload` contains the immutable run, Work-item, declaration, product,
  operation, input-contract, output-contract, authority, evidence, review, and
  manifest-entrypoint binding;
- `binding` contains a 64-character opaque token, the SHA-256 digest of the
  exact payload, and deterministic request, attempt, and idempotency
  identities.

The token is not authority. It is an unguessable, digest-bound correlation
identity. A receiver must still return explicit authority and review evidence.

MoonDesk enables navigation only when its installed manifest and local app
runtime resolve the exact published `pack_id`. The browser opens:

```text
/pack-apps/<pack-id>/?moonflow_run=<run-id>&moonflow_handoff=<opaque-token>
```

There is no Packs fallback. A missing, unsafe, or mismatched entrypoint remains
visible but disabled.

## Receiver API

The configured pack application reads the two query values and uses the
MoonDesk origin that served it:

```text
GET  /api/moonflow/runs/<run-id>/handoffs/<token>
GET  /api/moonflow/runs/<run-id>/handoffs/<token>/status
POST /api/moonflow/runs/<run-id>/handoffs/<token>/receipt
```

The intake response is the exact verified
`moonflow.operator-handoff.v2`. The status response is
`moonflow.receiver-status.v1` and reports `pending`, `accepted`, or `denied`,
the durable receipt reference and digest when present, the current Work-item
state, the run outcome, and `/?activity=flow` as the return path.

The POST body uses `moonflow.receiver-receipt.v1`:

```json
{
  "contract_id": "moonflow.receiver-receipt.v1",
  "contract_version": "1.0.0",
  "receipt_id": "receipt-build-1",
  "handoff_token": "<token>",
  "handoff_digest": "sha256:<token>",
  "run_id": "run-1",
  "work_item_id": "build-output",
  "declaration_id": "build-output-r1",
  "product_id": "product-one",
  "operation": "product-one/build@1.0.0",
  "request_id": "receiver-request-<token-prefix>",
  "attempt_id": "receiver-attempt-<token-prefix>",
  "idempotency_key": "receiver-<token>",
  "decision": "accepted",
  "output_contracts": ["product-one/receipt@1.0.0"],
  "output_artifacts": [
    "evidence/authority.json",
    "evidence/output.json"
  ],
  "output_digest": "sha256:<aggregate-output-digest>",
  "authority": {
    "requested_authority": "workspace-mutation",
    "decision": "granted",
    "receipt_ref": "evidence/authority.json"
  },
  "review": {
    "review_id": "review-build-1",
    "decision": "accepted",
    "reviewer_id": "named-reviewer",
    "review_authority_id": "review-authority",
    "criteria": [
      {
        "criterion": "reviewed output exists",
        "satisfied": true,
        "evidence_refs": ["evidence/output.json"],
        "note": "The declared output was reviewed."
      }
    ]
  },
  "owner_id": "product-one-operator",
  "recorded_at": "2026-07-31T00:01:00Z"
}
```

An accepted receipt must reproduce every bound identity, preserve the exact
declared output-contract order, cite existing workspace-confined artifacts,
match the recomputed aggregate output digest, include a granted authority
receipt among those outputs, and review every acceptance criterion in the
original order with evidence. MoonFlow converts it through the existing
adapter-attempt and acceptance-review contracts, then makes newly unblocked
dependencies ready.

A denied receipt must contain a bound authority denial or rejected review. It
records a terminal failed Work item and never unlocks a dependency.

## Recovery and replay

Before applying a receipt, MoonFlow stores
`operator-receipts/<token>.json` as a `received` journal record. After the
attempt, result, review, and dependency events are durable, it marks the record
`applied`.

MoonDesk checks for received journals when the action queue or receiver API is
loaded and asks the same MoonFlow CLI to resume them. Reconciliation is
idempotent. Reusing a token with different bytes, changing input evidence after
publication, changing run or operation identity, replaying against a
non-matching Work-item state, escaping the workspace, or presenting an
unconfigured manifest entrypoint fails closed.

The operator queue retains accepted and denied handoffs after restart. It shows
the receipt reference, digest, recorded time, and a return-to-Flow action while
the next ready item appears as a new pending handoff.

## Product receiver requirement

Each pack-owned UI still must implement a small receiver adapter:

1. read `moonflow_run` and `moonflow_handoff` from the launch URL;
2. fetch and display the intake before doing work;
3. write its output, authority, evidence, and review artifacts under the
   workspace paths declared in the receipt;
4. POST the exact generic receipt;
5. show the returned status and offer its `return_path`.

A product must not introduce a private scheduler or agent runtime for this
loop. Downstream products are declared as subsequent MoonFlow Work items; an
accepted upstream receipt lets MoonFlow issue the next manifest-owned handoff.
