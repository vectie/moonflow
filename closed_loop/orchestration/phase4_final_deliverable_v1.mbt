///|
/// Exact, opaque binding to a terminal receipt accepted by the host. The
/// protocol never interprets the terminal outcome or pack payload.
pub struct TerminalReceiptBindingV1 {
  receipt_ref : @contracts.RecordRef
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_terminal_receipt_binding_v1(
  receipt_ref : @contracts.RecordRef,
  canonical : Bytes,
) -> TerminalReceiptBindingV1 raise OrchestrationError {
  let digest = @contracts.sha256_digest(canonical)
  if receipt_ref.digest() != digest {
    raise DigestMismatch(field="finalization_terminal_receipt_v1")
  }
  { receipt_ref, canonical, digest }
}

///|
pub fn TerminalReceiptBindingV1::from_work_terminal_v2(
  receipt : CommittedWorkTerminalReceiptV2,
) -> TerminalReceiptBindingV1 raise OrchestrationError {
  make_terminal_receipt_binding_v1(
    receipt.record_ref(),
    receipt.canonical_bytes(),
  )
}

///|
pub fn TerminalReceiptBindingV1::from_recovery_terminal_v3(
  receipt : ThreeStreamRecoveryTerminalReceiptV3,
) -> TerminalReceiptBindingV1 raise OrchestrationError {
  make_terminal_receipt_binding_v1(
    receipt.record_ref(),
    receipt.canonical_bytes(),
  )
}

///|
/// Host extension point for a terminal protocol implemented outside this
/// package. Integrity is exact; the payload remains opaque.
pub fn TerminalReceiptBindingV1::from_verified_opaque(
  receipt_ref : @contracts.RecordRef,
  canonical : Bytes,
) -> TerminalReceiptBindingV1 raise OrchestrationError {
  make_terminal_receipt_binding_v1(receipt_ref, canonical)
}

///|
pub fn TerminalReceiptBindingV1::record_ref(
  self : TerminalReceiptBindingV1,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn TerminalReceiptBindingV1::canonical_bytes(
  self : TerminalReceiptBindingV1,
) -> Bytes {
  self.canonical
}

///|
pub fn TerminalReceiptBindingV1::digest(
  self : TerminalReceiptBindingV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
fn write_terminal_receipt_binding_v1(
  writer : OrchestrationWriter,
  value : TerminalReceiptBindingV1,
) -> Unit raise OrchestrationError {
  write_ref(writer, value.receipt_ref)
  writer.bytes(value.canonical)
  writer.string(value.digest.text())
}

///|
fn require_granted_authority_v1(
  authority : @governance.AuthorityDecision,
  field : String,
) -> Unit raise OrchestrationError {
  if authority.outcome() != @governance.Granted {
    raise GovernanceMismatch(field~)
  }
}

///|
fn require_review_binding_v1(
  request : @governance.ReviewRequest,
  decision : @governance.ReviewDecision,
  subject : @contracts.WireEnvelope,
  field : String,
) -> Unit raise OrchestrationError {
  if decision.request_ref() != request.request_ref() ||
    request.subject().canonical_bytes() != subject.canonical_bytes() {
    raise GovernanceMismatch(field~)
  }
}

///|
fn write_authority_decision_binding_v1(
  writer : OrchestrationWriter,
  authority : @governance.AuthorityDecision,
) -> Unit raise OrchestrationError {
  write_ref(writer, authority.decision_ref())
  write_ref(writer, authority.request_ref())
  write_ref(writer, authority.authority_ref())
  writer.int64(authority.decided_at())
  writer.string(authority.binding_digest().text())
  writer.bytes(authority.canonical_bytes())
}

///|
fn write_review_decision_binding_v1(
  writer : OrchestrationWriter,
  request : @governance.ReviewRequest,
  decision : @governance.ReviewDecision,
) -> Unit raise OrchestrationError {
  write_ref(writer, request.request_ref())
  writer.string(request.binding_digest().text())
  writer.bytes(request.canonical_bytes())
  write_ref(writer, decision.decision_ref())
  write_ref(writer, decision.reviewer_ref())
  writer.int64(decision.decided_at())
  writer.string(decision.binding_digest().text())
  writer.bytes(decision.canonical_bytes())
}

///|
fn copy_evidence_v1(
  evidence : Array[@contracts.EvidenceRef],
) -> ReadOnlyArray[@contracts.EvidenceRef] raise OrchestrationError {
  for index, value in evidence {
    for prior in 0..<index {
      if evidence[prior].record() == value.record() {
        raise EvidenceMismatch(field="duplicate_evidence_v1")
      }
    }
  }
  ReadOnlyArray::from_array(evidence.copy())
}

///|
/// Opaque candidate intake. It is valid only because it binds an exact
/// terminal receipt, exact ability version, granted authority, and evidence.
pub struct FinalDeliverableCandidateV1 {
  candidate_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  terminal : TerminalReceiptBindingV1
  candidate : @contracts.WireEnvelope
  ability_ref : @contracts.RecordRef
  intake_authority_ref : @contracts.RecordRef
  intake_authority_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  submitted_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn FinalDeliverableCandidateV1::new(
  candidate_id : String,
  workflow : @contracts.RecordRef,
  terminal : TerminalReceiptBindingV1,
  candidate : @contracts.WireEnvelope,
  ability_ref : @contracts.RecordRef,
  intake_authority : @governance.AuthorityDecision,
  evidence : Array[@contracts.EvidenceRef],
  submitted_at : Int64,
) -> FinalDeliverableCandidateV1 raise OrchestrationError {
  require_text(candidate_id, "final_deliverable_candidate_id_v1")
  require_non_negative(submitted_at, "final_deliverable_submitted_at_v1")
  require_granted_authority_v1(
    intake_authority, "final_deliverable_intake_authority_v1",
  )
  if submitted_at < intake_authority.decided_at() {
    raise OrderingViolation(field="final_deliverable_intake_time_v1")
  }
  let evidence = copy_evidence_v1(evidence)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/FINAL-DELIVERABLE-CANDIDATE-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(candidate_id)
  write_ref(writer, workflow)
  write_terminal_receipt_binding_v1(writer, terminal)
  writer.bytes(candidate.canonical_bytes())
  write_ref(writer, ability_ref)
  write_authority_decision_binding_v1(writer, intake_authority)
  write_evidence(writer, evidence)
  writer.int64(submitted_at)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    candidate_ref: self_ref(
      "orchestration-final-deliverable-candidate-v1", candidate_id, digest,
    ),
    workflow,
    terminal,
    candidate,
    ability_ref,
    intake_authority_ref: intake_authority.decision_ref(),
    intake_authority_digest: intake_authority.binding_digest(),
    evidence,
    submitted_at,
    canonical,
    digest,
  }
}

///|
pub fn FinalDeliverableCandidateV1::record_ref(
  self : FinalDeliverableCandidateV1,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn FinalDeliverableCandidateV1::workflow(
  self : FinalDeliverableCandidateV1,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn FinalDeliverableCandidateV1::terminal_receipt_ref(
  self : FinalDeliverableCandidateV1,
) -> @contracts.RecordRef {
  self.terminal.record_ref()
}

///|
pub fn FinalDeliverableCandidateV1::candidate(
  self : FinalDeliverableCandidateV1,
) -> @contracts.WireEnvelope {
  self.candidate
}

///|
pub fn FinalDeliverableCandidateV1::ability_ref(
  self : FinalDeliverableCandidateV1,
) -> @contracts.RecordRef {
  self.ability_ref
}

///|
pub fn FinalDeliverableCandidateV1::intake_authority_ref(
  self : FinalDeliverableCandidateV1,
) -> @contracts.RecordRef {
  self.intake_authority_ref
}

///|
pub fn FinalDeliverableCandidateV1::intake_authority_digest(
  self : FinalDeliverableCandidateV1,
) -> @contracts.ContentDigest {
  self.intake_authority_digest
}

///|
pub fn FinalDeliverableCandidateV1::evidence(
  self : FinalDeliverableCandidateV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn FinalDeliverableCandidateV1::submitted_at(
  self : FinalDeliverableCandidateV1,
) -> Int64 {
  self.submitted_at
}

///|
pub fn FinalDeliverableCandidateV1::canonical_bytes(
  self : FinalDeliverableCandidateV1,
) -> Bytes {
  self.canonical
}

///|
pub fn FinalDeliverableCandidateV1::digest(
  self : FinalDeliverableCandidateV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum FinalDeliverableDispositionV1 {
  DeliverableAcceptedV1
  DeliverableRejectedV1
  DeliverableRevisionRequestedV1
  DeliverableEscalatedV1
} derive(Eq, Debug)

///|
fn FinalDeliverableDispositionV1::wire(
  self : FinalDeliverableDispositionV1,
) -> String {
  match self {
    DeliverableAcceptedV1 => "accepted"
    DeliverableRejectedV1 => "rejected"
    DeliverableRevisionRequestedV1 => "revision-requested"
    DeliverableEscalatedV1 => "escalated"
  }
}

///|
fn require_disposition_review_v1(
  disposition : FinalDeliverableDispositionV1,
  review : @governance.ReviewDecision,
  escalation_target : @contracts.RecordRef?,
) -> Unit raise OrchestrationError {
  match disposition {
    DeliverableAcceptedV1 =>
      if review.outcome() != @governance.Approved ||
        escalation_target is Some(_) {
        raise GovernanceMismatch(field="deliverable_accept_review_v1")
      }
    DeliverableRejectedV1 =>
      if review.outcome() != @governance.Rejected ||
        escalation_target is Some(_) {
        raise GovernanceMismatch(field="deliverable_reject_review_v1")
      }
    DeliverableRevisionRequestedV1 =>
      if review.outcome() != @governance.ChangesRequested ||
        escalation_target is Some(_) {
        raise GovernanceMismatch(field="deliverable_revision_review_v1")
      }
    DeliverableEscalatedV1 =>
      if escalation_target is None {
        raise GovernanceMismatch(field="deliverable_escalation_target_v1")
      }
  }
}

///|
/// Human-reviewed disposition over one exact candidate. An escalation only
/// records a bounded handoff target; it does not schedule or execute work.
pub struct FinalDeliverableDecisionV1 {
  decision_ref : @contracts.RecordRef
  candidate_ref : @contracts.RecordRef
  disposition : FinalDeliverableDispositionV1
  ability_ref : @contracts.RecordRef
  authority_ref : @contracts.RecordRef
  review_request_ref : @contracts.RecordRef
  review_decision_ref : @contracts.RecordRef
  human_reviewer_ref : @contracts.RecordRef
  escalation_target : @contracts.RecordRef?
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  decided_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn FinalDeliverableDecisionV1::new(
  decision_id : String,
  candidate : FinalDeliverableCandidateV1,
  disposition : FinalDeliverableDispositionV1,
  ability_ref : @contracts.RecordRef,
  authority : @governance.AuthorityDecision,
  review_request : @governance.ReviewRequest,
  human_review : @governance.ReviewDecision,
  evidence : Array[@contracts.EvidenceRef],
  decided_at : Int64,
  escalation_target? : @contracts.RecordRef,
) -> FinalDeliverableDecisionV1 raise OrchestrationError {
  require_text(decision_id, "final_deliverable_decision_id_v1")
  require_non_negative(decided_at, "final_deliverable_decided_at_v1")
  if ability_ref != candidate.ability_ref {
    raise IdentityMismatch(field="final_deliverable_ability_v1")
  }
  require_granted_authority_v1(
    authority, "final_deliverable_decision_authority_v1",
  )
  if authority.decision_ref() != candidate.intake_authority_ref ||
    authority.binding_digest() != candidate.intake_authority_digest {
    raise GovernanceMismatch(field="final_deliverable_candidate_authority_v1")
  }
  require_review_binding_v1(
    review_request,
    human_review,
    candidate.candidate,
    "final_deliverable_human_review_v1",
  )
  require_disposition_review_v1(disposition, human_review, escalation_target)
  if decided_at < candidate.submitted_at ||
    decided_at < human_review.decided_at() {
    raise OrderingViolation(field="final_deliverable_decision_time_v1")
  }
  let evidence = copy_evidence_v1(evidence)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/FINAL-DELIVERABLE-DECISION-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(decision_id)
  write_ref(writer, candidate.candidate_ref)
  writer.string(disposition.wire())
  write_ref(writer, ability_ref)
  write_authority_decision_binding_v1(writer, authority)
  write_review_decision_binding_v1(writer, review_request, human_review)
  write_optional_ref(writer, escalation_target)
  write_evidence(writer, evidence)
  writer.int64(decided_at)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    decision_ref: self_ref(
      "orchestration-final-deliverable-decision-v1", decision_id, digest,
    ),
    candidate_ref: candidate.candidate_ref,
    disposition,
    ability_ref,
    authority_ref: authority.decision_ref(),
    review_request_ref: review_request.request_ref(),
    review_decision_ref: human_review.decision_ref(),
    human_reviewer_ref: human_review.reviewer_ref(),
    escalation_target,
    evidence,
    decided_at,
    canonical,
    digest,
  }
}

///|
pub fn FinalDeliverableDecisionV1::record_ref(
  self : FinalDeliverableDecisionV1,
) -> @contracts.RecordRef {
  self.decision_ref
}

///|
pub fn FinalDeliverableDecisionV1::candidate_ref(
  self : FinalDeliverableDecisionV1,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn FinalDeliverableDecisionV1::disposition(
  self : FinalDeliverableDecisionV1,
) -> FinalDeliverableDispositionV1 {
  self.disposition
}

///|
pub fn FinalDeliverableDecisionV1::human_reviewer_ref(
  self : FinalDeliverableDecisionV1,
) -> @contracts.RecordRef {
  self.human_reviewer_ref
}

///|
pub fn FinalDeliverableDecisionV1::ability_ref(
  self : FinalDeliverableDecisionV1,
) -> @contracts.RecordRef {
  self.ability_ref
}

///|
pub fn FinalDeliverableDecisionV1::authority_ref(
  self : FinalDeliverableDecisionV1,
) -> @contracts.RecordRef {
  self.authority_ref
}

///|
pub fn FinalDeliverableDecisionV1::review_request_ref(
  self : FinalDeliverableDecisionV1,
) -> @contracts.RecordRef {
  self.review_request_ref
}

///|
pub fn FinalDeliverableDecisionV1::review_decision_ref(
  self : FinalDeliverableDecisionV1,
) -> @contracts.RecordRef {
  self.review_decision_ref
}

///|
pub fn FinalDeliverableDecisionV1::escalation_target(
  self : FinalDeliverableDecisionV1,
) -> @contracts.RecordRef? {
  self.escalation_target
}

///|
pub fn FinalDeliverableDecisionV1::evidence(
  self : FinalDeliverableDecisionV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn FinalDeliverableDecisionV1::decided_at(
  self : FinalDeliverableDecisionV1,
) -> Int64 {
  self.decided_at
}

///|
pub fn FinalDeliverableDecisionV1::canonical_bytes(
  self : FinalDeliverableDecisionV1,
) -> Bytes {
  self.canonical
}

///|
pub fn FinalDeliverableDecisionV1::digest(
  self : FinalDeliverableDecisionV1,
) -> @contracts.ContentDigest {
  self.digest
}
