///|
fn phase1b_effect_schema_v22(
  kind : String,
) -> @contracts.SchemaRef raise OrchestrationError {
  @contracts.SchemaRef::new(
    "closed-loop.effects",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("closed-loop.effects/{kind}/1")).text(),
  ) catch {
    _ => raise MalformedInput(field="guarded_effect_fact_schema")
  }
}

///|
fn prepare_guarded_effect_fact_commit_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : InFlightResolutionAuthorityV2,
  scope : String,
  target_ref : @contracts.RecordRef,
  event_id : String,
  event_kind : String,
  command_idempotency_key : String,
  payload_bytes : Bytes,
  evidence : Array[@contracts.EvidenceRef],
) -> @storage.CommitRequest raise OrchestrationError {
  current.require_legacy_intent_mutation_v22(authorization.intent_ref)
  authorization.validate_current(current)
  if authorization.scope != scope || authorization.target_ref != target_ref {
    raise CancellationPrecedenceViolation(field="inflight_resolution_scope")
  }
  let intent = current.work.effects.strict_intent_state_v2(
    authorization.intent_ref,
  ) catch {
    _ => raise ReplayBindingViolation(field="inflight_resolution_scope")
  }
  if intent.outbox_ref() != authorization.outbox_ref ||
    intent.external_idempotency_key() != authorization.external_idempotency_key ||
    intent.state() != authorization.effect_state ||
    !inflight_scope_allows_state_v22(scope, intent.state()) {
    raise ReplayBindingViolation(field="inflight_resolution_scope")
  }
  let payload = @contracts.WireEnvelope::new(
    "closed-loop.effects",
    "1.0.0",
    event_id,
    event_kind,
    intent.governed_subject(),
    phase1b_effect_schema_v22(event_kind),
    payload_bytes,
    "effects-protocol",
    "1.0.0",
    [],
    evidence,
    run_ref=current.root_binding.workflow,
    attempt_ref=intent.attempt_ref(),
    correlation_ref=current.root_binding.workflow.id(),
    causation_ref=intent.intent_ref().id(),
    idempotency_ref=target_ref.id(),
    previous_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="guarded_effect_fact_payload")
  }
  let event = @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    current.root_binding.workflow,
    event_id,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    target_ref.id(),
    payload,
    evidence,
    previous_event_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="guarded_effect_fact_event")
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
    _ => raise ReplayBindingViolation(field="guarded_effect_fact_commit")
  }
}

///|
fn prepare_dispatch_observation_from_inflight_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : InFlightResolutionAuthorityV2,
  event_id : String,
  command_idempotency_key : String,
  observation : @effects.DispatchObservation,
) -> @storage.CommitRequest raise OrchestrationError {
  if observation.intent_ref() != authorization.intent_ref ||
    observation.external_idempotency_key() !=
    authorization.external_idempotency_key {
    raise ReplayBindingViolation(field="guarded_dispatch_observation")
  }
  prepare_guarded_effect_fact_commit_v22(
    current,
    authorization,
    "dispatch.observe",
    observation.observation_ref(),
    event_id,
    "effect.dispatch.observed.v1",
    command_idempotency_key,
    observation.canonical_bytes(),
    [
      for value in observation.evidence() => value
    ],
  )
}

///|
fn require_guarded_dispatch_observation_current_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  guarded : GuardedDispatchObservationV2,
) -> Unit raise OrchestrationError {
  current.require_legacy_intent_mutation_v22(guarded.intent_ref)
  if !current.cancellation_authoritative {
    raise ReplayBindingViolation(
      field="cancellation_committed_governance_receipt_required",
    )
  }
  ignore(
    require_phase1b_self_address_v22(
      guarded.dispatch_authorization_ref,
      guarded_dispatch_authority_kind_v22,
      guarded.dispatch_authorization_bytes,
      "guarded_dispatch_authorization_integrity",
    ),
  )
  if guarded.observation.intent_ref() != guarded.intent_ref ||
    guarded.observation.external_idempotency_key() !=
    guarded.external_idempotency_key ||
    current.governance_revision != guarded.governance_revision ||
    current.governance_head_digest != guarded.governance_head_digest {
    raise ReplayBindingViolation(field="guarded_dispatch_observation")
  }
  match current.work.cancellation {
    None => {
      let open = current.open_work_authority()
      let replayed = current.guarded_dispatch_authorization(
        open,
        guarded.intent_ref,
      )
      if replayed.authorization_ref != guarded.dispatch_authorization_ref ||
        replayed.canonical != guarded.dispatch_authorization_bytes ||
        replayed.work_revision != guarded.work_revision ||
        replayed.work_head_digest != guarded.work_head_digest ||
        replayed.work_replay_digest != guarded.work_replay_digest {
        raise ReplayBindingViolation(field="guarded_dispatch_observation")
      }
    }
    Some(cancellation) =>
      if current.work.work_terminal is Some(_) ||
        cancellation.proposal.prefix_revision != guarded.work_revision ||
        cancellation.proposal.prefix_event_ref.digest() !=
        guarded.work_head_digest ||
        cancellation.proposal.prefix_replay_digest != guarded.work_replay_digest {
        raise CancellationPrecedenceViolation(
          field="guarded_dispatch_observation_prefix",
        )
      }
  }
  let intent = current.work.effects.strict_intent_state_v2(guarded.intent_ref) catch {
    _ => raise ReplayBindingViolation(field="guarded_dispatch_observation")
  }
  if intent.state() != DurableIntentDispatchEligible ||
    intent.outbox_ref() != guarded.outbox_ref ||
    intent.external_idempotency_key() != guarded.external_idempotency_key {
    raise ReplayBindingViolation(field="guarded_dispatch_observation")
  }
}

///|
/// Record only the inert fact returned by `dispatch_guarded_effect_v2`. If a
/// cancellation won the exact same-prefix race, the frozen dispatch prefix is
/// revalidated and no second dispatcher invocation occurs.
pub fn prepare_guarded_dispatch_observation_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  guarded : GuardedDispatchObservationV2,
  event_id : String,
  command_idempotency_key : String,
) -> @storage.CommitRequest raise OrchestrationError {
  require_guarded_dispatch_observation_current_v22(current, guarded)
  let authorization = current.inflight_resolution_authority(
    guarded.intent_ref,
    "dispatch.observe",
    guarded.observation.observation_ref(),
  )
  prepare_dispatch_observation_from_inflight_v22(
    current,
    authorization,
    event_id,
    command_idempotency_key,
    guarded.observation,
  )
}

///|
/// Record a receipt fact. It never invokes the external dispatcher.
pub fn prepare_guarded_effect_receipt_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : InFlightResolutionAuthorityV2,
  event_id : String,
  command_idempotency_key : String,
  receipt : @effects.EffectReceipt,
) -> @storage.CommitRequest raise OrchestrationError {
  if receipt.intent_ref() != authorization.intent_ref ||
    receipt.external_idempotency_key() != authorization.external_idempotency_key {
    raise ReplayBindingViolation(field="guarded_effect_receipt")
  }
  let kind = if receipt.outcome() == Unknown {
    "effect.outcome.unknown.v1"
  } else {
    "effect.receipt.recorded.v1"
  }
  prepare_guarded_effect_fact_commit_v22(
    current,
    authorization,
    "receipt.record",
    receipt.receipt_ref(),
    event_id,
    kind,
    command_idempotency_key,
    receipt.canonical_bytes(),
    [
      for value in receipt.evidence() => value
    ],
  )
}

///|
/// Record a reconciliation request for an exact unknown durable outcome.
pub fn prepare_guarded_reconciliation_request_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : InFlightResolutionAuthorityV2,
  event_id : String,
  command_idempotency_key : String,
  request : @effects.ReconciliationRequest,
) -> @storage.CommitRequest raise OrchestrationError {
  current.require_legacy_effect_protocol_v2()
  if request.intent_ref() != authorization.intent_ref ||
    request.external_idempotency_key() != authorization.external_idempotency_key {
    raise ReplayBindingViolation(field="guarded_reconciliation_request")
  }
  prepare_guarded_effect_fact_commit_v22(
    current,
    authorization,
    "reconciliation.request",
    request.request_ref(),
    event_id,
    "effect.reconciliation.requested.v1",
    command_idempotency_key,
    request.canonical_bytes(),
    [
      for value in request.evidence() => value
    ],
  )
}

///|
/// Record a reconciliation result for an exact pending reconciliation.
pub fn prepare_guarded_reconciliation_resolution_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : InFlightResolutionAuthorityV2,
  event_id : String,
  command_idempotency_key : String,
  reconciliation : @effects.ReconciliationRecord,
) -> @storage.CommitRequest raise OrchestrationError {
  current.require_legacy_effect_protocol_v2()
  if reconciliation.intent_ref() != authorization.intent_ref ||
    reconciliation.external_idempotency_key() !=
    authorization.external_idempotency_key {
    raise ReplayBindingViolation(field="guarded_reconciliation_resolution")
  }
  prepare_guarded_effect_fact_commit_v22(
    current,
    authorization,
    "reconciliation.resolve",
    reconciliation.reconciliation_ref(),
    event_id,
    "effect.reconciliation.resolved.v1",
    command_idempotency_key,
    reconciliation.canonical_bytes(),
    [
      for value in reconciliation.evidence() => value
    ],
  )
}
