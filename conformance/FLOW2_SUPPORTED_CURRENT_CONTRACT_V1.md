# MoonFlow supported-current-contract inventory v1

- Inventory id: `moonflow.flow2-supported-current-contract.v1`
- Frozen baseline: `d8af47bc4ae0e04213eead3bcbcea7c810b1be3e`
- Scope: frozen current compatibility evidence plus the separately versioned,
  domain-neutral FLOW-3 contract package

## Frozen current surface

The supported import protocol is `moonsuite.work-model.v1`. The supported
runtime stream is `moonflow.event-stream.v2`, and its serialized projection is
`moonflow.run-projection.v2`. Typed acceptance receipts use
`moonflow.acceptance-review.v1`. Adapter capabilities carry their caller-owned
`protocol` string; the current examples use `moonflow.adapter.v1`.

The root public families are `RuntimeEvent`, `EventKind`, `RuntimeItem`,
`RuntimeStatus`, `RunProjection`, `FlowError`; `AdapterCapability`,
`AdapterRequest`, `AdapterResult`, `AdapterAttemptStatus`,
`ReconciliationDecision`, `AdapterContractError`; and
`AcceptanceCriterionReview`, `AcceptanceReviewReceipt`, and
`AcceptanceReviewError`, plus their existing codecs, replay/projection,
readiness, reconciliation, review, and path-guard functions. The CLI package
has no public values or types.

The pre-FLOW-2 public-interface SHA-256 values are:

- root `pkg.generated.mbti`: `5bae5ec3be94548b89dc07736870cd0fa5d68f457b63638ccb42240f8c25c228`
- CLI `cmd/main/pkg.generated.mbti`: `5b878150adb30f6448e652949cf7673df9ce05c2d3e62a3b8ceff2b94f91c975`

The pre-existing fixture is `fixtures/source-linked-work-graph.json`. FLOW-2
adds reviewable golden inputs and outputs under `conformance/golden/v2/`; they
are evidence for current behavior, not new accepted runtime inputs.

## Separate FLOW-3 contract surface

FLOW-3 adds exactly one public package at `closed_loop/contracts`, imported as
`vectie/moonflow/closed_loop/contracts`. It is not re-exported by the existing
root package and is not imported by the CLI. Its generated public-interface
SHA-256 is
`ad6d9bc984109b9616e9a24447667dafaca00f78e73a05ac8221335ef0dfba97`.

The package owns opaque validated `RecordRef`, `SchemaRef`, `ArtifactRef`,
`EvidenceRef`, `OpaqueExtension`, `WireEnvelope`, `ContentDigest`, `Version`,
and `VersionProfile` values; pure `EnvelopeCodec`, `ReceiptExchangePort`, and
`WorkExchangePort` traits; deterministic highest-exact version negotiation;
and pure replay classification. It uses immutable `ReadOnlyArray` snapshots.

Canonical envelope version `1.0.0` is the length-prefixed binary format
documented by `WireEnvelope::canonical_bytes`. It hashes exact opaque payload
bytes and the complete canonical envelope except its own envelope-digest field
with pure SHA-256. The only accepted digest text is
`sha256:<64 lowercase hexadecimal digits>`. Canonical arrays are sorted,
exact-deduplicated, and conflicting identities fail closed.

This package has no persistence, event store, checkpoint, scheduler, lease,
outbox, authority-attestation, execution, dispatch, state-application, external
I/O, or concrete external adapter. It does not claim any FLOW-4 capability and
does not change current root or CLI behavior. Its package dependencies are
limited to MoonBit core buffer and UTF-8 helpers; the protected module
dependency set is unchanged.

## Frozen behavior and guarantees

- Graph import requires exact source linkage, unique declarations, non-empty
  criteria, canonical authority classes, known dependencies, and an acyclic
  graph. Only items with no dependencies are initially ready.
- Replay requires the exact run/source context and next sequence. An exact
  whole-event duplicate is a no-op. Reusing an event id with different content
  fails closed. Restart means replaying the complete event array and produces
  the same projection and canonical JSON.
- Readiness requires every declared dependency to be `Accepted`.
- Adapter reconciliation binds request, attempt, idempotency, and product
  identities. Exact resubmission and result import return the prior event;
  changed content under a reused result identity conflicts. Adapter success
  enters `Review`, never `Accepted`. These guarantees are exactly-once state
  projection guarantees, not exactly-once external-effect guarantees.
- Acceptance requires an item already in `Review` and binds run, item,
  declaration, result, attempt, output digest, criterion order/text, and
  attached evidence. A rejected receipt produces a visible blocker.
- Artifact references at the public layer must be non-empty, workspace-relative
  slash paths with no absolute prefix, empty component, or `..` component. The
  native CLI additionally requires existence, resolves workspace and artifact
  real paths, and rejects lexical, symlink, or canonical-path escape.

The root library is applicable to `wasm`, `wasm-gc`, `js`, and `native`. The
CLI and filesystem-backed golden/containment evidence are native-only, as
declared by their package or command boundary.

## Documented legacy durability and authority exceptions

The v2 surface predates the proposed rule that every durable record carry
explicit record and schema version fields. The precise FLOW-2 legacy allowlist
is `RuntimeEvent`, `RuntimeItem`, `RunProjection`, `AdapterCapability`,
`AdapterRequest`, `AdapterResult`, `AcceptanceCriterionReview`, and
`AcceptanceReviewReceipt` in their existing files. Their surrounding protocol
or contract ids provide compatibility context, but the records themselves are
not represented as fully versioned FLOW-3 records. No additional unversioned
durable declaration is allowed.

`ApprovalGranted` currently validates only a nonblank authority id. It is a
legacy string receipt and must never be described or bridged as a named-human
attestation. Acceptance receipt decoding requires nonblank reviewer fields,
but the current accepted event stores `review_authority_id`; `reviewer_id` is
not independently retained in the event/projection. FLOW-2 freezes and reports
these limitations; it does not strengthen or reinterpret them.

Current persistence rewrites `events.json` and `projection.json` as separate
whole files. Replay can recover a projection from a valid event file, but this
is not an append-only, crash-atomic event/outbox transaction. There is no
current durable outbox, effect-intent store, checkpoint, scheduler/lease store,
general authority attestation, or generalized secret-reference runtime type.

## Boundary and upgrade rule

MoonFlow currently has only its declared MoonBit dependencies and does not
compile against external product or domain source. Production code and public
interfaces must remain domain-neutral. Scanner implementation/configuration,
this inventory, conformance test names, and safe negative fixtures are the only
exact paths allowed to carry terms needed to test that rule; no production
directory is ignored.

`DOM004` enforces this boundary for representative finance terms (`finance`,
`financial`, A-share spellings, `stock`, and `equity_research`) and
AIGC/media-production terms (`aigc`, `campaign`, `scene`, `shot`, `storyboard`,
`animatic`, `video_generation`, and `video_production`) when they occur as
explicit tokens or identifier components. It does not reserve neutral contract
terms such as record, schema, envelope, artifact, evidence, asset, workflow,
stage, tool, review, effect, provider, project, operation, or adapter.

Any change to a frozen production-source hash, either protected root/CLI
public-interface hash,
golden v2 bytes, legacy allowlist, protocol interpretation, or guarantee above
remains outside the frozen FLOW-2 baseline. The FLOW-3 source, test, manifest,
and generated-interface hashes are independently enumerated in
`boundary-rules.json`; only those exact paths are approved. New stores,
effects/outbox, generalized attestations, schedules, and durable runtime
records remain later architecture and are neither implemented nor represented
by placeholder APIs.
