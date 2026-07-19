///|
fn phase1b_prepare_effect_envelope_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  event_id : String,
  event_kind : String,
  subject : @contracts.RecordRef,
  payload_bytes : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  attempt_ref : @contracts.RecordRef,
  causation_ref : String,
  idempotency_ref : String,
) -> @contracts.WireEnvelope raise OrchestrationError {
  @contracts.WireEnvelope::new(
    "closed-loop.effects",
    "1.0.0",
    event_id,
    event_kind,
    subject,
    phase1b_effect_schema_v22(event_kind),
    payload_bytes,
    "effects-protocol",
    "1.0.0",
    [],
    evidence,
    run_ref=current.root_binding.workflow,
    attempt_ref~,
    correlation_ref=current.root_binding.workflow.id(),
    causation_ref~,
    idempotency_ref~,
    previous_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="guarded_new_work_payload")
  }
}

///|
/// Prepare a new attempt registration only from an exact current OpenWork guard.
pub fn prepare_guarded_attempt_registration_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  authorization : OpenWorkOperationAuthorizationV2,
  event_id : String,
  command_idempotency_key : String,
  registration : @effects.AttemptRegistration,
) -> @storage.CommitRequest raise OrchestrationError {
  authorization.require_current_scope(
    current,
    open,
    "attempt.register",
    registration.attempt_ref(),
  )
  guard current.work.prefix_event is Some(prefix_event) else {
    raise ReplayBindingViolation(field="guarded_attempt_prefix")
  }
  if registration.workflow() != current.root_binding.workflow ||
    registration.previous_digest() != current.work_head_digest ||
    registration.causal_event_ref() != prefix_event.event_ref() {
    raise ReplayBindingViolation(field="guarded_attempt_prefix")
  }
  let (latest_attempt, latest_intent) = current.work.effects.latest_attempt_intent_refs() catch {
    _ => raise ReplayBindingViolation(field="guarded_attempt_lineage")
  }
  match registration.retry_of_intent_ref() {
    None =>
      if latest_attempt is Some(_) || latest_intent is Some(_) {
        raise OrderingViolation(field="guarded_attempt_not_initial")
      }
    Some(source) =>
      if latest_intent != Some(source) {
        raise OrderingViolation(field="guarded_attempt_retry_source")
      }
  }
  let evidence = [ for value in registration.evidence() => value ]
  let payload = phase1b_prepare_effect_envelope_v22(
    current,
    event_id,
    "attempt.registered.v1",
    registration.governance().governed_subject(),
    registration.canonical_bytes(),
    evidence,
    registration.attempt_ref(),
    registration.causal_event_ref().id(),
    registration.idempotency_key(),
  )
  let event = @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    current.root_binding.workflow,
    event_id,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    registration.idempotency_key(),
    payload,
    evidence,
    previous_event_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="guarded_attempt_event")
  }
  @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    current.root_binding.workflow,
    current.work_revision,
    command_idempotency_key,
    [event],
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="guarded_attempt_commit")
  }
}

///|
/// Prepare the exact atomic event/outbox batch for one new effect intent.
pub fn prepare_guarded_effect_intent_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  authorization : OpenWorkOperationAuthorizationV2,
  event_id : String,
  outbox_intent_id : String,
  command_idempotency_key : String,
  intent : @effects.EffectIntent,
) -> @storage.CommitRequest raise OrchestrationError {
  authorization.require_current_scope(
    current,
    open,
    "effect.intent.commit",
    intent.intent_ref(),
  )
  if intent.workflow() != current.root_binding.workflow ||
    intent.previous_digest() != current.work_head_digest {
    raise ReplayBindingViolation(field="guarded_effect_intent_prefix")
  }
  let (latest_attempt, latest_intent) = current.work.effects.latest_attempt_intent_refs() catch {
    _ => raise ReplayBindingViolation(field="guarded_effect_intent_lineage")
  }
  if latest_attempt != Some(intent.attempt_ref()) || latest_intent is Some(_) {
    raise OrderingViolation(field="guarded_effect_intent_lineage")
  }
  let evidence = [ for value in intent.evidence() => value ]
  let payload = phase1b_prepare_effect_envelope_v22(
    current,
    event_id,
    "effect.intent.requested.v1",
    intent.governance().governed_subject(),
    intent.canonical_bytes(),
    evidence,
    intent.attempt_ref(),
    intent.attempt_ref().id(),
    intent.external_idempotency_key(),
  )
  let event = @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    current.root_binding.workflow,
    event_id,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    "effect-event/\{intent.external_idempotency_key()}",
    payload,
    evidence,
    previous_event_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="guarded_effect_intent_event")
  }
  let outbox = @storage.OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    outbox_intent_id,
    current.root_binding.workflow,
    event.event_ref(),
    intent.external_idempotency_key(),
    intent.effect_request(),
    evidence,
  ) catch {
    _ => raise MalformedInput(field="guarded_effect_intent_outbox")
  }
  @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    current.root_binding.workflow,
    current.work_revision,
    command_idempotency_key,
    [event],
    [outbox],
  ) catch {
    _ => raise ReplayBindingViolation(field="guarded_effect_intent_commit")
  }
}
