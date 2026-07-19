///|
let cancellation_authorization_record_kind_v22 = "orchestration-cancellation-authorization-v2"

///|
let cancellation_request_record_kind_v22 = "orchestration-cancellation-request-v2"

///|
/// Proposal-scoped cancellation control proof derived only from a current,
/// replay-minted committed governance receipt. It never names a final request.
pub struct CancellationAuthorizationV2 {
  authorization_ref : @contracts.RecordRef
  proposal : CancellationProposalV2
  governance_receipt : CommittedCancellationGovernanceReceiptV2
  workflow : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  observed_at : Int64
  effective_valid_until_inclusive : Int64
  deadline_exclusive : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn cancellation_authorization_signing_bytes_v22(
  authorization_id : String,
  receipt : CommittedCancellationGovernanceReceiptV2,
  proposal : CancellationProposalV2,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CANCELLATION-AUTHORIZATION-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(authorization_id)
  write_phase1b_record_v22(writer, proposal.proposal_ref, proposal.canonical)
  write_phase1b_record_v22(writer, receipt.record_ref, receipt.canonical)
  write_ref(writer, proposal.workflow)
  write_ref(writer, proposal.governed_subject)
  write_ref(writer, receipt.governance_stream_ref)
  writer.int64(receipt.work_sequence)
  writer.int64(receipt.work_revision)
  writer.string(receipt.work_head_digest.text())
  writer.string(receipt.work_replay_digest.text())
  writer.int64(receipt.governance_sequence)
  writer.int64(receipt.governance_revision)
  writer.string(receipt.governance_head_digest.text())
  writer.string(receipt.governance_replay_digest.text())
  writer.int64(receipt.observed_at)
  writer.int64(receipt.effective_valid_until_inclusive)
  writer.int64(receipt.deadline_exclusive)
  writer.finish()
}

///|
fn build_cancellation_authorization_v22(
  authorization_id : String,
  receipt : CommittedCancellationGovernanceReceiptV2,
  proposal : CancellationProposalV2,
) -> CancellationAuthorizationV2 raise OrchestrationError {
  phase1b_require_short_text_v22(
    authorization_id, "cancellation_authorization_id",
  )
  let request_time_invalid = match receipt.request_deadline_exclusive {
    Some(request_deadline_exclusive) =>
      receipt.observed_at >= request_deadline_exclusive
    None => false
  }
  if receipt.observed_at >= receipt.deadline_exclusive ||
    receipt.effective_valid_until_inclusive + 1L != receipt.deadline_exclusive ||
    request_time_invalid {
    raise ReplayBindingViolation(
      field="cancellation_authorization_time_binding",
    )
  }
  if receipt.proposal.proposal_ref != proposal.proposal_ref ||
    receipt.proposal.digest != proposal.digest ||
    receipt.proposal.canonical != proposal.canonical ||
    receipt.proposal.governed_subject != proposal.governed_subject {
    raise ReplayBindingViolation(
      field="cancellation_authorization_proposal_binding",
    )
  }
  let canonical = cancellation_authorization_signing_bytes_v22(
    authorization_id, receipt, proposal,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    authorization_ref: self_ref_v22(
      cancellation_authorization_record_kind_v22, authorization_id, digest,
    ),
    proposal,
    governance_receipt: receipt,
    workflow: proposal.workflow,
    governed_subject: proposal.governed_subject,
    observed_at: receipt.observed_at,
    effective_valid_until_inclusive: receipt.effective_valid_until_inclusive,
    deadline_exclusive: receipt.deadline_exclusive,
    canonical,
    digest,
  }
}

///|
pub fn CancellationAuthorizationV2::from_committed_governance(
  authorization_id : String,
  receipt : CommittedCancellationGovernanceReceiptV2,
  proposal : CancellationProposalV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> CancellationAuthorizationV2 raise OrchestrationError {
  receipt.validate_current(current)
  require_proposal_current_v22(proposal, current)
  build_cancellation_authorization_v22(authorization_id, receipt, proposal)
}

///|
/// Phase-2-only authorization over an exact historical proposal. Governance
/// still binds the activated pre-claim work head; only proposal currentness is
/// checked against its own storage-verified historical prefix.
fn CancellationAuthorizationV2::from_historical_proposal_v3(
  authorization_id : String,
  receipt : CommittedCancellationGovernanceReceiptV2,
  proposal : CancellationProposalV2,
  authorization_current : CurrentGovernedClosedLoopProjectionV2,
  proposal_current : CurrentGovernedClosedLoopProjectionV2,
) -> CancellationAuthorizationV2 raise OrchestrationError {
  require_proposal_current_v22(proposal, proposal_current)
  let replayed = authorization_current.mint_committed_cancellation_governance_receipt_v22(
    proposal,
  )
  if replayed.record_ref != receipt.record_ref ||
    replayed.canonical != receipt.canonical ||
    replayed.governance_head_digest != receipt.governance_head_digest ||
    replayed.governance_replay_digest != receipt.governance_replay_digest ||
    replayed.work_head_digest != receipt.work_head_digest ||
    replayed.work_replay_digest != receipt.work_replay_digest {
    raise ReplayBindingViolation(
      field="cancellation_governance_receipt_not_current",
    )
  }
  build_cancellation_authorization_v22(authorization_id, receipt, proposal)
}

///|
fn decode_cancellation_authorization_at_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
  current : CurrentGovernedClosedLoopProjectionV2,
  historical_proposal_current : CurrentGovernedClosedLoopProjectionV2?,
) -> CancellationAuthorizationV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/CANCELLATION-AUTHORIZATION-V2/2.2.0" {
    raise MalformedInput(field="cancellation_authorization_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="cancellation_authorization", version~)
  }
  let authorization_id = reader.read_string()
  let (proposal_ref, proposal_bytes) = read_phase1b_record_v22(reader)
  let proposal = decode_cancellation_proposal_v22_strict(
    proposal_ref, proposal_bytes,
  )
  let (receipt_ref, receipt_bytes) = read_phase1b_record_v22(reader)
  let receipt = decode_committed_cancellation_governance_receipt_at_v22(
    receipt_ref, receipt_bytes, current, historical_proposal_current,
  )
  ignore(reader.read_ref())
  ignore(reader.read_ref())
  ignore(reader.read_ref())
  for _ in 0..<2 {
    ignore(reader.read_int64())
  }
  for _ in 0..<2 {
    ignore(reader.read_digest())
  }
  for _ in 0..<2 {
    ignore(reader.read_int64())
  }
  for _ in 0..<2 {
    ignore(reader.read_digest())
  }
  for _ in 0..<3 {
    ignore(reader.read_int64())
  }
  reader.require_end()
  let decoded = match historical_proposal_current {
    None =>
      CancellationAuthorizationV2::from_committed_governance(
        authorization_id, receipt, proposal, current,
      )
    Some(proposal_current) =>
      CancellationAuthorizationV2::from_historical_proposal_v3(
        authorization_id, receipt, proposal, current, proposal_current,
      )
  }
  if decoded.authorization_ref != expected_ref ||
    decoded.canonical != bytes ||
    expected_ref.kind() != cancellation_authorization_record_kind_v22 ||
    expected_ref.version().text() != orchestration_record_version_v22 {
    raise ReplayBindingViolation(
      field="cancellation_authorization_proposal_binding",
    )
  }
  decoded
}

///|
fn decode_cancellation_authorization_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> CancellationAuthorizationV2 raise OrchestrationError {
  decode_cancellation_authorization_at_v22(expected_ref, bytes, current, None)
}

///|
pub fn CancellationAuthorizationV2::record_ref(
  self : CancellationAuthorizationV2,
) -> @contracts.RecordRef {
  self.authorization_ref
}

///|
pub fn CancellationAuthorizationV2::digest(
  self : CancellationAuthorizationV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn CancellationAuthorizationV2::canonical_bytes(
  self : CancellationAuthorizationV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CancellationAuthorizationV2::observed_at(
  self : CancellationAuthorizationV2,
) -> Int64 {
  self.observed_at
}

///|
pub fn CancellationAuthorizationV2::effective_valid_until_inclusive(
  self : CancellationAuthorizationV2,
) -> Int64 {
  self.effective_valid_until_inclusive
}

///|
pub fn CancellationAuthorizationV2::deadline_exclusive(
  self : CancellationAuthorizationV2,
) -> Int64 {
  self.deadline_exclusive
}

///|
/// Inert, cycle-free composite binding of one exact proposal and its exact
/// proposal-scoped authorization. It performs no mutation.
pub struct CancellationRequestV2 {
  request_ref : @contracts.RecordRef
  proposal : CancellationProposalV2
  authorization : CancellationAuthorizationV2
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn cancellation_request_signing_bytes_v22(
  request_id : String,
  proposal : CancellationProposalV2,
  authorization : CancellationAuthorizationV2,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CANCELLATION-REQUEST-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(request_id)
  write_phase1b_record_v22(writer, proposal.proposal_ref, proposal.canonical)
  write_phase1b_record_v22(
    writer,
    authorization.authorization_ref,
    authorization.canonical,
  )
  writer.finish()
}

///|
pub fn CancellationRequestV2::new(
  request_id : String,
  proposal : CancellationProposalV2,
  authorization : CancellationAuthorizationV2,
) -> CancellationRequestV2 raise OrchestrationError {
  phase1b_require_short_text_v22(request_id, "cancellation_request_id")
  if authorization.proposal.proposal_ref != proposal.proposal_ref ||
    authorization.proposal.digest != proposal.digest ||
    authorization.proposal.canonical != proposal.canonical ||
    authorization.workflow != proposal.workflow ||
    authorization.governed_subject != proposal.governed_subject {
    raise ReplayBindingViolation(field="cancellation_request_composite_binding")
  }
  let canonical = cancellation_request_signing_bytes_v22(
    request_id, proposal, authorization,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    request_ref: self_ref_v22(
      cancellation_request_record_kind_v22, request_id, digest,
    ),
    proposal,
    authorization,
    canonical,
    digest,
  }
}

///|
fn decode_cancellation_request_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> CancellationRequestV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/CANCELLATION-REQUEST-V2/2.2.0" {
    raise MalformedInput(field="cancellation_request_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="cancellation_request", version~)
  }
  let request_id = reader.read_string()
  let (proposal_ref, proposal_bytes) = read_phase1b_record_v22(reader)
  let proposal = decode_cancellation_proposal_v22_strict(
    proposal_ref, proposal_bytes,
  )
  let (authorization_ref, authorization_bytes) = read_phase1b_record_v22(reader)
  let authorization = decode_cancellation_authorization_v22(
    authorization_ref, authorization_bytes, current,
  )
  reader.require_end()
  let decoded = CancellationRequestV2::new(request_id, proposal, authorization)
  if decoded.request_ref != expected_ref ||
    decoded.canonical != bytes ||
    expected_ref.kind() != cancellation_request_record_kind_v22 ||
    expected_ref.version().text() != orchestration_record_version_v22 {
    raise ReplayBindingViolation(field="cancellation_request_composite_binding")
  }
  decoded
}

///|
fn decode_historical_cancellation_request_v3(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
  authorization_current : CurrentGovernedClosedLoopProjectionV2,
  proposal_current : CurrentGovernedClosedLoopProjectionV2,
) -> CancellationRequestV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/CANCELLATION-REQUEST-V2/2.2.0" {
    raise MalformedInput(field="cancellation_request_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="cancellation_request", version~)
  }
  let request_id = reader.read_string()
  let (proposal_ref, proposal_bytes) = read_phase1b_record_v22(reader)
  let proposal = decode_cancellation_proposal_v22_strict(
    proposal_ref, proposal_bytes,
  )
  let (authorization_ref, authorization_bytes) = read_phase1b_record_v22(reader)
  let authorization = decode_cancellation_authorization_at_v22(
    authorization_ref,
    authorization_bytes,
    authorization_current,
    Some(proposal_current),
  )
  reader.require_end()
  let decoded = CancellationRequestV2::new(request_id, proposal, authorization)
  if decoded.request_ref != expected_ref ||
    decoded.canonical != bytes ||
    expected_ref.kind() != cancellation_request_record_kind_v22 ||
    expected_ref.version().text() != orchestration_record_version_v22 {
    raise ReplayBindingViolation(field="cancellation_request_composite_binding")
  }
  decoded
}

///|
pub fn CancellationRequestV2::record_ref(
  self : CancellationRequestV2,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn CancellationRequestV2::digest(
  self : CancellationRequestV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn CancellationRequestV2::canonical_bytes(
  self : CancellationRequestV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CancellationRequestV2::proposal_ref(
  self : CancellationRequestV2,
) -> @contracts.RecordRef {
  self.proposal.proposal_ref
}

///|
pub fn CancellationRequestV2::authorization_ref(
  self : CancellationRequestV2,
) -> @contracts.RecordRef {
  self.authorization.authorization_ref
}

///|
pub fn CancellationRequestV2::workflow(
  self : CancellationRequestV2,
) -> @contracts.RecordRef {
  self.proposal.workflow
}

///|
pub fn CancellationRequestV2::governed_subject(
  self : CancellationRequestV2,
) -> @contracts.RecordRef {
  self.proposal.governed_subject
}

///|
pub fn CancellationRequestV2::observed_at(
  self : CancellationRequestV2,
) -> Int64 {
  self.proposal.observed_at
}

///|
pub fn CancellationRequestV2::event_idempotency_key(
  self : CancellationRequestV2,
) -> String {
  self.proposal.event_idempotency_key
}

///|
pub fn CancellationRequestV2::command_idempotency_key(
  self : CancellationRequestV2,
) -> String {
  self.proposal.command_idempotency_key
}
