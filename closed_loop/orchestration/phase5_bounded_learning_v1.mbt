///|
/// Opaque, schema-versioned assessment over an exact outcome-history head.
/// MoonFlow validates bindings only and never classifies or interprets gaps.
pub struct OpaqueThreeGapAssessmentV1 {
  assessment_ref : @contracts.RecordRef
  delivery_receipt_ref : @contracts.RecordRef
  outcome_history_ref : @contracts.RecordRef
  assessment_method_ref : @contracts.RecordRef
  assessor_ability_ref : @contracts.RecordRef
  assessment : @contracts.WireEnvelope
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  assessed_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn OpaqueThreeGapAssessmentV1::new(
  assessment_id : String,
  delivery : GovernedDeliveryReceiptV1,
  history : OutcomeHistoryV1,
  assessment_method_ref : @contracts.RecordRef,
  assessor_ability_ref : @contracts.RecordRef,
  assessment : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  assessed_at : Int64,
) -> OpaqueThreeGapAssessmentV1 raise OrchestrationError {
  require_text(assessment_id, "opaque_gap_assessment_id_v1")
  require_non_negative(assessed_at, "opaque_gap_assessed_at_v1")
  if history.delivery_receipt_ref != delivery.record_ref() ||
    assessment.subject() != history.record_ref() {
    raise IdentityMismatch(field="opaque_gap_assessment_history_v1")
  }
  if assessed_at < delivery.delivered_at() {
    raise OrderingViolation(field="opaque_gap_assessment_time_v1")
  }
  let evidence = copy_evidence_v1(evidence)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/OPAQUE-THREE-GAP-ASSESSMENT-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(assessment_id)
  write_ref(writer, delivery.record_ref())
  write_ref(writer, history.record_ref())
  writer.string(history.digest().text())
  write_ref(writer, assessment_method_ref)
  write_ref(writer, assessor_ability_ref)
  writer.bytes(assessment.canonical_bytes())
  write_evidence(writer, evidence)
  writer.int64(assessed_at)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    assessment_ref: self_ref(
      "orchestration-opaque-three-gap-assessment-v1", assessment_id, digest,
    ),
    delivery_receipt_ref: delivery.record_ref(),
    outcome_history_ref: history.record_ref(),
    assessment_method_ref,
    assessor_ability_ref,
    assessment,
    evidence,
    assessed_at,
    canonical,
    digest,
  }
}

///|
pub fn OpaqueThreeGapAssessmentV1::record_ref(
  self : OpaqueThreeGapAssessmentV1,
) -> @contracts.RecordRef {
  self.assessment_ref
}

///|
pub fn OpaqueThreeGapAssessmentV1::assessment(
  self : OpaqueThreeGapAssessmentV1,
) -> @contracts.WireEnvelope {
  self.assessment
}

///|
pub fn OpaqueThreeGapAssessmentV1::delivery_receipt_ref(
  self : OpaqueThreeGapAssessmentV1,
) -> @contracts.RecordRef {
  self.delivery_receipt_ref
}

///|
pub fn OpaqueThreeGapAssessmentV1::outcome_history_ref(
  self : OpaqueThreeGapAssessmentV1,
) -> @contracts.RecordRef {
  self.outcome_history_ref
}

///|
pub fn OpaqueThreeGapAssessmentV1::assessment_method_ref(
  self : OpaqueThreeGapAssessmentV1,
) -> @contracts.RecordRef {
  self.assessment_method_ref
}

///|
pub fn OpaqueThreeGapAssessmentV1::assessor_ability_ref(
  self : OpaqueThreeGapAssessmentV1,
) -> @contracts.RecordRef {
  self.assessor_ability_ref
}

///|
pub fn OpaqueThreeGapAssessmentV1::evidence(
  self : OpaqueThreeGapAssessmentV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn OpaqueThreeGapAssessmentV1::assessed_at(
  self : OpaqueThreeGapAssessmentV1,
) -> Int64 {
  self.assessed_at
}

///|
pub fn OpaqueThreeGapAssessmentV1::canonical_bytes(
  self : OpaqueThreeGapAssessmentV1,
) -> Bytes {
  self.canonical
}

///|
pub fn OpaqueThreeGapAssessmentV1::digest(
  self : OpaqueThreeGapAssessmentV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Exactly one bounded target surface. The enum is routing metadata only; it
/// does not grant authority to modify that surface.
pub(all) enum ImprovementRouteV1 {
  MemoryRouteV1
  SkillRouteV1
  FlowRouteV1
  CodeRouteV1
  PolicyRouteV1
} derive(Eq, Debug)

///|
fn ImprovementRouteV1::wire(self : ImprovementRouteV1) -> String {
  match self {
    MemoryRouteV1 => "memory"
    SkillRouteV1 => "skill"
    FlowRouteV1 => "flow"
    CodeRouteV1 => "code"
    PolicyRouteV1 => "policy"
  }
}

///|
/// One finite proposal with no parent/child proposal link and no execution
/// authority. Evaluation and follow-up counts are hard bounded.
pub struct BoundedImprovementProposalV1 {
  proposal_ref : @contracts.RecordRef
  assessment_ref : @contracts.RecordRef
  route : ImprovementRouteV1
  old_version_ref : @contracts.RecordRef
  new_version_ref : @contracts.RecordRef
  proposal : @contracts.WireEnvelope
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  max_offline_evaluations : Int64
  max_followup_actions : Int64
  proposed_at : Int64
  expires_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn BoundedImprovementProposalV1::new(
  proposal_id : String,
  assessment : OpaqueThreeGapAssessmentV1,
  route : ImprovementRouteV1,
  old_version_ref : @contracts.RecordRef,
  new_version_ref : @contracts.RecordRef,
  proposal : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  max_offline_evaluations : Int64,
  max_followup_actions : Int64,
  proposed_at : Int64,
  expires_at : Int64,
) -> BoundedImprovementProposalV1 raise OrchestrationError {
  require_text(proposal_id, "bounded_improvement_proposal_id_v1")
  require_non_negative(proposed_at, "bounded_improvement_proposed_at_v1")
  require_non_negative(expires_at, "bounded_improvement_expires_at_v1")
  if old_version_ref.kind() != new_version_ref.kind() ||
    old_version_ref.id() != new_version_ref.id() ||
    old_version_ref == new_version_ref {
    raise IdentityMismatch(field="bounded_improvement_version_pair_v1")
  }
  if proposal.subject() != new_version_ref {
    raise IdentityMismatch(field="bounded_improvement_subject_v1")
  }
  if max_offline_evaluations <= 0L || max_offline_evaluations > 32L {
    raise RetryBoundViolation(field="bounded_offline_evaluations_v1")
  }
  if max_followup_actions < 0L || max_followup_actions > 64L {
    raise RetryBoundViolation(field="bounded_followup_actions_v1")
  }
  if proposed_at < assessment.assessed_at || expires_at <= proposed_at {
    raise OrderingViolation(field="bounded_improvement_window_v1")
  }
  let evidence = copy_evidence_v1(evidence)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/BOUNDED-IMPROVEMENT-PROPOSAL-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(proposal_id)
  write_ref(writer, assessment.assessment_ref)
  writer.string(route.wire())
  write_ref(writer, old_version_ref)
  write_ref(writer, new_version_ref)
  writer.bytes(proposal.canonical_bytes())
  write_evidence(writer, evidence)
  writer.int64(max_offline_evaluations)
  writer.int64(max_followup_actions)
  writer.int64(proposed_at)
  writer.int64(expires_at)
  writer.byte(0)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    proposal_ref: self_ref(
      "orchestration-bounded-improvement-proposal-v1", proposal_id, digest,
    ),
    assessment_ref: assessment.assessment_ref,
    route,
    old_version_ref,
    new_version_ref,
    proposal,
    evidence,
    max_offline_evaluations,
    max_followup_actions,
    proposed_at,
    expires_at,
    canonical,
    digest,
  }
}

///|
pub fn BoundedImprovementProposalV1::record_ref(
  self : BoundedImprovementProposalV1,
) -> @contracts.RecordRef {
  self.proposal_ref
}

///|
pub fn BoundedImprovementProposalV1::route(
  self : BoundedImprovementProposalV1,
) -> ImprovementRouteV1 {
  self.route
}

///|
pub fn BoundedImprovementProposalV1::assessment_ref(
  self : BoundedImprovementProposalV1,
) -> @contracts.RecordRef {
  self.assessment_ref
}

///|
pub fn BoundedImprovementProposalV1::old_version_ref(
  self : BoundedImprovementProposalV1,
) -> @contracts.RecordRef {
  self.old_version_ref
}

///|
pub fn BoundedImprovementProposalV1::new_version_ref(
  self : BoundedImprovementProposalV1,
) -> @contracts.RecordRef {
  self.new_version_ref
}

///|
pub fn BoundedImprovementProposalV1::max_offline_evaluations(
  self : BoundedImprovementProposalV1,
) -> Int64 {
  self.max_offline_evaluations
}

///|
pub fn BoundedImprovementProposalV1::max_followup_actions(
  self : BoundedImprovementProposalV1,
) -> Int64 {
  self.max_followup_actions
}

///|
pub fn BoundedImprovementProposalV1::proposal(
  self : BoundedImprovementProposalV1,
) -> @contracts.WireEnvelope {
  self.proposal
}

///|
pub fn BoundedImprovementProposalV1::evidence(
  self : BoundedImprovementProposalV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn BoundedImprovementProposalV1::proposed_at(
  self : BoundedImprovementProposalV1,
) -> Int64 {
  self.proposed_at
}

///|
pub fn BoundedImprovementProposalV1::expires_at(
  self : BoundedImprovementProposalV1,
) -> Int64 {
  self.expires_at
}

///|
pub fn BoundedImprovementProposalV1::automatic_activation_permitted(
  self : BoundedImprovementProposalV1,
) -> Bool {
  false
}

///|
pub fn BoundedImprovementProposalV1::recursive_proposal_permitted(
  self : BoundedImprovementProposalV1,
) -> Bool {
  false
}

///|
pub fn BoundedImprovementProposalV1::canonical_bytes(
  self : BoundedImprovementProposalV1,
) -> Bytes {
  self.canonical
}

///|
pub(all) enum OfflineEvaluationOutcomeV1 {
  OfflineEvaluationPassedV1
  OfflineEvaluationFailedV1
  OfflineEvaluationInconclusiveV1
} derive(Eq, Debug)

///|
fn OfflineEvaluationOutcomeV1::wire(
  self : OfflineEvaluationOutcomeV1,
) -> String {
  match self {
    OfflineEvaluationPassedV1 => "passed"
    OfflineEvaluationFailedV1 => "failed"
    OfflineEvaluationInconclusiveV1 => "inconclusive"
  }
}

///|
pub struct OfflineProposalEvaluationV1 {
  evaluation_ref : @contracts.RecordRef
  proposal_ref : @contracts.RecordRef
  evaluation_ordinal : Int64
  evaluator_ability_ref : @contracts.RecordRef
  dataset_snapshot_ref : @contracts.RecordRef
  harness_version_ref : @contracts.RecordRef
  result : @contracts.WireEnvelope
  outcome : OfflineEvaluationOutcomeV1
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  evaluated_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub struct OfflineEvaluationLedgerV1 {
  ledger_ref : @contracts.RecordRef
  proposal_ref : @contracts.RecordRef
  old_version_ref : @contracts.RecordRef
  new_version_ref : @contracts.RecordRef
  maximum_evaluations : Int64
  evaluations : ReadOnlyArray[OfflineProposalEvaluationV1]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn offline_evaluation_ledger_bytes_v1(
  proposal : BoundedImprovementProposalV1,
  evaluations : ArrayView[OfflineProposalEvaluationV1],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/OFFLINE-EVALUATION-LEDGER-V1/1.0.0")
  writer.string("1.0.0")
  write_ref(writer, proposal.proposal_ref)
  write_ref(writer, proposal.old_version_ref)
  write_ref(writer, proposal.new_version_ref)
  writer.int64(proposal.max_offline_evaluations)
  writer.count(evaluations.length())
  for evaluation in evaluations {
    write_ref(writer, evaluation.evaluation_ref)
    writer.bytes(evaluation.canonical)
  }
  writer.finish()
}

///|
pub fn OfflineEvaluationLedgerV1::empty(
  proposal : BoundedImprovementProposalV1,
) -> OfflineEvaluationLedgerV1 raise OrchestrationError {
  let evaluations : Array[OfflineProposalEvaluationV1] = []
  let canonical = offline_evaluation_ledger_bytes_v1(proposal, evaluations)
  let digest = @contracts.sha256_digest(canonical)
  {
    ledger_ref: self_ref(
      "orchestration-offline-evaluation-ledger-v1",
      proposal.proposal_ref.id(),
      digest,
    ),
    proposal_ref: proposal.proposal_ref,
    old_version_ref: proposal.old_version_ref,
    new_version_ref: proposal.new_version_ref,
    maximum_evaluations: proposal.max_offline_evaluations,
    evaluations: ReadOnlyArray::from_array(evaluations),
    canonical,
    digest,
  }
}

///|
pub fn OfflineEvaluationLedgerV1::append(
  self : OfflineEvaluationLedgerV1,
  proposal : BoundedImprovementProposalV1,
  evaluation_id : String,
  evaluator_ability_ref : @contracts.RecordRef,
  dataset_snapshot_ref : @contracts.RecordRef,
  harness_version_ref : @contracts.RecordRef,
  result : @contracts.WireEnvelope,
  outcome : OfflineEvaluationOutcomeV1,
  evidence : Array[@contracts.EvidenceRef],
  evaluated_at : Int64,
) -> (OfflineEvaluationLedgerV1, OfflineProposalEvaluationV1) raise OrchestrationError {
  require_text(evaluation_id, "offline_evaluation_id_v1")
  require_non_negative(evaluated_at, "offline_evaluated_at_v1")
  if self.proposal_ref != proposal.proposal_ref ||
    self.old_version_ref != proposal.old_version_ref ||
    self.new_version_ref != proposal.new_version_ref ||
    self.maximum_evaluations != proposal.max_offline_evaluations {
    raise IdentityMismatch(field="offline_evaluation_proposal_v1")
  }
  if result.subject() != proposal.new_version_ref {
    raise IdentityMismatch(field="offline_evaluation_subject_v1")
  }
  if evaluated_at < proposal.proposed_at || evaluated_at >= proposal.expires_at {
    raise OrderingViolation(field="offline_evaluation_window_v1")
  }
  if self.evaluations.length().to_int64() >= self.maximum_evaluations {
    raise RetryBoundViolation(field="offline_evaluation_count_v1")
  }
  if self.evaluations.any(value => value.evaluation_ref.id() == evaluation_id) {
    raise IdempotencyConflict(key=evaluation_id)
  }
  match self.evaluations.last() {
    Some(previous) if evaluated_at < previous.evaluated_at =>
      raise OrderingViolation(field="offline_evaluation_time_v1")
    _ => ()
  }
  let evidence = copy_evidence_v1(evidence)
  let evaluation_ordinal = checked_add_non_negative(
    self.evaluations.length().to_int64(),
    1L,
    "offline_evaluation_ordinal_v1",
  )
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/OFFLINE-PROPOSAL-EVALUATION-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(evaluation_id)
  write_ref(writer, proposal.proposal_ref)
  writer.int64(evaluation_ordinal)
  write_ref(writer, evaluator_ability_ref)
  write_ref(writer, dataset_snapshot_ref)
  write_ref(writer, harness_version_ref)
  writer.bytes(result.canonical_bytes())
  writer.string(outcome.wire())
  write_evidence(writer, evidence)
  writer.int64(evaluated_at)
  writer.byte(0)
  let evaluation_canonical = writer.finish()
  let evaluation_digest = @contracts.sha256_digest(evaluation_canonical)
  let evaluation : OfflineProposalEvaluationV1 = {
    evaluation_ref: self_ref(
      "orchestration-offline-proposal-evaluation-v1", evaluation_id, evaluation_digest,
    ),
    proposal_ref: proposal.proposal_ref,
    evaluation_ordinal,
    evaluator_ability_ref,
    dataset_snapshot_ref,
    harness_version_ref,
    result,
    outcome,
    evidence,
    evaluated_at,
    canonical: evaluation_canonical,
    digest: evaluation_digest,
  }
  let evaluations : Array[OfflineProposalEvaluationV1] = []
  for value in self.evaluations {
    evaluations.push(value)
  }
  evaluations.push(evaluation)
  let canonical = offline_evaluation_ledger_bytes_v1(proposal, evaluations)
  let digest = @contracts.sha256_digest(canonical)
  let current : OfflineEvaluationLedgerV1 = {
    ledger_ref: self_ref(
      "orchestration-offline-evaluation-ledger-v1",
      proposal.proposal_ref.id(),
      digest,
    ),
    proposal_ref: proposal.proposal_ref,
    old_version_ref: proposal.old_version_ref,
    new_version_ref: proposal.new_version_ref,
    maximum_evaluations: proposal.max_offline_evaluations,
    evaluations: ReadOnlyArray::from_array(evaluations),
    canonical,
    digest,
  }
  (current, evaluation)
}

///|
pub fn OfflineEvaluationLedgerV1::record_ref(
  self : OfflineEvaluationLedgerV1,
) -> @contracts.RecordRef {
  self.ledger_ref
}

///|
pub fn OfflineEvaluationLedgerV1::evaluations(
  self : OfflineEvaluationLedgerV1,
) -> ReadOnlyArray[OfflineProposalEvaluationV1] {
  self.evaluations
}

///|
pub fn OfflineEvaluationLedgerV1::proposal_ref(
  self : OfflineEvaluationLedgerV1,
) -> @contracts.RecordRef {
  self.proposal_ref
}

///|
pub fn OfflineEvaluationLedgerV1::canonical_bytes(
  self : OfflineEvaluationLedgerV1,
) -> Bytes {
  self.canonical
}

///|
pub fn OfflineEvaluationLedgerV1::digest(
  self : OfflineEvaluationLedgerV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn OfflineProposalEvaluationV1::record_ref(
  self : OfflineProposalEvaluationV1,
) -> @contracts.RecordRef {
  self.evaluation_ref
}

///|
pub fn OfflineProposalEvaluationV1::outcome(
  self : OfflineProposalEvaluationV1,
) -> OfflineEvaluationOutcomeV1 {
  self.outcome
}

///|
pub fn OfflineProposalEvaluationV1::proposal_ref(
  self : OfflineProposalEvaluationV1,
) -> @contracts.RecordRef {
  self.proposal_ref
}

///|
pub fn OfflineProposalEvaluationV1::evaluation_ordinal(
  self : OfflineProposalEvaluationV1,
) -> Int64 {
  self.evaluation_ordinal
}

///|
pub fn OfflineProposalEvaluationV1::evaluator_ability_ref(
  self : OfflineProposalEvaluationV1,
) -> @contracts.RecordRef {
  self.evaluator_ability_ref
}

///|
pub fn OfflineProposalEvaluationV1::dataset_snapshot_ref(
  self : OfflineProposalEvaluationV1,
) -> @contracts.RecordRef {
  self.dataset_snapshot_ref
}

///|
pub fn OfflineProposalEvaluationV1::harness_version_ref(
  self : OfflineProposalEvaluationV1,
) -> @contracts.RecordRef {
  self.harness_version_ref
}

///|
pub fn OfflineProposalEvaluationV1::result(
  self : OfflineProposalEvaluationV1,
) -> @contracts.WireEnvelope {
  self.result
}

///|
pub fn OfflineProposalEvaluationV1::evidence(
  self : OfflineProposalEvaluationV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn OfflineProposalEvaluationV1::evaluated_at(
  self : OfflineProposalEvaluationV1,
) -> Int64 {
  self.evaluated_at
}

///|
pub fn OfflineProposalEvaluationV1::canonical_bytes(
  self : OfflineProposalEvaluationV1,
) -> Bytes {
  self.canonical
}

///|
pub fn OfflineProposalEvaluationV1::digest(
  self : OfflineProposalEvaluationV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn OfflineProposalEvaluationV1::external_effects_permitted(
  self : OfflineProposalEvaluationV1,
) -> Bool {
  false
}

///|
pub(all) enum HumanVersionDecisionOutcomeV1 {
  VersionAdoptedV1
  VersionRejectedV1
} derive(Eq, Debug)

///|
fn HumanVersionDecisionOutcomeV1::wire(
  self : HumanVersionDecisionOutcomeV1,
) -> String {
  match self {
    VersionAdoptedV1 => "adopted"
    VersionRejectedV1 => "rejected"
  }
}

///|
/// Named-human governance over exact old/new versions after offline
/// evaluation. Adoption is an approval receipt, never a deployment command.
pub struct HumanVersionDecisionV1 {
  decision_ref : @contracts.RecordRef
  proposal_ref : @contracts.RecordRef
  evaluation_ref : @contracts.RecordRef
  outcome : HumanVersionDecisionOutcomeV1
  old_version_ref : @contracts.RecordRef
  new_version_ref : @contracts.RecordRef
  named_human_ref : @contracts.RecordRef
  authority_ref : @contracts.RecordRef
  review_decision_ref : @contracts.RecordRef
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  decided_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn HumanVersionDecisionV1::new(
  decision_id : String,
  proposal : BoundedImprovementProposalV1,
  ledger : OfflineEvaluationLedgerV1,
  evaluation : OfflineProposalEvaluationV1,
  outcome : HumanVersionDecisionOutcomeV1,
  named_human_ref : @contracts.RecordRef,
  named_human_attestation : @contracts.WireEnvelope,
  authority : @governance.AuthorityDecision,
  review_request : @governance.ReviewRequest,
  human_review : @governance.ReviewDecision,
  evidence : Array[@contracts.EvidenceRef],
  decided_at : Int64,
) -> HumanVersionDecisionV1 raise OrchestrationError {
  require_text(decision_id, "human_version_decision_id_v1")
  require_non_negative(decided_at, "human_version_decided_at_v1")
  if ledger.proposal_ref != proposal.proposal_ref ||
    ledger.old_version_ref != proposal.old_version_ref ||
    ledger.new_version_ref != proposal.new_version_ref ||
    !ledger.evaluations.any(value => {
      value.evaluation_ref == evaluation.evaluation_ref &&
      value.canonical == evaluation.canonical
    }) {
    raise IdentityMismatch(field="human_version_evaluation_v1")
  }
  if named_human_attestation.subject() != named_human_ref ||
    human_review.reviewer_ref() != named_human_ref {
    raise IdentityMismatch(field="named_human_identity_v1")
  }
  require_granted_authority_v1(authority, "human_version_authority_v1")
  require_review_binding_v1(
    review_request,
    human_review,
    evaluation.result,
    "human_version_review_v1",
  )
  match outcome {
    VersionAdoptedV1 =>
      if evaluation.outcome != OfflineEvaluationPassedV1 ||
        human_review.outcome() != @governance.Approved {
        raise GovernanceMismatch(field="human_version_adoption_v1")
      }
    VersionRejectedV1 =>
      if human_review.outcome() != @governance.Rejected {
        raise GovernanceMismatch(field="human_version_rejection_v1")
      }
  }
  if decided_at < evaluation.evaluated_at ||
    decided_at < human_review.decided_at() ||
    decided_at >= proposal.expires_at {
    raise OrderingViolation(field="human_version_decision_time_v1")
  }
  let evidence = copy_evidence_v1(evidence)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/HUMAN-VERSION-DECISION-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(decision_id)
  write_ref(writer, proposal.proposal_ref)
  write_ref(writer, evaluation.evaluation_ref)
  writer.string(outcome.wire())
  write_ref(writer, proposal.old_version_ref)
  write_ref(writer, proposal.new_version_ref)
  write_ref(writer, named_human_ref)
  writer.bytes(named_human_attestation.canonical_bytes())
  write_authority_decision_binding_v1(writer, authority)
  write_review_decision_binding_v1(writer, review_request, human_review)
  write_evidence(writer, evidence)
  writer.int64(decided_at)
  writer.byte(0)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    decision_ref: self_ref(
      "orchestration-human-version-decision-v1", decision_id, digest,
    ),
    proposal_ref: proposal.proposal_ref,
    evaluation_ref: evaluation.evaluation_ref,
    outcome,
    old_version_ref: proposal.old_version_ref,
    new_version_ref: proposal.new_version_ref,
    named_human_ref,
    authority_ref: authority.decision_ref(),
    review_decision_ref: human_review.decision_ref(),
    evidence,
    decided_at,
    canonical,
    digest,
  }
}

///|
pub fn HumanVersionDecisionV1::record_ref(
  self : HumanVersionDecisionV1,
) -> @contracts.RecordRef {
  self.decision_ref
}

///|
pub fn HumanVersionDecisionV1::outcome(
  self : HumanVersionDecisionV1,
) -> HumanVersionDecisionOutcomeV1 {
  self.outcome
}

///|
pub fn HumanVersionDecisionV1::proposal_ref(
  self : HumanVersionDecisionV1,
) -> @contracts.RecordRef {
  self.proposal_ref
}

///|
pub fn HumanVersionDecisionV1::evaluation_ref(
  self : HumanVersionDecisionV1,
) -> @contracts.RecordRef {
  self.evaluation_ref
}

///|
pub fn HumanVersionDecisionV1::old_version_ref(
  self : HumanVersionDecisionV1,
) -> @contracts.RecordRef {
  self.old_version_ref
}

///|
pub fn HumanVersionDecisionV1::new_version_ref(
  self : HumanVersionDecisionV1,
) -> @contracts.RecordRef {
  self.new_version_ref
}

///|
pub fn HumanVersionDecisionV1::named_human_ref(
  self : HumanVersionDecisionV1,
) -> @contracts.RecordRef {
  self.named_human_ref
}

///|
pub fn HumanVersionDecisionV1::authority_ref(
  self : HumanVersionDecisionV1,
) -> @contracts.RecordRef {
  self.authority_ref
}

///|
pub fn HumanVersionDecisionV1::review_decision_ref(
  self : HumanVersionDecisionV1,
) -> @contracts.RecordRef {
  self.review_decision_ref
}

///|
pub fn HumanVersionDecisionV1::evidence(
  self : HumanVersionDecisionV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn HumanVersionDecisionV1::decided_at(
  self : HumanVersionDecisionV1,
) -> Int64 {
  self.decided_at
}

///|
pub fn HumanVersionDecisionV1::requires_manual_application(
  self : HumanVersionDecisionV1,
) -> Bool {
  true
}

///|
pub fn HumanVersionDecisionV1::automatic_deployment_permitted(
  self : HumanVersionDecisionV1,
) -> Bool {
  false
}

///|
pub fn HumanVersionDecisionV1::canonical_bytes(
  self : HumanVersionDecisionV1,
) -> Bytes {
  self.canonical
}

///|
pub fn HumanVersionDecisionV1::digest(
  self : HumanVersionDecisionV1,
) -> @contracts.ContentDigest {
  self.digest
}
