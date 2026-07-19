///|
/// Opaque validated input for exactly one governance event meaning.
pub struct GovernanceAction {
  event_kind : String
  record_ref : @contracts.RecordRef
  payload : Bytes
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  idempotency_key : String
}

///|
fn GovernanceAction::make(
  event_kind : String,
  record_ref : @contracts.RecordRef,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  idempotency_key : String,
) -> GovernanceAction raise GovernanceError {
  require_text(idempotency_key, "event_idempotency_key")
  {
    event_kind,
    record_ref,
    payload,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    idempotency_key,
  }
}

///|
pub fn GovernanceAction::evidence_attached(
  value : EvidenceAttachment,
  idempotency_key : String,
) -> GovernanceAction raise GovernanceError {
  GovernanceAction::make(
    evidence_attached_kind,
    value.attachment_ref,
    value.canonical_bytes(),
    [
      for evidence in value.evidence => evidence
    ],
    idempotency_key,
  )
}

///|
pub fn GovernanceAction::authority_requested(
  value : AuthorityRequest,
) -> GovernanceAction raise GovernanceError {
  GovernanceAction::make(
    authority_requested_kind,
    value.request_ref,
    value.canonical_bytes(),
    [
      for evidence in value.evidence => evidence
    ],
    value.idempotency_key,
  )
}

///|
pub fn GovernanceAction::authority_decided(
  value : AuthorityDecision,
  idempotency_key : String,
) -> GovernanceAction raise GovernanceError {
  GovernanceAction::make(
    if value.outcome == Granted {
      authority_granted_kind
    } else {
      authority_denied_kind
    },
    value.decision_ref,
    value.canonical_bytes(),
    [],
    idempotency_key,
  )
}

///|
pub fn GovernanceAction::authority_expired(
  value : AuthorityExpiration,
  idempotency_key : String,
) -> GovernanceAction raise GovernanceError {
  GovernanceAction::make(
    authority_expired_kind,
    value.expiration_ref,
    value.canonical_bytes(),
    [],
    idempotency_key,
  )
}

///|
pub fn GovernanceAction::review_requested(
  value : ReviewRequest,
) -> GovernanceAction raise GovernanceError {
  GovernanceAction::make(
    review_requested_kind,
    value.request_ref,
    value.canonical_bytes(),
    [
      for evidence in value.evidence => evidence
    ],
    value.idempotency_key,
  )
}

///|
pub fn GovernanceAction::review_decision_recorded(
  value : ReviewDecision,
  idempotency_key : String,
) -> GovernanceAction raise GovernanceError {
  let evidence = [ for item in value.supporting_evidence => item ]
  for item in value.contradictory_evidence {
    evidence.push(item)
  }
  GovernanceAction::make(
    review_decision_recorded_kind,
    value.decision_ref,
    value.canonical_bytes(),
    evidence,
    idempotency_key,
  )
}

///|
pub fn GovernanceAction::review_receipt_bound(
  value : ReviewReceipt,
  idempotency_key : String,
) -> GovernanceAction raise GovernanceError {
  GovernanceAction::make(
    review_receipt_bound_kind,
    value.receipt_ref,
    value.canonical_bytes(),
    [],
    idempotency_key,
  )
}

///|
pub fn GovernanceAction::event_kind(self : GovernanceAction) -> String {
  self.event_kind
}

///|
pub fn prepare_event(
  projection : GovernanceProjection,
  event_id : String,
  action : GovernanceAction,
) -> @storage.WorkflowEvent raise {
  require_text(event_id, "event_id")
  let causation_ref = projection.accepted_events
    .last()
    .map(value => value.event_ref().id())
  let previous_digest = projection.last_event_digest
  let envelope = @contracts.WireEnvelope::new(
    governance_contract_id,
    governance_contract_version,
    event_id,
    action.event_kind,
    action.record_ref,
    schema_for(action.event_kind),
    action.payload,
    governance_producer_id,
    governance_producer_version,
    [],
    [
      for evidence in action.evidence => evidence
    ],
    run_ref=projection.workflow,
    correlation_ref=projection.workflow.id(),
    causation_ref?,
    idempotency_ref=action.idempotency_key,
    previous_digest?,
  )
  let event = match projection.last_event_digest {
    None =>
      @storage.WorkflowEvent::new(
        governance_record_version,
        governance_schema_version,
        projection.workflow,
        event_id,
        projection.sequence + 1L,
        projection.revision + 1L,
        action.idempotency_key,
        envelope,
        [
          for evidence in action.evidence => evidence
        ],
      )
    Some(previous) =>
      @storage.WorkflowEvent::new(
        governance_record_version,
        governance_schema_version,
        projection.workflow,
        event_id,
        projection.sequence + 1L,
        projection.revision + 1L,
        action.idempotency_key,
        envelope,
        [
          for evidence in action.evidence => evidence
        ],
        previous_event_digest=previous,
      )
  }
  ignore(projection.apply_event(event))
  event
}
