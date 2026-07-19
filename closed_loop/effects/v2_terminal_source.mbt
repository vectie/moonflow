///|
let terminal_source_receipt_kind_v2 = "committed-effect-terminal-source-v2"

///|
fn terminal_source_state_tag_v2(state : ReconciliationState) -> String {
  match state {
    KnownSuccess => "known-success"
    KnownFailure => "known-failure"
    ReconciledSuccessState => "reconciled-success"
    ReconciledFailureState => "reconciled-failure"
    ReconciledNotAppliedRetryEligible => "reconciled-not-applied"
    _ => "nonterminal"
  }
}

///|
/// Opaque replay-minted proof of one exact committed effects outcome that may
/// be considered by the aggregate work-terminal classifier. It is neither
/// mutation nor dispatch authority and has no public constructor or decoder.
pub struct CommittedEffectTerminalSourceV2 {
  receipt_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  root_intent_ref : @contracts.RecordRef
  root_attempt_ref : @contracts.RecordRef
  source_intent_ref : @contracts.RecordRef
  source_attempt_ref : @contracts.RecordRef
  lineage_digest : @contracts.ContentDigest
  attempt_count : Int64
  retry_count : Int64
  state : ReconciliationState
  source_record_ref : @contracts.RecordRef
  source_record_bytes : Bytes
  source_observed_at : Int64
  source_event_ref : @contracts.RecordRef
  source_event_bytes : Bytes
  source_evidence : ReadOnlyArray[@contracts.EvidenceRef]
  unknown_receipt_ref : @contracts.RecordRef?
  unknown_receipt_bytes : Bytes?
  unknown_receipt_event_ref : @contracts.RecordRef?
  unknown_receipt_event_bytes : Bytes?
  reconciliation_request_ref : @contracts.RecordRef?
  reconciliation_request_bytes : Bytes?
  reconciliation_request_event_ref : @contracts.RecordRef?
  reconciliation_request_event_bytes : Bytes?
  projection_sequence : Int64
  projection_revision : Int64
  projection_head_digest : @contracts.ContentDigest
  projection_state_digest : @contracts.ContentDigest
  projection_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn write_optional_terminal_source_record_v2(
  writer : EffectsWriter,
  record_ref : @contracts.RecordRef?,
  record_bytes : Bytes?,
  event_ref : @contracts.RecordRef?,
  event_bytes : Bytes?,
) -> Unit raise EffectsError {
  match (record_ref, record_bytes, event_ref, event_bytes) {
    (None, None, None, None) => writer.byte(0)
    (Some(reference), Some(bytes), Some(event), Some(event_canonical)) => {
      writer.byte(1)
      write_ref(writer, reference)
      writer.bytes(bytes)
      write_ref(writer, event)
      writer.bytes(event_canonical)
    }
    _ => raise RetryEligibilityViolation(field="terminal_source_optional_chain")
  }
}

///|
fn strict_terminal_source_event_bytes_v2(
  projection : EffectsProjection,
  event_ref : @contracts.RecordRef,
) -> Bytes raise EffectsError {
  guard projection.strict_replay is Some(replay) else {
    raise RetryEligibilityViolation(
      field="terminal_source_requires_strict_replay",
    )
  }
  guard replay.events().search_by(event => event.event_ref() == event_ref)
    is Some(index) else {
    raise RetryEligibilityViolation(field="terminal_source_event")
  }
  replay.events()[index].canonical_bytes()
}

///|
fn mint_effect_terminal_source_v2(
  projection : EffectsProjection,
  lineage : RetryLineageV2,
  state : ReconciliationState,
  source_record_ref : @contracts.RecordRef,
  source_record_bytes : Bytes,
  source_observed_at : Int64,
  source_event_ref : @contracts.RecordRef,
  source_evidence : ArrayView[@contracts.EvidenceRef],
  unknown_receipt_ref : @contracts.RecordRef?,
  unknown_receipt_bytes : Bytes?,
  unknown_receipt_event_ref : @contracts.RecordRef?,
  reconciliation_request_ref : @contracts.RecordRef?,
  reconciliation_request_bytes : Bytes?,
  reconciliation_request_event_ref : @contracts.RecordRef?,
) -> CommittedEffectTerminalSourceV2 raise EffectsError {
  if source_observed_at < 0L ||
    terminal_source_state_tag_v2(state) == "nonterminal" {
    raise RetryEligibilityViolation(field="terminal_source_state")
  }
  guard projection.last_event_digest is Some(projection_head_digest) &&
    projection.replay_digest is Some(projection_replay_digest) else {
    raise RetryEligibilityViolation(field="terminal_source_projection")
  }
  if source_record_ref.digest() != @contracts.sha256_digest(source_record_bytes) {
    raise DigestMismatch(field="terminal_source_record")
  }
  let source_event_bytes = strict_terminal_source_event_bytes_v2(
    projection, source_event_ref,
  )
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6/COMMITTED-EFFECT-TERMINAL-SOURCE-V2/2.0.0")
  writer.string(effects_record_version)
  write_ref(writer, projection.workflow)
  write_ref(writer, lineage.root_intent_ref)
  write_ref(writer, lineage.root_attempt_ref)
  write_ref(writer, lineage.source_intent_ref)
  write_ref(writer, lineage.source_attempt_ref)
  writer.string(lineage.digest.text())
  writer.int64(lineage.attempt_count)
  writer.int64(lineage.retry_count)
  writer.string(terminal_source_state_tag_v2(state))
  write_ref(writer, source_record_ref)
  writer.bytes(source_record_bytes)
  writer.int64(source_observed_at)
  write_ref(writer, source_event_ref)
  writer.bytes(source_event_bytes)
  write_evidence(writer, source_evidence)
  write_optional_terminal_source_record_v2(
    writer,
    unknown_receipt_ref,
    unknown_receipt_bytes,
    unknown_receipt_event_ref,
    match unknown_receipt_event_ref {
      Some(event_ref) =>
        Some(strict_terminal_source_event_bytes_v2(projection, event_ref))
      None => None
    },
  )
  write_optional_terminal_source_record_v2(
    writer,
    reconciliation_request_ref,
    reconciliation_request_bytes,
    reconciliation_request_event_ref,
    match reconciliation_request_event_ref {
      Some(event_ref) =>
        Some(strict_terminal_source_event_bytes_v2(projection, event_ref))
      None => None
    },
  )
  writer.int64(projection.sequence)
  writer.int64(projection.revision)
  writer.string(projection_head_digest.text())
  writer.string(projection.state_digest.text())
  writer.string(projection_replay_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref(
      terminal_source_receipt_kind_v2,
      lineage.source_intent_ref.id(),
      digest,
    ),
    workflow: projection.workflow,
    root_intent_ref: lineage.root_intent_ref,
    root_attempt_ref: lineage.root_attempt_ref,
    source_intent_ref: lineage.source_intent_ref,
    source_attempt_ref: lineage.source_attempt_ref,
    lineage_digest: lineage.digest,
    attempt_count: lineage.attempt_count,
    retry_count: lineage.retry_count,
    state,
    source_record_ref,
    source_record_bytes,
    source_observed_at,
    source_event_ref,
    source_event_bytes,
    source_evidence: ReadOnlyArray::from_array(source_evidence.to_owned()),
    unknown_receipt_ref,
    unknown_receipt_bytes,
    unknown_receipt_event_ref,
    unknown_receipt_event_bytes: match unknown_receipt_event_ref {
      Some(event_ref) =>
        Some(strict_terminal_source_event_bytes_v2(projection, event_ref))
      None => None
    },
    reconciliation_request_ref,
    reconciliation_request_bytes,
    reconciliation_request_event_ref,
    reconciliation_request_event_bytes: match reconciliation_request_event_ref {
      Some(event_ref) =>
        Some(strict_terminal_source_event_bytes_v2(projection, event_ref))
      None => None
    },
    projection_sequence: projection.sequence,
    projection_revision: projection.revision,
    projection_head_digest,
    projection_state_digest: projection.state_digest,
    projection_replay_digest,
    canonical,
    digest,
  }
}

///|
/// Mint the exact current terminal-source proof for one intent. Open, pending,
/// unknown, and reconciliation-requested states return `None`.
pub fn EffectsProjection::committed_effect_terminal_source_v2(
  self : EffectsProjection,
  source_intent_ref : @contracts.RecordRef,
) -> CommittedEffectTerminalSourceV2? raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "terminal_source_requires_strict_replay",
  )
  guard first(snapshot.intents, value => value.intent_ref == source_intent_ref)
    is Some(_) else {
    raise IdentityMismatch(field="terminal_source_intent")
  }
  let lineage = snapshot.retry_lineage(source_intent_ref)
  let state = snapshot.state_for(source_intent_ref)
  match state {
    KnownSuccess | KnownFailure => {
      guard snapshot.receipts.search_by(value => {
          value.intent_ref == source_intent_ref &&
          (
            (state == KnownSuccess && value.outcome == Succeeded) ||
            (state == KnownFailure && value.outcome == Failed)
          )
        })
        is Some(index) else {
        raise RetryEligibilityViolation(field="terminal_source_receipt")
      }
      let receipt = snapshot.receipts[index]
      Some(
        mint_effect_terminal_source_v2(
          self,
          lineage,
          state,
          receipt.receipt_ref,
          receipt.canonical,
          receipt.observed_at,
          snapshot.receipt_event_refs[index],
          receipt.evidence,
          None,
          None,
          None,
          None,
          None,
          None,
        ),
      )
    }
    ReconciledSuccessState
    | ReconciledFailureState
    | ReconciledNotAppliedRetryEligible => {
      guard snapshot.reconciliations.search_by(value => {
          value.intent_ref == source_intent_ref &&
          (
            (
              state == ReconciledSuccessState &&
              value.resolution == ReconciledSucceeded
            ) ||
            (
              state == ReconciledFailureState &&
              value.resolution == ReconciledFailed
            ) ||
            (
              state == ReconciledNotAppliedRetryEligible &&
              value.resolution == ReconciledNotApplied
            )
          )
        })
        is Some(reconciliation_index) else {
        raise RetryEligibilityViolation(field="terminal_source_reconciliation")
      }
      let reconciliation = snapshot.reconciliations[reconciliation_index]
      guard snapshot.requests.search_by(value => {
          value.request_ref == reconciliation.request_ref &&
          value.intent_ref == source_intent_ref
        })
        is Some(request_index) else {
        raise RetryEligibilityViolation(field="terminal_source_request")
      }
      let request = snapshot.requests[request_index]
      guard snapshot.receipts.search_by(value => {
          value.receipt_ref == request.unknown_receipt_ref &&
          value.intent_ref == source_intent_ref &&
          value.outcome == Unknown
        })
        is Some(receipt_index) else {
        raise RetryEligibilityViolation(field="terminal_source_unknown")
      }
      let unknown = snapshot.receipts[receipt_index]
      Some(
        mint_effect_terminal_source_v2(
          self,
          lineage,
          state,
          reconciliation.reconciliation_ref,
          reconciliation.canonical,
          reconciliation.reconciled_at,
          snapshot.reconciliation_event_refs[reconciliation_index],
          reconciliation.evidence,
          Some(unknown.receipt_ref),
          Some(unknown.canonical),
          Some(snapshot.receipt_event_refs[receipt_index]),
          Some(request.request_ref),
          Some(request.canonical),
          Some(snapshot.request_event_refs[request_index]),
        ),
      )
    }
    _ => None
  }
}

///|
pub fn CommittedEffectTerminalSourceV2::validate_current(
  self : CommittedEffectTerminalSourceV2,
  projection : EffectsProjection,
) -> Unit raise EffectsError {
  guard projection.committed_effect_terminal_source_v2(self.source_intent_ref)
    is Some(current) else {
    raise RetryEligibilityViolation(field="terminal_source_not_current")
  }
  if current.receipt_ref != self.receipt_ref ||
    current.canonical != self.canonical ||
    current.digest != self.digest {
    raise RetryEligibilityViolation(field="terminal_source_not_current")
  }
}

///|
pub fn CommittedEffectTerminalSourceV2::receipt_ref(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn CommittedEffectTerminalSourceV2::workflow(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn CommittedEffectTerminalSourceV2::root_intent_ref(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.RecordRef {
  self.root_intent_ref
}

///|
pub fn CommittedEffectTerminalSourceV2::root_attempt_ref(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.RecordRef {
  self.root_attempt_ref
}

///|
pub fn CommittedEffectTerminalSourceV2::source_intent_ref(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.RecordRef {
  self.source_intent_ref
}

///|
pub fn CommittedEffectTerminalSourceV2::source_attempt_ref(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.RecordRef {
  self.source_attempt_ref
}

///|
pub fn CommittedEffectTerminalSourceV2::lineage_digest(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.ContentDigest {
  self.lineage_digest
}

///|
pub fn CommittedEffectTerminalSourceV2::attempt_count(
  self : CommittedEffectTerminalSourceV2,
) -> Int64 {
  self.attempt_count
}

///|
pub fn CommittedEffectTerminalSourceV2::retry_count(
  self : CommittedEffectTerminalSourceV2,
) -> Int64 {
  self.retry_count
}

///|
pub fn CommittedEffectTerminalSourceV2::state(
  self : CommittedEffectTerminalSourceV2,
) -> ReconciliationState {
  self.state
}

///|
pub fn CommittedEffectTerminalSourceV2::source_record_ref(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.RecordRef {
  self.source_record_ref
}

///|
pub fn CommittedEffectTerminalSourceV2::source_record_bytes(
  self : CommittedEffectTerminalSourceV2,
) -> Bytes {
  self.source_record_bytes
}

///|
pub fn CommittedEffectTerminalSourceV2::source_observed_at(
  self : CommittedEffectTerminalSourceV2,
) -> Int64 {
  self.source_observed_at
}

///|
pub fn CommittedEffectTerminalSourceV2::source_event_ref(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.RecordRef {
  self.source_event_ref
}

///|
pub fn CommittedEffectTerminalSourceV2::source_event_bytes(
  self : CommittedEffectTerminalSourceV2,
) -> Bytes {
  self.source_event_bytes
}

///|
pub fn CommittedEffectTerminalSourceV2::source_evidence(
  self : CommittedEffectTerminalSourceV2,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.source_evidence
}

///|
pub fn CommittedEffectTerminalSourceV2::canonical_bytes(
  self : CommittedEffectTerminalSourceV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedEffectTerminalSourceV2::digest(
  self : CommittedEffectTerminalSourceV2,
) -> @contracts.ContentDigest {
  self.digest
}
