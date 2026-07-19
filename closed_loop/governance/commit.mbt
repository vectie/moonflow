///|
fn request_wrapper(
  event : @storage.WorkflowEvent,
  envelope_id : String,
  idempotency_key : String,
  requested_work : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
) -> @contracts.WireEnvelope raise {
  @contracts.WireEnvelope::new(
    governance_contract_id,
    governance_contract_version,
    envelope_id,
    request_intent_kind,
    event.event_ref(),
    schema_for(request_intent_kind),
    @contracts.encode_wire_envelope(requested_work),
    governance_producer_id,
    governance_producer_version,
    [],
    evidence,
    run_ref=event.workflow(),
    correlation_ref=event.workflow().id(),
    causation_ref=event.event_ref().id(),
    idempotency_ref=idempotency_key,
    previous_digest=event.event_ref().digest(),
  )
}

///|
pub fn prepare_request_intent(
  event : @storage.WorkflowEvent,
  intent_id : String,
  idempotency_key : String,
  requested_work : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
) -> @storage.OutboxIntent raise {
  require_text(intent_id, "request_intent_id")
  require_text(idempotency_key, "request_intent_idempotency")
  let event_kind = event.payload().envelope_kind()
  if event_kind != authority_requested_kind &&
    event_kind != review_requested_kind {
    raise InvalidState(field="request_intent_causation")
  }
  let payload = request_wrapper(
    event,
    "request-intent-envelope-\{intent_id}",
    idempotency_key,
    requested_work,
    evidence,
  )
  let canonical_evidence = [ for value in payload.evidence() => value ]
  @storage.OutboxIntent::new(
    governance_record_version,
    governance_schema_version,
    intent_id,
    event.workflow(),
    event.event_ref(),
    idempotency_key,
    payload,
    canonical_evidence,
  )
}

///|
fn validate_request_intent(
  projection : GovernanceProjection,
  intent : @storage.OutboxIntent,
) -> Unit raise {
  if intent.record_version().text() != governance_record_version {
    raise UnsupportedVersion(
      field="request_intent_record_version",
      version=intent.record_version().text(),
    )
  }
  if intent.schema_version().text() != governance_schema_version {
    raise UnsupportedVersion(
      field="request_intent_schema_version",
      version=intent.schema_version().text(),
    )
  }
  if intent.intent_ref().kind() != "outbox-intent" ||
    intent.intent_ref().version() != intent.record_version() {
    raise IdentityMismatch(field="request_intent_identity")
  }
  require_exact_record(
    intent.workflow(),
    projection.workflow,
    "intent_workflow",
  )
  guard accepted_event_by_ref(projection, intent.causative_event())
    is Some(event) else {
    raise CausationMismatch(field="request_intent_event")
  }
  let event_kind = event.payload().envelope_kind()
  if event_kind != authority_requested_kind &&
    event_kind != review_requested_kind {
    raise InvalidState(field="request_intent_causation")
  }
  let payload = intent.payload()
  if payload.contract_id() != governance_contract_id ||
    payload.contract_version().text() != governance_contract_version ||
    payload.envelope_kind() != request_intent_kind ||
    payload.schema() != schema_for(request_intent_kind) {
    raise InvalidEventKind(payload.envelope_kind())
  }
  if payload.producer_id() != governance_producer_id ||
    payload.producer_version().text() != governance_producer_version {
    raise IdentityMismatch(field="request_intent_producer")
  }
  if payload.envelope_id() !=
    "request-intent-envelope-\{intent.intent_ref().id()}" {
    raise IdentityMismatch(field="request_intent_envelope_identity")
  }
  require_exact_record(payload.subject(), event.event_ref(), "intent_subject")
  if payload.run_ref() != Some(projection.workflow) ||
    payload.stage_ref() is Some(_) ||
    payload.attempt_ref() is Some(_) {
    raise IdentityMismatch(field="request_intent_workflow_binding")
  }
  if payload.correlation_ref() != Some(projection.workflow.id()) {
    raise CausationMismatch(field="request_intent_correlation")
  }
  if payload.causation_ref() != Some(event.event_ref().id()) ||
    payload.idempotency_ref() != Some(intent.idempotency_key()) ||
    payload.previous_digest() != Some(event.event_ref().digest()) {
    raise CausationMismatch(field="request_intent_binding")
  }
  if !payload.artifacts().is_empty() || !payload.extensions().is_empty() {
    raise MalformedPayload(field="request_intent_extras")
  }
  if !same_evidence(payload.evidence(), intent.evidence()) {
    raise EvidenceViolation(field="request_intent_evidence")
  }
  let requested_work_bytes = payload.payload()
  let requested_work = @contracts.decode_wire_envelope(requested_work_bytes)
  if @contracts.encode_wire_envelope(requested_work) != requested_work_bytes {
    raise MalformedPayload(field="request_intent_requested_work")
  }
}

///|
pub fn prepare_governance_commit(
  projection : GovernanceProjection,
  command_idempotency_key : String,
  events : Array[@storage.WorkflowEvent],
  intents : Array[@storage.OutboxIntent],
) -> @storage.CommitRequest raise {
  require_text(command_idempotency_key, "command_idempotency_key")
  if events.is_empty() {
    raise InvalidState(field="commit_events")
  }
  let mut advanced = projection
  for event in events {
    advanced = advanced.apply_event(event)
  }
  for intent in intents {
    validate_request_intent(advanced, intent)
  }
  @storage.CommitRequest::new(
    governance_record_version,
    governance_schema_version,
    projection.workflow,
    projection.revision,
    command_idempotency_key,
    events,
    intents,
  )
}
