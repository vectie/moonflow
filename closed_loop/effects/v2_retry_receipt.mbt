///|
let retry_cause_terminal_failed_v2 = "terminal_failed"

///|
let retry_cause_reconciled_not_applied_v2 = "reconciled_not_applied"

///|
priv struct RetryLineageV2 {
  root_intent_ref : @contracts.RecordRef
  root_attempt_ref : @contracts.RecordRef
  source_intent_ref : @contracts.RecordRef
  source_attempt_ref : @contracts.RecordRef
  attempt_count : Int64
  retry_count : Int64
  retry_ordinal : Int64
  digest : @contracts.ContentDigest
}

///|
/// Opaque replay-minted proof that one exact committed terminal effects state
/// may produce one retry attempt. It is not dispatch or application authority.
///
/// Construction is package-private. There is no public constructor or decoder.
pub struct CommittedRetryEligibilityReceiptV2 {
  receipt_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  root_intent_ref : @contracts.RecordRef
  root_attempt_ref : @contracts.RecordRef
  source_intent_ref : @contracts.RecordRef
  source_attempt_ref : @contracts.RecordRef
  lineage_digest : @contracts.ContentDigest
  attempt_count : Int64
  retry_count : Int64
  retry_ordinal : Int64
  cause_key : String
  source_record_ref : @contracts.RecordRef
  source_record_digest : @contracts.ContentDigest
  source_observed_at : Int64
  source_event_ref : @contracts.RecordRef
  source_event_digest : @contracts.ContentDigest
  unknown_receipt_ref : @contracts.RecordRef?
  unknown_receipt_digest : @contracts.ContentDigest?
  unknown_receipt_event_ref : @contracts.RecordRef?
  reconciliation_request_ref : @contracts.RecordRef?
  reconciliation_request_digest : @contracts.ContentDigest?
  reconciliation_request_event_ref : @contracts.RecordRef?
  projection_sequence : Int64
  projection_revision : Int64
  projection_head_digest : @contracts.ContentDigest
  projection_state_digest : @contracts.ContentDigest
  projection_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn write_optional_digest_v2(
  writer : EffectsWriter,
  value : @contracts.ContentDigest?,
) -> Unit raise EffectsError {
  match value {
    None => writer.byte(0)
    Some(digest) => {
      writer.byte(1)
      writer.string(digest.text())
    }
  }
}

///|
fn mint_retry_receipt_v2(
  projection : EffectsProjection,
  lineage : RetryLineageV2,
  cause_key : String,
  source_record_ref : @contracts.RecordRef,
  source_observed_at : Int64,
  source_event_ref : @contracts.RecordRef,
  unknown_receipt_ref : @contracts.RecordRef?,
  unknown_receipt_event_ref : @contracts.RecordRef?,
  reconciliation_request_ref : @contracts.RecordRef?,
  reconciliation_request_event_ref : @contracts.RecordRef?,
) -> CommittedRetryEligibilityReceiptV2 raise EffectsError {
  if source_observed_at < 0L {
    raise RetryEligibilityViolation(field="retry_source_observed_at")
  }
  guard projection.last_event_digest is Some(projection_head_digest) else {
    raise RetryEligibilityViolation(field="retry_projection_head_missing")
  }
  guard projection.replay_digest is Some(projection_replay_digest) else {
    raise RetryEligibilityViolation(field="retry_projection_replay_missing")
  }
  let source_record_digest = source_record_ref.digest()
  let source_event_digest = source_event_ref.digest()
  let unknown_receipt_digest = unknown_receipt_ref.map(value => value.digest())
  let reconciliation_request_digest = reconciliation_request_ref.map(value => {
    value.digest()
  })
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6/COMMITTED-RETRY-ELIGIBILITY-RECEIPT-V2/2.0.0")
  writer.string(effects_record_version)
  write_ref(writer, projection.workflow)
  write_ref(writer, lineage.root_intent_ref)
  write_ref(writer, lineage.root_attempt_ref)
  write_ref(writer, lineage.source_intent_ref)
  write_ref(writer, lineage.source_attempt_ref)
  writer.string(lineage.digest.text())
  writer.int64(lineage.attempt_count)
  writer.int64(lineage.retry_count)
  writer.int64(lineage.retry_ordinal)
  writer.string(cause_key)
  write_ref(writer, source_record_ref)
  writer.string(source_record_digest.text())
  writer.int64(source_observed_at)
  write_ref(writer, source_event_ref)
  writer.string(source_event_digest.text())
  write_optional_ref(writer, unknown_receipt_ref)
  write_optional_digest_v2(writer, unknown_receipt_digest)
  write_optional_ref(writer, unknown_receipt_event_ref)
  write_optional_ref(writer, reconciliation_request_ref)
  write_optional_digest_v2(writer, reconciliation_request_digest)
  write_optional_ref(writer, reconciliation_request_event_ref)
  writer.int64(projection.sequence)
  writer.int64(projection.revision)
  writer.string(projection_head_digest.text())
  writer.string(projection.state_digest.text())
  writer.string(projection_replay_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref(
      "committed-retry-eligibility-receipt-v2",
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
    retry_ordinal: lineage.retry_ordinal,
    cause_key,
    source_record_ref,
    source_record_digest,
    source_observed_at,
    source_event_ref,
    source_event_digest,
    unknown_receipt_ref,
    unknown_receipt_digest,
    unknown_receipt_event_ref,
    reconciliation_request_ref,
    reconciliation_request_digest,
    reconciliation_request_event_ref,
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

///|
/// Mint only from an exact terminal state retained by authoritative replay.
/// A source already consumed by a committed child attempt has no receipt.
pub fn EffectsProjection::committed_retry_eligibility_receipt(
  self : EffectsProjection,
  source_intent_ref : @contracts.RecordRef,
) -> CommittedRetryEligibilityReceiptV2? raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "retry_requires_strict_replay",
  )
  guard first(snapshot.intents, value => value.intent_ref == source_intent_ref)
    is Some(_) else {
    raise IdentityMismatch(field="retry_source_intent")
  }
  if snapshot.attempts.any(value => {
      value.retry_of_intent_ref == Some(source_intent_ref)
    }) {
    return None
  }
  let lineage = snapshot.retry_lineage(source_intent_ref)
  match snapshot.state_for(source_intent_ref) {
    KnownFailure => {
      guard snapshot.receipts.search_by(value => {
          value.intent_ref == source_intent_ref && value.outcome == Failed
        })
        is Some(receipt_index) else {
        raise RetryEligibilityViolation(field="retry_failed_receipt_missing")
      }
      let receipt = snapshot.receipts[receipt_index]
      Some(
        mint_retry_receipt_v2(
          self,
          lineage,
          retry_cause_terminal_failed_v2,
          receipt.receipt_ref,
          receipt.observed_at,
          snapshot.receipt_event_refs[receipt_index],
          None,
          None,
          None,
          None,
        ),
      )
    }
    ReconciledFailureState | ReconciledNotAppliedRetryEligible => {
      let expected_resolution = if snapshot.state_for(source_intent_ref) ==
        ReconciledFailureState {
        ReconciledFailed
      } else {
        ReconciledNotApplied
      }
      let cause_key = if snapshot.state_for(source_intent_ref) ==
        ReconciledFailureState {
        retry_cause_terminal_failed_v2
      } else {
        retry_cause_reconciled_not_applied_v2
      }
      guard snapshot.reconciliations.search_by(value => {
          value.intent_ref == source_intent_ref &&
          value.resolution == expected_resolution
        })
        is Some(reconciliation_index) else {
        raise RetryEligibilityViolation(
          field="retry_reconciliation_record_missing",
        )
      }
      let reconciliation = snapshot.reconciliations[reconciliation_index]
      guard snapshot.requests.search_by(value => {
          value.request_ref == reconciliation.request_ref &&
          value.intent_ref == source_intent_ref
        })
        is Some(request_index) else {
        raise RetryEligibilityViolation(
          field="retry_reconciliation_request_missing",
        )
      }
      let request = snapshot.requests[request_index]
      guard snapshot.receipts.search_by(value => {
          value.receipt_ref == request.unknown_receipt_ref &&
          value.intent_ref == source_intent_ref &&
          value.outcome == Unknown
        })
        is Some(receipt_index) else {
        raise RetryEligibilityViolation(field="retry_unknown_receipt_missing")
      }
      let unknown = snapshot.receipts[receipt_index]
      Some(
        mint_retry_receipt_v2(
          self,
          lineage,
          cause_key,
          reconciliation.reconciliation_ref,
          reconciliation.reconciled_at,
          snapshot.reconciliation_event_refs[reconciliation_index],
          Some(unknown.receipt_ref),
          Some(snapshot.receipt_event_refs[receipt_index]),
          Some(request.request_ref),
          Some(snapshot.request_event_refs[request_index]),
        ),
      )
    }
    _ => None
  }
}

///|
fn CommittedRetryEligibilityReceiptV2::require_integrity(
  self : CommittedRetryEligibilityReceiptV2,
) -> Unit raise EffectsError {
  if @contracts.sha256_digest(self.canonical) != self.digest ||
    self.receipt_ref.digest() != self.digest ||
    self.source_record_ref.digest() != self.source_record_digest ||
    self.source_event_ref.digest() != self.source_event_digest {
    raise DigestMismatch(field="retry_receipt_v2_integrity")
  }
  if self.cause_key != retry_cause_terminal_failed_v2 &&
    self.cause_key != retry_cause_reconciled_not_applied_v2 {
    raise RetryEligibilityViolation(field="retry_receipt_v2_cause")
  }
}

///|
/// Validate against the exact current authoritative projection. This receipt
/// becomes stale after any committed state change and disappears after use.
pub fn CommittedRetryEligibilityReceiptV2::validate_current(
  self : CommittedRetryEligibilityReceiptV2,
  projection : EffectsProjection,
) -> Unit raise EffectsError {
  self.require_integrity()
  if self.workflow != projection.workflow() {
    raise IdentityMismatch(field="retry_receipt_v2_workflow")
  }
  if self.projection_revision != projection.revision() {
    raise RevisionMismatch(
      expected=self.projection_revision,
      actual=projection.revision(),
    )
  }
  if self.projection_sequence != projection.sequence() {
    raise OrderingViolation(field="retry_receipt_v2_sequence")
  }
  if self.projection_state_digest != projection.state_digest() {
    raise DigestMismatch(field="retry_receipt_v2_projection_state")
  }
  if projection.last_event_digest() != Some(self.projection_head_digest) {
    raise DigestMismatch(field="retry_receipt_v2_projection_head")
  }
  if projection.replay_digest != Some(self.projection_replay_digest) {
    raise DigestMismatch(field="retry_receipt_v2_projection_replay")
  }
  guard projection.committed_retry_eligibility_receipt(self.source_intent_ref)
    is Some(current) else {
    raise RetryEligibilityViolation(field="retry_receipt_v2_not_current")
  }
  if current.receipt_ref != self.receipt_ref ||
    current.digest != self.digest ||
    current.canonical != self.canonical {
    raise RetryEligibilityViolation(field="retry_receipt_v2_replaced")
  }
}

///|
pub fn CommittedRetryEligibilityReceiptV2::receipt_ref(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn CommittedRetryEligibilityReceiptV2::workflow(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn CommittedRetryEligibilityReceiptV2::root_intent_ref(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.RecordRef {
  self.root_intent_ref
}

///|
pub fn CommittedRetryEligibilityReceiptV2::root_attempt_ref(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.RecordRef {
  self.root_attempt_ref
}

///|
pub fn CommittedRetryEligibilityReceiptV2::source_intent_ref(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.RecordRef {
  self.source_intent_ref
}

///|
pub fn CommittedRetryEligibilityReceiptV2::source_attempt_ref(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.RecordRef {
  self.source_attempt_ref
}

///|
pub fn CommittedRetryEligibilityReceiptV2::lineage_digest(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.ContentDigest {
  self.lineage_digest
}

///|
pub fn CommittedRetryEligibilityReceiptV2::attempt_count(
  self : CommittedRetryEligibilityReceiptV2,
) -> Int64 {
  self.attempt_count
}

///|
pub fn CommittedRetryEligibilityReceiptV2::retry_count(
  self : CommittedRetryEligibilityReceiptV2,
) -> Int64 {
  self.retry_count
}

///|
pub fn CommittedRetryEligibilityReceiptV2::retry_ordinal(
  self : CommittedRetryEligibilityReceiptV2,
) -> Int64 {
  self.retry_ordinal
}

///|
pub fn CommittedRetryEligibilityReceiptV2::cause_key(
  self : CommittedRetryEligibilityReceiptV2,
) -> String {
  self.cause_key
}

///|
pub fn CommittedRetryEligibilityReceiptV2::source_record_ref(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.RecordRef {
  self.source_record_ref
}

///|
pub fn CommittedRetryEligibilityReceiptV2::source_observed_at(
  self : CommittedRetryEligibilityReceiptV2,
) -> Int64 {
  self.source_observed_at
}

///|
pub fn CommittedRetryEligibilityReceiptV2::source_event_ref(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.RecordRef {
  self.source_event_ref
}

///|
pub fn CommittedRetryEligibilityReceiptV2::source_event_digest(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.ContentDigest {
  self.source_event_digest
}

///|
pub fn CommittedRetryEligibilityReceiptV2::projection_sequence(
  self : CommittedRetryEligibilityReceiptV2,
) -> Int64 {
  self.projection_sequence
}

///|
pub fn CommittedRetryEligibilityReceiptV2::projection_revision(
  self : CommittedRetryEligibilityReceiptV2,
) -> Int64 {
  self.projection_revision
}

///|
pub fn CommittedRetryEligibilityReceiptV2::projection_head_digest(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.ContentDigest {
  self.projection_head_digest
}

///|
pub fn CommittedRetryEligibilityReceiptV2::projection_state_digest(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.ContentDigest {
  self.projection_state_digest
}

///|
pub fn CommittedRetryEligibilityReceiptV2::projection_replay_digest(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.ContentDigest {
  self.projection_replay_digest
}

///|
pub fn CommittedRetryEligibilityReceiptV2::canonical_bytes(
  self : CommittedRetryEligibilityReceiptV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedRetryEligibilityReceiptV2::digest(
  self : CommittedRetryEligibilityReceiptV2,
) -> @contracts.ContentDigest {
  self.digest
}
