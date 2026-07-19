///|
/// One immutable governed attempt registration. It records requested work and
/// provenance only; it is not dispatch, success, or acceptance.
pub struct AttemptRegistration {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  attempt_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  causal_event_ref : @contracts.RecordRef
  attempt_ordinal : Int64
  requested_work : @contracts.WireEnvelope
  requested_work_bytes : Bytes
  requested_work_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  evidence_digest : @contracts.ContentDigest
  governance : GovernanceBinding
  created_at : Int64
  idempotency_key : String
  stage_ref : @contracts.RecordRef?
  retry_of_intent_ref : @contracts.RecordRef?
  retry_eligibility_receipt : CommittedRetryEligibilityReceiptV2?
  retry_plan : @retry_authority.RetryPlanProposalV2?
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
pub fn AttemptRegistration::new(
  attempt_id : String,
  attempt_version : String,
  workflow : @contracts.RecordRef,
  causal_event : @storage.WorkflowEvent,
  attempt_ordinal : Int64,
  requested_work : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  governance : GovernanceBinding,
  created_at : Int64,
  idempotency_key : String,
  previous_digest : @contracts.ContentDigest,
  stage_ref? : @contracts.RecordRef,
  retry_of_intent_ref? : @contracts.RecordRef,
  retry_eligibility_receipt? : CommittedRetryEligibilityReceiptV2,
  retry_plan? : @retry_authority.RetryPlanProposalV2,
) -> AttemptRegistration raise EffectsError {
  require_version(attempt_version, "attempt_version")
  require_text(attempt_id, "attempt_id")
  require_text(idempotency_key, "attempt_idempotency_key")
  if causal_event.workflow() != workflow || governance.workflow() != workflow {
    raise IdentityMismatch(field="attempt_workflow")
  }
  if causal_event.event_ref().digest() != previous_digest {
    raise DigestMismatch(field="attempt_previous_digest")
  }
  if attempt_ordinal <= 0L {
    raise OrderingViolation(field="attempt_ordinal")
  }
  if requested_work.subject() != governance.governed_subject() {
    raise IdentityMismatch(field="governed_subject")
  }
  match stage_ref {
    Some(expected) if requested_work.stage_ref() != Some(expected) =>
      raise IdentityMismatch(field="stage_ref")
    None if requested_work.stage_ref() is Some(_) =>
      raise IdentityMismatch(field="unexpected_stage_ref")
    _ => ()
  }
  let requested_work_bytes = @contracts.encode_wire_envelope(requested_work)
  let requested_work_digest = requested_work.envelope_digest()
  match (retry_of_intent_ref, retry_eligibility_receipt, retry_plan) {
    (None, None, None) => ()
    (Some(prior), Some(receipt), Some(plan)) => {
      receipt.require_integrity()
      if receipt.workflow != workflow || receipt.source_intent_ref != prior {
        raise RetryEligibilityViolation(field="retry_attempt_receipt_binding")
      }
      if causal_event.event_ref().digest() != receipt.projection_head_digest {
        raise RetryEligibilityViolation(field="retry_attempt_receipt_head")
      }
      if created_at < receipt.source_observed_at {
        raise OrderingViolation(field="retry_attempt_before_source")
      }
      let expected_child_request = try
        @retry_authority.retry_child_attempt_request_ref_v2(
          attempt_id, workflow, attempt_ordinal, idempotency_key, requested_work_digest,
        )
      catch {
        _ => raise RetryEligibilityViolation(field="retry_attempt_request")
      } noraise {
        value => value
      }
      if plan.workflow() != workflow ||
        plan.receipt_ref() != receipt.receipt_ref() ||
        plan.receipt_digest() != receipt.digest() ||
        plan.receipt_bytes() != receipt.canonical_bytes() ||
        plan.source_intent_ref() != prior ||
        plan.source_attempt_ref() != receipt.source_attempt_ref() ||
        plan.root_intent_ref() != receipt.root_intent_ref() ||
        plan.root_attempt_ref() != receipt.root_attempt_ref() ||
        plan.lineage_digest() != receipt.lineage_digest() ||
        plan.attempt_count() != receipt.attempt_count() ||
        plan.retry_count() != receipt.retry_count() ||
        plan.retry_ordinal() != receipt.retry_ordinal() ||
        plan.cause_key() != receipt.cause_key() ||
        plan.requested_work_ref().digest() != requested_work_digest ||
        plan.requested_work_digest() != requested_work_digest ||
        plan.child_attempt_request_ref() != expected_child_request ||
        plan.child_attempt_ordinal() != attempt_ordinal ||
        plan.child_attempt_idempotency_key() != idempotency_key ||
        plan.prefix_head_ref() != causal_event.event_ref() ||
        plan.prefix_head_digest() != previous_digest ||
        plan.prefix_sequence() != receipt.projection_sequence() ||
        plan.prefix_revision() != receipt.projection_revision() ||
        plan.prefix_replay_digest() != receipt.projection_replay_digest() ||
        plan.governance_digest() != Some(governance.binding_digest()) ||
        plan.governance_bytes() != Some(governance.canonical_bytes()) ||
        plan.governance_deadline() != governance.authority_expires_at() {
        raise RetryEligibilityViolation(field="retry_attempt_plan_binding")
      }
    }
    (Some(_), None, _) =>
      raise RetryEligibilityViolation(field="retry_attempt_receipt_missing")
    (None, Some(_), _) =>
      raise RetryEligibilityViolation(field="retry_attempt_source_missing")
    (Some(_), Some(_), None) =>
      raise RetryEligibilityViolation(field="retry_attempt_plan_missing")
    _ => raise RetryEligibilityViolation(field="retry_attempt_plan_triplet")
  }
  governance.require_active(created_at)
  let evidence_snapshot = evidence.copy()
  let evidence_digest = ordered_evidence_digest(b"MF6AATE1", evidence_snapshot)
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6AATT1")
  writer.string(effects_record_version)
  writer.string(effects_schema_version)
  writer.string(attempt_id)
  write_ref(writer, workflow)
  write_ref(writer, causal_event.event_ref())
  writer.int64(attempt_ordinal)
  writer.bytes(requested_work_bytes)
  writer.string(requested_work_digest.text())
  write_evidence(writer, evidence_snapshot)
  writer.string(evidence_digest.text())
  writer.bytes(governance.canonical_bytes())
  writer.int64(created_at)
  writer.string(idempotency_key)
  write_optional_ref(writer, stage_ref)
  write_optional_ref(writer, retry_of_intent_ref)
  match retry_eligibility_receipt {
    None => ()
    Some(receipt) => {
      write_ref(writer, receipt.receipt_ref())
      writer.string(receipt.digest().text())
      writer.bytes(receipt.canonical_bytes())
      guard retry_plan is Some(plan) else {
        raise RetryEligibilityViolation(field="retry_attempt_plan_missing")
      }
      write_ref(writer, plan.plan_ref())
      writer.string(plan.digest().text())
      writer.bytes(plan.canonical_bytes())
    }
  }
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  {
    record_version: effects_version(),
    schema_version: effects_version(),
    attempt_ref: self_ref(
      "effect-attempt",
      attempt_id,
      @contracts.sha256_digest(canonical),
    ),
    workflow,
    causal_event_ref: causal_event.event_ref(),
    attempt_ordinal,
    requested_work,
    requested_work_bytes,
    requested_work_digest,
    evidence: ReadOnlyArray::from_array(evidence_snapshot),
    evidence_digest,
    governance,
    created_at,
    idempotency_key,
    stage_ref,
    retry_of_intent_ref,
    retry_eligibility_receipt,
    retry_plan,
    previous_digest,
    canonical,
  }
}

///|
pub fn AttemptRegistration::attempt_ref(
  self : AttemptRegistration,
) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
pub fn AttemptRegistration::workflow(
  self : AttemptRegistration,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn AttemptRegistration::attempt_ordinal(
  self : AttemptRegistration,
) -> Int64 {
  self.attempt_ordinal
}

///|
pub fn AttemptRegistration::requested_work(
  self : AttemptRegistration,
) -> @contracts.WireEnvelope {
  self.requested_work
}

///|
pub fn AttemptRegistration::requested_work_digest(
  self : AttemptRegistration,
) -> @contracts.ContentDigest {
  self.requested_work_digest
}

///|
pub fn AttemptRegistration::evidence(
  self : AttemptRegistration,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn AttemptRegistration::governance(
  self : AttemptRegistration,
) -> GovernanceBinding {
  self.governance
}

///|
pub fn AttemptRegistration::idempotency_key(
  self : AttemptRegistration,
) -> String {
  self.idempotency_key
}

///|
/// Inert provenance used by the governed aggregate preparation boundary.
pub fn AttemptRegistration::causal_event_ref(
  self : AttemptRegistration,
) -> @contracts.RecordRef {
  self.causal_event_ref
}

///|
pub fn AttemptRegistration::previous_digest(
  self : AttemptRegistration,
) -> @contracts.ContentDigest {
  self.previous_digest
}

///|
pub fn AttemptRegistration::retry_of_intent_ref(
  self : AttemptRegistration,
) -> @contracts.RecordRef? {
  self.retry_of_intent_ref
}

///|
pub fn AttemptRegistration::retry_eligibility_receipt(
  self : AttemptRegistration,
) -> CommittedRetryEligibilityReceiptV2? {
  self.retry_eligibility_receipt
}

///|
pub fn AttemptRegistration::retry_plan(
  self : AttemptRegistration,
) -> @retry_authority.RetryPlanProposalV2? {
  self.retry_plan
}

///|
pub fn AttemptRegistration::canonical_bytes(
  self : AttemptRegistration,
) -> Bytes {
  self.canonical
}

///|
pub fn AttemptRegistration::binding_digest(
  self : AttemptRegistration,
) -> @contracts.ContentDigest {
  self.attempt_ref.digest()
}

///|
pub impl Eq for AttemptRegistration with fn equal(left, right) {
  left.attempt_ref == right.attempt_ref && left.canonical == right.canonical
}

///|
/// Prepare the next workflow event only. The returned event is still a
/// precommit proposal and confers no dispatch eligibility.
fn prepare_attempt_registration_event(
  projection : EffectsProjection,
  event_id : String,
  registration : AttemptRegistration,
) -> @storage.WorkflowEvent raise {
  projection.require_next_attempt(registration)
  let payload = event_envelope(
    event_id,
    "attempt.registered.v1",
    projection.workflow(),
    registration.governance().governed_subject(),
    registration.canonical_bytes(),
    copy_readonly(registration.evidence()),
    registration.attempt_ref(),
    registration.causal_event_ref.id(),
    registration.idempotency_key(),
    registration.previous_digest,
  )
  @storage.WorkflowEvent::new(
    effects_record_version,
    effects_schema_version,
    projection.workflow(),
    event_id,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    registration.idempotency_key(),
    payload,
    copy_readonly(registration.evidence()),
    previous_event_digest=registration.previous_digest,
  )
}
