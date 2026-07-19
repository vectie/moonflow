///|
fn find_registration(
  catalog : ReplayCatalog,
  payload : Bytes,
) -> AttemptRegistration? {
  first(catalog.registrations, value => value.canonical_bytes() == payload)
}

///|
fn find_intent(catalog : ReplayCatalog, payload : Bytes) -> EffectIntent? {
  first(catalog.intents, value => value.canonical_bytes() == payload)
}

///|
fn find_observation(
  catalog : ReplayCatalog,
  payload : Bytes,
) -> DispatchObservation? {
  first(catalog.observations, value => value.canonical_bytes() == payload)
}

///|
fn find_receipt(catalog : ReplayCatalog, payload : Bytes) -> EffectReceipt? {
  first(catalog.receipts, value => value.canonical_bytes() == payload)
}

///|
fn find_reconciliation_request(
  catalog : ReplayCatalog,
  payload : Bytes,
) -> ReconciliationRequest? {
  first(catalog.reconciliation_requests, value => {
    value.canonical_bytes() == payload
  })
}

///|
fn find_reconciliation(
  catalog : ReplayCatalog,
  payload : Bytes,
) -> ReconciliationRecord? {
  first(catalog.reconciliations, value => value.canonical_bytes() == payload)
}

///|
fn catalog_contains_payload(catalog : ReplayCatalog, payload : Bytes) -> Bool {
  find_registration(catalog, payload) is Some(_) ||
  find_intent(catalog, payload) is Some(_) ||
  find_observation(catalog, payload) is Some(_) ||
  find_receipt(catalog, payload) is Some(_) ||
  find_reconciliation_request(catalog, payload) is Some(_) ||
  find_reconciliation(catalog, payload) is Some(_)
}

///|
fn require_event_binding(
  event : @storage.WorkflowEvent,
  event_kind : String,
  subject : @contracts.RecordRef,
  attempt_ref : @contracts.RecordRef,
  event_idempotency_key : String,
  envelope_idempotency_key : String,
  causation_ref : String,
  payload_previous_digest : @contracts.ContentDigest,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Unit raise EffectsError {
  let envelope = event.payload()
  if event.record_version() != effects_version() ||
    event.schema_version() != effects_version() {
    raise UnsupportedVersion(
      field="effect_event",
      version=event.record_version().text(),
    )
  }
  if envelope.contract_id() != effects_contract_id ||
    envelope.contract_version() != effects_version() ||
    envelope.schema() != effects_schema(event_kind) ||
    envelope.producer_id() != effects_producer_id ||
    envelope.producer_version() != effects_version() ||
    envelope.envelope_kind() != event_kind {
    raise DigestMismatch(field="event_contract_binding")
  }
  if envelope.envelope_id() != event.event_ref().id() {
    raise IdentityMismatch(field="event_envelope_identity")
  }
  if envelope.subject() != subject {
    raise IdentityMismatch(field="event_subject")
  }
  if envelope.run_ref() != Some(event.workflow()) ||
    envelope.correlation_ref() != Some(event.workflow().id()) ||
    envelope.stage_ref() is Some(_) {
    raise IdentityMismatch(field="event_workflow_binding")
  }
  if envelope.attempt_ref() != Some(attempt_ref) {
    raise IdentityMismatch(field="event_attempt")
  }
  if event.idempotency_key() != event_idempotency_key ||
    envelope.idempotency_ref() != Some(envelope_idempotency_key) {
    raise IdempotencyConflict(key=envelope_idempotency_key)
  }
  if envelope.causation_ref() != Some(causation_ref) {
    raise IdentityMismatch(field="event_causation")
  }
  if envelope.previous_digest() != Some(payload_previous_digest) ||
    event.previous_event_digest() != Some(payload_previous_digest) {
    raise DigestMismatch(field="event_payload_previous_digest")
  }
  if !same_evidence(event.evidence(), evidence) ||
    !same_evidence(envelope.evidence(), evidence) {
    raise EvidenceMismatch(field="event_evidence")
  }
  if !envelope.artifacts().is_empty() || !envelope.extensions().is_empty() {
    raise MalformedRecord(field="event_envelope_extras")
  }
}

///|
fn require_observation_identity(
  observation : DispatchObservation,
  intent : EffectIntent,
) -> Unit raise EffectsError {
  if observation.intent_ref != intent.intent_ref() ||
    observation.external_idempotency_key != intent.external_idempotency_key() {
    raise IdentityMismatch(field="dispatch_observation_intent")
  }
  if observation.fencing != intent.fencing() {
    raise FencingViolation(field="dispatch_observation_fencing")
  }
}

///|
fn require_receipt_identity(
  receipt : EffectReceipt,
  intent : EffectIntent,
) -> Unit raise EffectsError {
  if receipt.intent_ref != intent.intent_ref() ||
    receipt.intent_digest != intent.binding_digest() ||
    receipt.external_idempotency_key != intent.external_idempotency_key() ||
    receipt.attempt_ref != intent.attempt_ref() ||
    receipt.workflow != intent.workflow() ||
    receipt.capability_ref != intent.capability_ref() ||
    receipt.governed_subject != intent.governance().governed_subject() ||
    receipt.authority_grant_ref != intent.governance().authority_grant_ref() ||
    receipt.review_receipt_ref != intent.governance().review_receipt_ref() {
    raise IdentityMismatch(field="effect_receipt_intent")
  }
  if receipt.fencing != intent.fencing() {
    raise FencingViolation(field="effect_receipt_fencing")
  }
}

///|
fn current_projection(
  base : EffectsProjection,
  attempts : Array[AttemptRegistration],
  intents : Array[EffectIntent],
  eligible : Array[DispatchEligibleIntent],
  observations : Array[DispatchObservation],
  receipts : Array[EffectReceipt],
  receipt_event_refs : Array[@contracts.RecordRef],
  requests : Array[ReconciliationRequest],
  request_event_refs : Array[@contracts.RecordRef],
  reconciliations : Array[ReconciliationRecord],
  reconciliation_event_refs : Array[@contracts.RecordRef],
  entries : Array[ExternalIdempotencyEntry],
) -> EffectsProjection {
  build_projection(
    base.workflow,
    base.policy_ref,
    base.sequence,
    base.revision,
    base.last_event_digest,
    attempts,
    intents,
    eligible,
    observations,
    receipts,
    receipt_event_refs,
    requests,
    request_event_refs,
    reconciliations,
    reconciliation_event_refs,
    registry_from_entries(entries),
    base.replay_digest,
    base.strict_replay,
    base.strict_snapshot_digest,
  )
}

///|
/// Fold only an authoritative FLOW-4A replay. Catalog values merely decode
/// exact canonical payloads and cannot make an absent/torn pair eligible.
pub fn fold_authoritative_replay(
  empty : EffectsProjection,
  replay : @storage.ReplayResult,
  catalog : ReplayCatalog,
) -> EffectsProjection raise EffectsError {
  if replay.workflow() != empty.workflow {
    raise IdentityMismatch(field="replay_workflow")
  }
  let attempts : Array[AttemptRegistration] = []
  let intents : Array[EffectIntent] = []
  let eligible : Array[DispatchEligibleIntent] = []
  let observations : Array[DispatchObservation] = []
  let receipts : Array[EffectReceipt] = []
  let receipt_event_refs : Array[@contracts.RecordRef] = []
  let requests : Array[ReconciliationRequest] = []
  let request_event_refs : Array[@contracts.RecordRef] = []
  let reconciliations : Array[ReconciliationRecord] = []
  let reconciliation_event_refs : Array[@contracts.RecordRef] = []
  let entries : Array[ExternalIdempotencyEntry] = []
  let mut working = empty
  for event in replay.events() {
    let kind = event.payload().envelope_kind()
    let payload = event.payload().payload()
    match kind {
      "attempt.registered.v1" => {
        guard find_registration(catalog, payload) is Some(value) else {
          raise MalformedRecord(field="attempt_registration_payload")
        }
        require_event_binding(
          event,
          kind,
          value.governance().governed_subject(),
          value.attempt_ref(),
          value.idempotency_key(),
          value.idempotency_key(),
          value.causal_event_ref.id(),
          value.previous_digest,
          value.evidence(),
        )
        match
          first(attempts, prior => prior.attempt_ref() == value.attempt_ref()) {
          Some(prior) if prior != value =>
            raise IdempotencyConflict(key=value.idempotency_key())
          Some(_) => ()
          None => attempts.push(value)
        }
      }
      "effect.intent.requested.v1" => {
        guard find_intent(catalog, payload) is Some(value) else {
          raise MalformedRecord(field="effect_intent_payload")
        }
        working.require_intent(value)
        require_event_binding(
          event,
          kind,
          value.governed_subject,
          value.attempt_ref(),
          "effect-event/\{value.external_idempotency_key()}",
          value.external_idempotency_key(),
          value.attempt_ref().id(),
          value.previous_digest,
          value.evidence(),
        )
        let matching = replay
          .intents()
          .filter(outbox => {
            outbox.causative_event() == event.event_ref() &&
            outbox.workflow() == value.workflow()
          })
        if matching.length() != 1 {
          raise OutboxAtomicityViolation(field="event_outbox_cardinality")
        }
        let outbox = matching[0]
        if outbox.record_version() != effects_version() ||
          outbox.schema_version() != effects_version() ||
          outbox.workflow() != event.workflow() ||
          outbox.causative_event() != event.event_ref() ||
          outbox.idempotency_key() != value.external_idempotency_key() ||
          outbox.payload() != value.effect_request() ||
          !same_evidence(outbox.evidence(), value.evidence()) {
          raise OutboxAtomicityViolation(field="event_outbox_binding")
        }
        match
          first(entries, entry => entry.key == value.external_idempotency_key()) {
          Some(entry) if entry.intent_ref != value.intent_ref() ||
            entry.intent_digest != value.binding_digest() =>
            raise IdempotencyConflict(key=value.external_idempotency_key())
          Some(_) => ()
          None => {
            intents.push(value)
            entries.push({
              key: value.external_idempotency_key(),
              intent_ref: value.intent_ref(),
              intent_digest: value.binding_digest(),
              receipt_ref: None,
              outcome: None,
            })
            eligible.push({
              record_version: effects_version(),
              intent: value,
              authoritative_replay_digest: replay.replay_digest(),
            })
          }
        }
      }
      "effect.dispatch.observed.v1" => {
        guard find_observation(catalog, payload) is Some(value) else {
          raise MalformedRecord(field="dispatch_observation_payload")
        }
        guard intents.any(intent => intent.intent_ref() == value.intent_ref()) else {
          raise OrderingViolation(field="observation_before_intent")
        }
        guard first(intents, intent => intent.intent_ref() == value.intent_ref())
          is Some(intent) else {
          raise OrderingViolation(field="observation_before_intent")
        }
        require_observation_identity(value, intent)
        if working.state_for(value.intent_ref()) !=
          DurableIntentDispatchEligible {
          raise InvalidState(field="observation_wrong_current_state")
        }
        require_event_binding(
          event,
          kind,
          intent.governance().governed_subject(),
          intent.attempt_ref(),
          value.observation_ref().id(),
          value.observation_ref().id(),
          intent.intent_ref().id(),
          event.previous_event_digest().unwrap(),
          value.evidence,
        )
        match
          first(observations, prior => {
            prior.observation_ref() == value.observation_ref()
          }) {
          Some(prior) if prior.canonical_bytes() != value.canonical_bytes() =>
            raise IdempotencyConflict(key=value.observation_ref().id())
          Some(_) => ()
          None => {
            observations.push(value)
            eligible.retain(item => {
              item.intent().intent_ref() != value.intent_ref()
            })
          }
        }
      }
      "effect.receipt.recorded.v1" | "effect.outcome.unknown.v1" => {
        guard find_receipt(catalog, payload) is Some(value) else {
          raise MalformedRecord(field="effect_receipt_payload")
        }
        if kind == "effect.outcome.unknown.v1" && value.outcome() != Unknown {
          raise OutcomeConflict(field="unknown_event_outcome")
        }
        if kind == "effect.receipt.recorded.v1" && value.outcome() == Unknown {
          raise OutcomeConflict(field="known_event_outcome")
        }
        guard observations.any(item => item.intent_ref() == value.intent_ref()) else {
          raise OrderingViolation(field="receipt_before_observation")
        }
        guard first(intents, intent => intent.intent_ref() == value.intent_ref())
          is Some(intent) else {
          raise OrderingViolation(field="receipt_before_intent")
        }
        require_receipt_identity(value, intent)
        if working.state_for(value.intent_ref()) != DispatchObservationPending {
          raise InvalidState(field="receipt_wrong_current_state")
        }
        require_event_binding(
          event,
          kind,
          intent.governance().governed_subject(),
          intent.attempt_ref(),
          value.receipt_ref().id(),
          value.receipt_ref().id(),
          intent.intent_ref().id(),
          event.previous_event_digest().unwrap(),
          value.evidence,
        )
        match
          first(receipts, prior => prior.intent_ref() == value.intent_ref()) {
          Some(prior) if prior != value =>
            raise OutcomeConflict(field="terminal_receipt_replacement")
          Some(_) => ()
          None => {
            receipts.push(value)
            receipt_event_refs.push(event.event_ref())
            guard entries.search_by(entry => {
                entry.key == value.external_idempotency_key()
              })
              is Some(index) else {
              raise IdempotencyConflict(key=value.external_idempotency_key())
            }
            let entry = entries[index]
            entries[index] = {
              ..entry,
              receipt_ref: Some(value.receipt_ref()),
              outcome: Some(value.outcome()),
            }
          }
        }
      }
      "effect.reconciliation.requested.v1" => {
        guard find_reconciliation_request(catalog, payload) is Some(value) else {
          raise MalformedRecord(field="reconciliation_request_payload")
        }
        guard first(receipts, item => item.intent_ref() == value.intent_ref())
          is Some(receipt) &&
          receipt.outcome() == Unknown else {
          raise ReconciliationViolation(field="request_without_unknown")
        }
        if value.unknown_receipt_ref != receipt.receipt_ref() ||
          value.external_idempotency_key != receipt.external_idempotency_key() {
          raise ReconciliationViolation(field="request_unknown_identity")
        }
        if working.state_for(value.intent_ref()) !=
          UnknownOutcomeRequiresReconciliation {
          raise ReconciliationViolation(field="request_wrong_current_state")
        }
        guard first(intents, intent => intent.intent_ref() == value.intent_ref())
          is Some(intent) else {
          raise ReconciliationViolation(field="request_foreign_intent")
        }
        require_event_binding(
          event,
          kind,
          intent.governance().governed_subject(),
          intent.attempt_ref(),
          value.request_ref().id(),
          value.request_ref().id(),
          intent.intent_ref().id(),
          event.previous_event_digest().unwrap(),
          value.evidence,
        )
        if !requests.any(prior => prior.request_ref() == value.request_ref()) {
          requests.push(value)
          request_event_refs.push(event.event_ref())
        }
      }
      "effect.reconciliation.resolved.v1" => {
        guard find_reconciliation(catalog, payload) is Some(value) else {
          raise MalformedRecord(field="reconciliation_payload")
        }
        guard requests.any(item => item.request_ref() == value.request_ref) else {
          raise ReconciliationViolation(field="resolution_without_request")
        }
        guard first(requests, item => item.request_ref() == value.request_ref)
          is Some(request) else {
          raise ReconciliationViolation(field="resolution_without_request")
        }
        if value.intent_ref() != request.intent_ref() ||
          value.external_idempotency_key != request.external_idempotency_key {
          raise ReconciliationViolation(field="resolution_request_identity")
        }
        if working.state_for(value.intent_ref()) != ReconciliationRequestedState {
          raise ReconciliationViolation(field="resolution_wrong_current_state")
        }
        guard first(intents, intent => intent.intent_ref() == value.intent_ref())
          is Some(intent) else {
          raise ReconciliationViolation(field="resolution_foreign_intent")
        }
        require_event_binding(
          event,
          kind,
          intent.governance().governed_subject(),
          intent.attempt_ref(),
          value.reconciliation_ref().id(),
          value.reconciliation_ref().id(),
          intent.intent_ref().id(),
          event.previous_event_digest().unwrap(),
          value.evidence,
        )
        match
          first(reconciliations, prior => {
            prior.intent_ref() == value.intent_ref()
          }) {
          Some(prior) if prior.canonical_bytes() != value.canonical_bytes() =>
            raise ReconciliationViolation(field="resolution_replacement")
          Some(_) => ()
          None => {
            reconciliations.push(value)
            reconciliation_event_refs.push(event.event_ref())
          }
        }
      }
      _ =>
        if catalog_contains_payload(catalog, payload) {
          raise MalformedRecord(field="known_payload_unknown_wrapper")
        }
    }
    working = current_projection(
      working, attempts, intents, eligible, observations, receipts, receipt_event_refs,
      requests, request_event_refs, reconciliations, reconciliation_event_refs, entries,
    )
  }
  for outbox in replay.intents() {
    if catalog.intents.any(value => {
        value.external_idempotency_key() == outbox.idempotency_key()
      }) &&
      !replay
      .events()
      .any(event => {
        event.event_ref() == outbox.causative_event() &&
        event.payload().envelope_kind() == "effect.intent.requested.v1"
      }) {
      raise OutboxAtomicityViolation(field="outbox_without_event")
    }
  }
  let head = replay.head()
  if head.sequence() != replay.events().length().to_int64() ||
    head.revision() != replay.events().length().to_int64() {
    raise RevisionMismatch(
      expected=replay.events().length().to_int64(),
      actual=head.revision(),
    )
  }
  build_projection(
    empty.workflow,
    empty.policy_ref,
    head.sequence(),
    head.revision(),
    head.last_event_digest(),
    attempts,
    intents,
    eligible,
    observations,
    receipts,
    receipt_event_refs,
    requests,
    request_event_refs,
    reconciliations,
    reconciliation_event_refs,
    registry_from_entries(entries),
    Some(replay.replay_digest()),
    None,
    None,
  )
}

///|
fn prepare_fact_commit(
  projection : EffectsProjection,
  event_id : String,
  event_kind : String,
  subject : @contracts.RecordRef,
  attempt_ref : @contracts.RecordRef,
  causation_ref : String,
  idempotency_key : String,
  payload_bytes : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  command_idempotency_key : String,
) -> @storage.CommitRequest raise {
  let payload = event_envelope(
    event_id,
    event_kind,
    projection.workflow(),
    subject,
    payload_bytes,
    evidence,
    attempt_ref,
    causation_ref,
    idempotency_key,
    projection.last_event_digest().unwrap(),
  )
  let event = @storage.WorkflowEvent::new(
    effects_record_version,
    effects_schema_version,
    projection.workflow(),
    event_id,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    idempotency_key,
    payload,
    evidence,
    previous_event_digest=projection.last_event_digest().unwrap(),
  )
  @storage.CommitRequest::new(
    effects_record_version,
    effects_schema_version,
    projection.workflow(),
    projection.revision(),
    command_idempotency_key,
    [event],
    [],
  )
}

///|
fn prepare_dispatch_observation_commit(
  projection : EffectsProjection,
  event_id : String,
  command_idempotency_key : String,
  observation : DispatchObservation,
) -> @storage.CommitRequest raise {
  guard first(projection.intents, value => {
      value.intent_ref() == observation.intent_ref()
    })
    is Some(intent) else {
    raise OrderingViolation(field="observation_before_intent")
  }
  if projection.state_for(intent.intent_ref()) != DurableIntentDispatchEligible {
    raise InvalidState(field="intent_not_dispatch_eligible")
  }
  prepare_fact_commit(
    projection,
    event_id,
    "effect.dispatch.observed.v1",
    intent.governance().governed_subject(),
    intent.attempt_ref(),
    intent.intent_ref().id(),
    observation.observation_ref().id(),
    observation.canonical_bytes(),
    copy_readonly(observation.evidence),
    command_idempotency_key,
  )
}

///|
fn prepare_effect_receipt_commit(
  projection : EffectsProjection,
  event_id : String,
  command_idempotency_key : String,
  receipt : EffectReceipt,
) -> @storage.CommitRequest raise {
  guard first(projection.intents, value => {
      value.intent_ref() == receipt.intent_ref()
    })
    is Some(intent) else {
    raise OrderingViolation(field="receipt_before_intent")
  }
  if projection.state_for(intent.intent_ref()) != DispatchObservationPending {
    raise InvalidState(field="receipt_without_pending_observation")
  }
  let kind = if receipt.outcome() == Unknown {
    "effect.outcome.unknown.v1"
  } else {
    "effect.receipt.recorded.v1"
  }
  prepare_fact_commit(
    projection,
    event_id,
    kind,
    intent.governance().governed_subject(),
    intent.attempt_ref(),
    intent.intent_ref().id(),
    receipt.receipt_ref().id(),
    receipt.canonical_bytes(),
    copy_readonly(receipt.evidence),
    command_idempotency_key,
  )
}

///|
fn prepare_reconciliation_request_commit(
  projection : EffectsProjection,
  event_id : String,
  command_idempotency_key : String,
  request : ReconciliationRequest,
) -> @storage.CommitRequest raise {
  guard first(projection.intents, value => {
      value.intent_ref() == request.intent_ref()
    })
    is Some(intent) else {
    raise ReconciliationViolation(field="foreign_intent")
  }
  if projection.state_for(intent.intent_ref()) !=
    UnknownOutcomeRequiresReconciliation {
    raise ReconciliationViolation(field="outcome_not_unknown")
  }
  prepare_fact_commit(
    projection,
    event_id,
    "effect.reconciliation.requested.v1",
    intent.governance().governed_subject(),
    intent.attempt_ref(),
    intent.intent_ref().id(),
    request.request_ref().id(),
    request.canonical_bytes(),
    copy_readonly(request.evidence),
    command_idempotency_key,
  )
}

///|
fn prepare_reconciliation_resolution_commit(
  projection : EffectsProjection,
  event_id : String,
  command_idempotency_key : String,
  reconciliation : ReconciliationRecord,
) -> @storage.CommitRequest raise {
  guard first(projection.intents, value => {
      value.intent_ref() == reconciliation.intent_ref()
    })
    is Some(intent) else {
    raise ReconciliationViolation(field="foreign_intent")
  }
  if projection.state_for(intent.intent_ref()) != ReconciliationRequestedState {
    raise ReconciliationViolation(field="request_not_pending")
  }
  prepare_fact_commit(
    projection,
    event_id,
    "effect.reconciliation.resolved.v1",
    intent.governance().governed_subject(),
    intent.attempt_ref(),
    intent.intent_ref().id(),
    reconciliation.reconciliation_ref().id(),
    reconciliation.canonical_bytes(),
    copy_readonly(reconciliation.evidence),
    command_idempotency_key,
  )
}
