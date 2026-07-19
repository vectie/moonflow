///|
let cancellation_proposed_event_kind_v22 = "cancellation.proposed.v2"

///|
let cancellation_authorized_event_kind_v22 = "cancellation.authorized.v2"

///|
let cancellation_requested_event_kind_v22 = "work.cancellation.requested.v2"

///|
let work_terminal_event_kind_v22 = "work.terminal.v2"

///|
pub(all) enum WorkTerminalOutcomeV2 {
  SucceededV2
  FailedNonRetryableV2
  FailedRetryExhaustedV2
  FailedCancellationStoppedRetryV2
  CancelledBeforeEffectIntentV2
  CancelledAfterReconciledNotAppliedV2
} derive(Eq, Debug)

///|
fn WorkTerminalOutcomeV2::wire(self : WorkTerminalOutcomeV2) -> String {
  match self {
    SucceededV2 => "succeeded_v2"
    FailedNonRetryableV2 => "failed_non_retryable_v2"
    FailedRetryExhaustedV2 => "failed_retry_exhausted_v2"
    FailedCancellationStoppedRetryV2 => "failed_cancellation_stopped_retry_v2"
    CancelledBeforeEffectIntentV2 => "cancelled_before_effect_intent_v2"
    CancelledAfterReconciledNotAppliedV2 =>
      "cancelled_after_reconciled_not_applied_v2"
  }
}

///|
fn decode_terminal_outcome_v22(
  value : String,
) -> WorkTerminalOutcomeV2 raise OrchestrationError {
  match value {
    "succeeded_v2" => SucceededV2
    "failed_non_retryable_v2" => FailedNonRetryableV2
    "failed_retry_exhausted_v2" => FailedRetryExhaustedV2
    "failed_cancellation_stopped_retry_v2" => FailedCancellationStoppedRetryV2
    "cancelled_before_effect_intent_v2" => CancelledBeforeEffectIntentV2
    "cancelled_after_reconciled_not_applied_v2" =>
      CancelledAfterReconciledNotAppliedV2
    _ => raise MalformedInput(field="work_terminal_outcome_v22")
  }
}

///|
priv struct CancellationProposalFoundationV2 {
  proposal_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  reason_ref : @contracts.RecordRef
  observed_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  idempotency_key : String
  previous_digest : @contracts.ContentDigest?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn new_cancellation_proposal_foundation_v22(
  proposal_id : String,
  workflow : @contracts.RecordRef,
  schedule_registration_ref : @contracts.RecordRef,
  reason_ref : @contracts.RecordRef,
  observed_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  idempotency_key : String,
  previous_digest? : @contracts.ContentDigest,
) -> CancellationProposalFoundationV2 raise OrchestrationError {
  require_text(proposal_id, "cancellation_proposal_v22_id")
  require_text(idempotency_key, "cancellation_proposal_v22_idempotency")
  require_utc_millis_v22(observed_at, "cancellation_proposal_v22_observed_at")
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CANCELLATION-PROPOSAL-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(proposal_id)
  write_ref(writer, workflow)
  write_ref(writer, schedule_registration_ref)
  write_ref(writer, reason_ref)
  writer.int64(observed_at)
  write_evidence(writer, evidence)
  write_ref(writer, causation)
  writer.string(idempotency_key)
  writer.optional_digest(previous_digest)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    proposal_ref: self_ref_v22(
      "orchestration-cancellation-proposal-v2", proposal_id, digest,
    ),
    workflow,
    schedule_registration_ref,
    reason_ref,
    observed_at,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    causation,
    idempotency_key,
    previous_digest,
    canonical,
    digest,
  }
}

///|
fn decode_cancellation_proposal_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> CancellationProposalFoundationV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/CANCELLATION-PROPOSAL-V2/2.2.0" {
    raise MalformedInput(field="cancellation_proposal_v22_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="cancellation_proposal_v22", version~)
  }
  let id = reader.read_string()
  let workflow = reader.read_ref()
  let registration = reader.read_ref()
  let reason = reader.read_ref()
  let observed_at = reader.read_int64()
  let evidence = reader.read_evidence()
  let causation = reader.read_ref()
  let key = reader.read_string()
  let previous_digest = reader.read_optional_digest()
  reader.require_end()
  let decoded = new_cancellation_proposal_foundation_v22(
    id,
    workflow,
    registration,
    reason,
    observed_at,
    evidence,
    causation,
    key,
    previous_digest?,
  )
  if decoded.proposal_ref != expected_ref || decoded.canonical != bytes {
    raise DigestMismatch(field="cancellation_proposal_v22_expected_ref")
  }
  decoded
}

///|
fn CancellationProposalFoundationV2::proposal_ref(
  self : CancellationProposalFoundationV2,
) -> @contracts.RecordRef {
  self.proposal_ref
}

///|
fn CancellationProposalFoundationV2::canonical_bytes(
  self : CancellationProposalFoundationV2,
) -> Bytes {
  self.canonical
}

///|
priv struct CancellationAuthorizationFoundationV2 {
  authorization_ref : @contracts.RecordRef
  proposal_ref : @contracts.RecordRef
  proposal_digest : @contracts.ContentDigest
  proposal_bytes : Bytes
  observed_at : Int64
  valid_until_inclusive : Int64
  deadline_exclusive : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  idempotency_key : String
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
// Package-private codec foundation only. It does not authorize cancellation
// and is not reachable from the public interface. A later slice may invoke it
// only after validating an opaque replay-minted governance receipt.
fn new_cancellation_authorization_v22(
  authorization_id : String,
  proposal : CancellationProposalFoundationV2,
  authority_requested_at : Int64,
  authority_decided_at : Int64,
  review_requested_at : Int64,
  review_decided_at : Int64,
  review_bound_at : Int64,
  governance_valid_until_inclusive : Int64,
  request_deadline_exclusive : Int64?,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  idempotency_key : String,
) -> CancellationAuthorizationFoundationV2 raise OrchestrationError {
  require_text(authorization_id, "cancellation_authorization_v22_id")
  require_text(idempotency_key, "cancellation_authorization_v22_idempotency")
  let (observed_at, valid_until_inclusive, deadline_exclusive) = cancellation_authorization_times_v22(
    proposal.observed_at,
    authority_requested_at,
    authority_decided_at,
    review_requested_at,
    review_decided_at,
    review_bound_at,
    governance_valid_until_inclusive,
    request_deadline_exclusive,
  )
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CANCELLATION-AUTHORIZATION-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(authorization_id)
  write_ref(writer, proposal.proposal_ref)
  writer.bytes(@utf8.encode(proposal.digest.text()))
  writer.bytes(proposal.canonical)
  writer.int64(observed_at)
  writer.int64(valid_until_inclusive)
  writer.int64(deadline_exclusive)
  write_evidence(writer, evidence)
  write_ref(writer, causation)
  writer.string(idempotency_key)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    authorization_ref: self_ref_v22(
      "orchestration-cancellation-authorization-v2", authorization_id, digest,
    ),
    proposal_ref: proposal.proposal_ref,
    proposal_digest: proposal.digest,
    proposal_bytes: proposal.canonical,
    observed_at,
    valid_until_inclusive,
    deadline_exclusive,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    causation,
    idempotency_key,
    canonical,
    digest,
  }
}

///|
fn CancellationAuthorizationFoundationV2::authorization_ref(
  self : CancellationAuthorizationFoundationV2,
) -> @contracts.RecordRef {
  self.authorization_ref
}

///|
fn CancellationAuthorizationFoundationV2::canonical_bytes(
  self : CancellationAuthorizationFoundationV2,
) -> Bytes {
  self.canonical
}

///|
fn CancellationAuthorizationFoundationV2::deadline_exclusive(
  self : CancellationAuthorizationFoundationV2,
) -> Int64 {
  self.deadline_exclusive
}

///|
priv struct CancellationRequestFoundationV2 {
  request_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  proposal_ref : @contracts.RecordRef
  authorization_ref : @contracts.RecordRef
  observed_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  idempotency_key : String
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
// Package-private record foundation only. A public cancellation command must
// consume a current opaque governance receipt and aggregate guard in a later
// reviewed slice; raw authorization values never cross this boundary.
fn new_cancellation_request_v22(
  request_id : String,
  workflow : @contracts.RecordRef,
  proposal : CancellationProposalFoundationV2,
  authorization : CancellationAuthorizationFoundationV2,
  observed_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  idempotency_key : String,
) -> CancellationRequestFoundationV2 raise OrchestrationError {
  require_text(request_id, "cancellation_request_v22_id")
  require_text(idempotency_key, "cancellation_request_v22_idempotency")
  require_utc_millis_v22(observed_at, "cancellation_request_v22_observed_at")
  if proposal.workflow != workflow ||
    authorization.proposal_ref != proposal.proposal_ref ||
    authorization.proposal_digest != proposal.digest ||
    authorization.proposal_bytes != proposal.canonical {
    raise ReplayBindingViolation(field="cancellation_request_v22_chain")
  }
  if observed_at >= authorization.deadline_exclusive {
    raise AuthorityExpired(
      expires_at=authorization.valid_until_inclusive,
      observed_at~,
    )
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CANCELLATION-REQUEST-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(request_id)
  write_ref(writer, workflow)
  write_ref(writer, proposal.proposal_ref)
  writer.bytes(proposal.canonical)
  write_ref(writer, authorization.authorization_ref)
  writer.bytes(authorization.canonical)
  writer.int64(observed_at)
  write_evidence(writer, evidence)
  write_ref(writer, causation)
  writer.string(idempotency_key)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    request_ref: self_ref_v22(
      "orchestration-cancellation-request-v2", request_id, digest,
    ),
    workflow,
    proposal_ref: proposal.proposal_ref,
    authorization_ref: authorization.authorization_ref,
    observed_at,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    causation,
    idempotency_key,
    canonical,
    digest,
  }
}

///|
fn CancellationRequestFoundationV2::request_ref(
  self : CancellationRequestFoundationV2,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
fn CancellationRequestFoundationV2::canonical_bytes(
  self : CancellationRequestFoundationV2,
) -> Bytes {
  self.canonical
}

///|
// Internal codec scaffold only. This deliberately is not WorkTerminalRecordV2
// and is absent from the public interface: the accepted terminal record also
// requires source proof/event, full lineage, effects/orchestration prefix
// digests, counters/policy, and cancellation bindings. Those mandatory fields
// and replay-minted receipt are deferred together rather than exposing a
// semantically incomplete terminal record.
priv struct WorkTerminalFoundationV2 {
  terminal_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  outcome : WorkTerminalOutcomeV2
  observed_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  idempotency_key : String
  previous_digest : @contracts.ContentDigest?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn new_work_terminal_foundation_v22(
  terminal_id : String,
  workflow : @contracts.RecordRef,
  schedule_registration_ref : @contracts.RecordRef,
  outcome : WorkTerminalOutcomeV2,
  observed_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  idempotency_key : String,
  previous_digest? : @contracts.ContentDigest,
) -> WorkTerminalFoundationV2 raise OrchestrationError {
  require_text(terminal_id, "work_terminal_v22_id")
  require_text(idempotency_key, "work_terminal_v22_idempotency")
  require_utc_millis_v22(observed_at, "work_terminal_v22_observed_at")
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/WORK-TERMINAL-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(terminal_id)
  write_ref(writer, workflow)
  write_ref(writer, schedule_registration_ref)
  writer.string(outcome.wire())
  writer.int64(observed_at)
  write_evidence(writer, evidence)
  write_ref(writer, causation)
  writer.string(idempotency_key)
  writer.optional_digest(previous_digest)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    terminal_ref: self_ref_v22(
      "orchestration-work-terminal-v2", terminal_id, digest,
    ),
    workflow,
    schedule_registration_ref,
    outcome,
    observed_at,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    causation,
    idempotency_key,
    previous_digest,
    canonical,
    digest,
  }
}

///|
fn decode_work_terminal_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> WorkTerminalFoundationV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/WORK-TERMINAL-V2/2.2.0" {
    raise MalformedInput(field="work_terminal_v22_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="work_terminal_v22", version~)
  }
  let id = reader.read_string()
  let workflow = reader.read_ref()
  let registration = reader.read_ref()
  let outcome = decode_terminal_outcome_v22(reader.read_string())
  let observed_at = reader.read_int64()
  let evidence = reader.read_evidence()
  let causation = reader.read_ref()
  let key = reader.read_string()
  let previous_digest = reader.read_optional_digest()
  reader.require_end()
  let decoded = new_work_terminal_foundation_v22(
    id,
    workflow,
    registration,
    outcome,
    observed_at,
    evidence,
    causation,
    key,
    previous_digest?,
  )
  if decoded.terminal_ref != expected_ref || decoded.canonical != bytes {
    raise DigestMismatch(field="work_terminal_v22_expected_ref")
  }
  decoded
}

///|
fn WorkTerminalFoundationV2::terminal_ref(
  self : WorkTerminalFoundationV2,
) -> @contracts.RecordRef {
  self.terminal_ref
}

///|
fn WorkTerminalFoundationV2::outcome(
  self : WorkTerminalFoundationV2,
) -> WorkTerminalOutcomeV2 {
  self.outcome
}

///|
fn WorkTerminalFoundationV2::canonical_bytes(
  self : WorkTerminalFoundationV2,
) -> Bytes {
  self.canonical
}
