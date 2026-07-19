///|
fn find_schedule(
  catalog : OrchestrationCatalog,
  payload : Bytes,
) -> ScheduleIntent? {
  first(catalog.schedules, value => value.canonical_bytes() == payload)
}

///|
fn find_clock(catalog : OrchestrationCatalog, payload : Bytes) -> ClockInput? {
  first(catalog.clocks, value => value.canonical_bytes() == payload)
}

///|
fn find_claim(catalog : OrchestrationCatalog, payload : Bytes) -> LeaseClaim? {
  first(catalog.claims, value => value.canonical_bytes() == payload)
}

///|
fn find_renewal(
  catalog : OrchestrationCatalog,
  payload : Bytes,
) -> LeaseRenewal? {
  first(catalog.renewals, value => value.canonical_bytes() == payload)
}

///|
fn find_release(
  catalog : OrchestrationCatalog,
  payload : Bytes,
) -> LeaseRelease? {
  first(catalog.releases, value => value.canonical_bytes() == payload)
}

///|
fn find_expiry(catalog : OrchestrationCatalog, payload : Bytes) -> LeaseExpiry? {
  first(catalog.expiries, value => value.canonical_bytes() == payload)
}

///|
fn find_cancellation(
  catalog : OrchestrationCatalog,
  payload : Bytes,
) -> CancellationRecord? {
  first(catalog.cancellations, value => value.canonical_bytes() == payload)
}

///|
fn find_retry(catalog : OrchestrationCatalog, payload : Bytes) -> RetryLink? {
  first(catalog.retries, value => value.canonical_bytes() == payload)
}

///|
fn catalog_contains_payload(
  catalog : OrchestrationCatalog,
  payload : Bytes,
) -> Bool {
  find_schedule(catalog, payload) is Some(_) ||
  find_clock(catalog, payload) is Some(_) ||
  find_claim(catalog, payload) is Some(_) ||
  find_renewal(catalog, payload) is Some(_) ||
  find_release(catalog, payload) is Some(_) ||
  find_expiry(catalog, payload) is Some(_) ||
  find_cancellation(catalog, payload) is Some(_) ||
  find_retry(catalog, payload) is Some(_)
}

///|
fn require_event_binding(
  event : @storage.WorkflowEvent,
  event_kind : String,
  subject : @contracts.RecordRef,
  attempt_ref : @contracts.RecordRef,
  event_idempotency_key : String,
  causation_ref : @contracts.RecordRef,
  payload_previous_digest : @contracts.ContentDigest?,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.record_version() != orchestration_version() ||
    event.schema_version() != orchestration_version() {
    raise UnsupportedVersion(
      field="orchestration_event",
      version=event.record_version().text(),
    )
  }
  if envelope.contract_id() != orchestration_contract_id ||
    envelope.contract_version() != orchestration_version() ||
    envelope.schema() != orchestration_schema(event_kind) ||
    envelope.producer_id() != orchestration_producer_id ||
    envelope.producer_version() != orchestration_version() ||
    envelope.envelope_kind() != event_kind {
    raise ReplayBindingViolation(field="event_contract_schema_producer_kind")
  }
  if envelope.envelope_id() != event.event_ref().id() ||
    envelope.subject() != subject {
    raise IdentityMismatch(field="event_envelope_or_subject")
  }
  if envelope.run_ref() != Some(event.workflow()) ||
    envelope.correlation_ref() != Some(event.workflow().id()) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() != Some(attempt_ref) {
    raise WorkflowMismatch(field="event_workflow_attempt")
  }
  if event.idempotency_key() != event_idempotency_key ||
    envelope.idempotency_ref() != Some(event_idempotency_key) {
    raise IdempotencyConflict(key=event_idempotency_key)
  }
  if envelope.causation_ref() != Some(causation_ref.id()) {
    raise IdentityMismatch(field="event_causation")
  }
  if envelope.previous_digest() != payload_previous_digest {
    raise DigestMismatch(field="event_payload_previous_digest")
  }
  if !same_evidence(event.evidence(), evidence) ||
    !same_evidence(envelope.evidence(), evidence) {
    raise EvidenceMismatch(field="event_evidence")
  }
  if !envelope.artifacts().is_empty() || !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="event_unauthorized_extras")
  }
}

///|
fn exact_committed_clock(latest : ClockInput?, incoming : ClockInput) -> Bool {
  latest is Some(value) && value == incoming
}

///|
fn effect_blocking(value : ScheduleState) -> Bool {
  value == EffectObservationPending ||
  value == UnknownOutcomeRequiresReconciliation ||
  value == ReconciliationRequested ||
  value == CancellationRequestedOutcomeUnresolved ||
  terminal_effect_state(value)
}

///|
fn event_is_for_schedule(
  event : @storage.WorkflowEvent,
  schedule : ScheduleIntent,
) -> Bool {
  event.payload().attempt_ref() == Some(schedule.effect_intent().attempt_ref()) &&
  event.payload().subject() == schedule.governed_subject()
}

///|
fn observed_effect_state(
  kind : String,
  schedule : ScheduleIntent,
  effects_projection : @effects.EffectsProjection,
) -> ScheduleState? raise {
  match kind {
    "effect.dispatch.observed.v1" => Some(EffectObservationPending)
    "effect.receipt.recorded.v1" =>
      Some(effect_state(schedule, effects_projection))
    "effect.outcome.unknown.v1" => Some(UnknownOutcomeRequiresReconciliation)
    "effect.reconciliation.requested.v1" => Some(ReconciliationRequested)
    "effect.reconciliation.resolved.v1" =>
      Some(effect_state(schedule, effects_projection))
    _ => None
  }
}

///|
/// Reconstruct solely from exact authoritative FLOW-4A replay. Catalog values
/// are decoders; accepted FLOW-6 projection supplies effect facts only.
pub fn fold_orchestration_replay(
  empty : OrchestrationProjection,
  replay : @storage.ReplayResult,
  catalog : OrchestrationCatalog,
  effects_projection : @effects.EffectsProjection,
) -> OrchestrationProjection raise {
  if replay.workflow() != empty.workflow ||
    effects_projection.workflow() != empty.workflow {
    raise WorkflowMismatch(field="authoritative_replay")
  }
  let mut schedule : ScheduleIntent? = None
  let mut latest_clock : ClockInput? = None
  let mut state = ScheduleAbsent
  let mut current_claim : LeaseClaim? = None
  let mut current_owner : @contracts.RecordRef? = None
  let mut current_epoch = 0L
  let mut current_fencing = 0L
  let mut current_expires_at : Int64? = None
  let mut claim_active = false
  let mut claim_released = false
  let mut claim_expired = false
  let mut cancellation : CancellationRecord? = None
  let retries : Array[RetryLink] = []
  let mut working = empty
  for event in replay.events() {
    if event.sequence() != working.sequence + 1L ||
      event.revision() != working.revision + 1L ||
      event.previous_event_digest() != working.last_event_digest {
      raise RevisionMismatch(
        expected=working.revision + 1L,
        actual=event.revision(),
      )
    }
    let kind = event.payload().envelope_kind()
    let payload = event.payload().payload()
    match kind {
      "schedule.registered.v1" => {
        guard find_schedule(catalog, payload) is Some(value) else {
          raise ReplayBindingViolation(field="schedule_payload")
        }
        if schedule is Some(_) {
          raise IdempotencyConflict(key=value.idempotency_key())
        }
        if value.workflow() != empty.workflow ||
          value.policy_ref() != empty.policy_ref {
          raise PolicyMismatch(field="schedule_projection")
        }
        require_event_binding(
          event,
          kind,
          value.governed_subject(),
          value.effect_intent().attempt_ref(),
          value.idempotency_key(),
          value.causation_ref(),
          value.previous_digest(),
          value.evidence(),
        )
        schedule = Some(value)
        state = RegisteredWaiting
      }
      "schedule.clock.recorded.v1" => {
        guard schedule is Some(bound) else {
          raise OrderingViolation(field="clock_before_schedule")
        }
        guard find_clock(catalog, payload) is Some(value) else {
          raise ReplayBindingViolation(field="clock_payload")
        }
        if value.workflow() != bound.workflow() {
          raise WorkflowMismatch(field="clock_schedule")
        }
        match latest_clock {
          Some(previous) if value.logical_instant() < previous.logical_instant() =>
            raise ClockRegression(
              previous=previous.logical_instant(),
              incoming=value.logical_instant(),
            )
          Some(previous) if previous.clock_ref() == value.clock_ref() &&
            previous != value =>
            raise IdempotencyConflict(key=value.idempotency_key())
          _ => ()
        }
        require_event_binding(
          event,
          kind,
          bound.governed_subject(),
          bound.effect_intent().attempt_ref(),
          value.idempotency_key(),
          value.causation_ref(),
          value.previous_digest(),
          value.evidence(),
        )
        latest_clock = Some(value)
        if !effect_blocking(state) && cancellation is None {
          state = if claim_active {
            ClaimedRunning
          } else {
            state_from_clock(bound, value)
          }
        }
      }
      "schedule.lease.claimed.v1" => {
        guard schedule is Some(bound) else {
          raise OrderingViolation(field="claim_before_schedule")
        }
        guard find_claim(catalog, payload) is Some(value) else {
          raise ReplayBindingViolation(field="claim_payload")
        }
        if !exact_committed_clock(latest_clock, value.clock) {
          raise OrderingViolation(field="claim_without_exact_clock")
        }
        if state != DueUnclaimed && state != LeaseExpiredReclaimable {
          raise ScheduleStateViolation(field="claim_not_due")
        }
        if claim_active {
          raise ScheduleStateViolation(field="competing_claim")
        }
        if value.schedule_ref != bound.schedule_ref() ||
          value.workflow != bound.workflow() {
          raise IdentityMismatch(field="claim_schedule")
        }
        if value.lease_epoch <= current_epoch {
          raise LeaseEpochViolation(
            expected_greater_than=current_epoch,
            actual=value.lease_epoch,
          )
        }
        if value.fencing_token <= current_fencing {
          raise FencingViolation(
            expected_greater_than=current_fencing,
            actual=value.fencing_token,
          )
        }
        require_event_binding(
          event,
          kind,
          bound.governed_subject(),
          bound.effect_intent().attempt_ref(),
          value.idempotency_key,
          value.causation_ref,
          Some(value.previous_digest),
          value.evidence,
        )
        current_claim = Some(value)
        current_owner = Some(value.owner_ref)
        current_epoch = value.lease_epoch
        current_fencing = value.fencing_token
        current_expires_at = Some(value.expires_at)
        claim_active = true
        claim_released = false
        claim_expired = false
        state = ClaimedRunning
      }
      "schedule.lease.renewed.v1" => {
        guard schedule is Some(bound) && current_claim is Some(claim) else {
          raise OrderingViolation(field="renewal_without_claim")
        }
        guard find_renewal(catalog, payload) is Some(value) else {
          raise ReplayBindingViolation(field="renewal_payload")
        }
        if !claim_active ||
          state != ClaimedRunning ||
          !exact_committed_clock(latest_clock, value.clock) {
          raise ScheduleStateViolation(field="renewal_inactive")
        }
        if value.claim_ref != claim.claim_ref ||
          Some(value.owner_ref) != current_owner {
          raise LeaseOwnerViolation(field="renewal_owner_or_claim")
        }
        guard current_expires_at is Some(expires_at) else {
          raise RecoveryViolation(field="renewal_missing_expiry")
        }
        if value.clock.logical_instant() >= expires_at ||
          value.expires_at < expires_at {
          raise TtlViolation(field="renewal_expiry")
        }
        if value.lease_epoch <= current_epoch ||
          value.fencing_token <= current_fencing {
          raise FencingViolation(
            expected_greater_than=current_fencing,
            actual=value.fencing_token,
          )
        }
        require_event_binding(
          event,
          kind,
          bound.governed_subject(),
          bound.effect_intent().attempt_ref(),
          value.idempotency_key,
          value.causation_ref,
          Some(value.previous_digest),
          value.evidence,
        )
        current_epoch = value.lease_epoch
        current_fencing = value.fencing_token
        current_expires_at = Some(value.expires_at)
      }
      "schedule.lease.released.v1" => {
        guard schedule is Some(bound) && current_claim is Some(claim) else {
          raise OrderingViolation(field="release_without_claim")
        }
        guard find_release(catalog, payload) is Some(value) else {
          raise ReplayBindingViolation(field="release_payload")
        }
        if !claim_active ||
          !exact_committed_clock(latest_clock, value.clock) ||
          value.claim_ref != claim.claim_ref ||
          Some(value.owner_ref) != current_owner ||
          value.lease_epoch != current_epoch ||
          value.fencing_token != current_fencing {
          raise LeaseOwnerViolation(field="release_active_binding")
        }
        require_event_binding(
          event,
          kind,
          bound.governed_subject(),
          bound.effect_intent().attempt_ref(),
          value.idempotency_key,
          value.causation_ref,
          Some(value.previous_digest),
          value.evidence,
        )
        claim_active = false
        claim_released = true
        claim_expired = false
        if !effect_blocking(state) && cancellation is None {
          state = DueUnclaimed
        }
      }
      "schedule.lease.expired.v1" => {
        guard schedule is Some(bound) && current_claim is Some(claim) else {
          raise OrderingViolation(field="expiry_without_claim")
        }
        guard find_expiry(catalog, payload) is Some(value) else {
          raise ReplayBindingViolation(field="expiry_payload")
        }
        if !claim_active ||
          !exact_committed_clock(latest_clock, value.clock) ||
          value.claim_ref != claim.claim_ref ||
          Some(value.owner_ref) != current_owner ||
          value.lease_epoch != current_epoch ||
          value.fencing_token != current_fencing {
          raise LeaseOwnerViolation(field="expiry_active_binding")
        }
        guard current_expires_at is Some(expires_at) else {
          raise RecoveryViolation(field="expiry_missing_expiry")
        }
        if value.clock.logical_instant() < expires_at ||
          value.expires_at != expires_at {
          raise ScheduleStateViolation(field="expiry_before_exact_expiration")
        }
        require_event_binding(
          event,
          kind,
          bound.governed_subject(),
          bound.effect_intent().attempt_ref(),
          value.idempotency_key,
          value.causation_ref,
          Some(value.previous_digest),
          value.evidence,
        )
        claim_active = false
        claim_released = false
        claim_expired = true
        if !effect_blocking(state) && cancellation is None {
          state = LeaseExpiredReclaimable
        }
      }
      "schedule.cancelled.v1" => {
        guard schedule is Some(bound) else {
          raise OrderingViolation(field="cancellation_before_schedule")
        }
        guard find_cancellation(catalog, payload) is Some(value) else {
          raise ReplayBindingViolation(field="cancellation_payload")
        }
        if !exact_committed_clock(latest_clock, value.clock) {
          raise OrderingViolation(field="cancellation_without_exact_clock")
        }
        require_event_binding(
          event,
          kind,
          bound.governed_subject(),
          bound.effect_intent().attempt_ref(),
          value.idempotency_key,
          value.causation_ref,
          Some(value.previous_digest),
          value.evidence,
        )
        match cancellation {
          Some(prior) if prior == value => ()
          Some(_) => raise IdempotencyConflict(key=value.idempotency_key())
          None => cancellation = Some(value)
        }
        if terminal_effect_state(state) {
          ()
        } else if state == EffectObservationPending ||
          state == UnknownOutcomeRequiresReconciliation ||
          state == ReconciliationRequested {
          state = CancellationRequestedOutcomeUnresolved
        } else {
          claim_active = false
          state = CancelledBeforeWork
        }
      }
      "schedule.retry.linked.v1" => {
        guard schedule is Some(bound) else {
          raise OrderingViolation(field="retry_before_schedule")
        }
        guard find_retry(catalog, payload) is Some(value) else {
          raise ReplayBindingViolation(field="retry_payload")
        }
        if cancellation is Some(_) || state != ReconciledNotAppliedRetryEligible {
          raise RetryClassificationViolation(field="retry_current_state")
        }
        require_event_binding(
          event,
          kind,
          bound.governed_subject(),
          bound.effect_intent().attempt_ref(),
          value.idempotency_key,
          value.causation_ref,
          Some(value.previous_digest),
          value.evidence,
        )
        if retries.any(prior => prior.retry_ref() == value.retry_ref()) {
          raise IdempotencyConflict(key=value.idempotency_key)
        }
        retries.push(value)
        state = Terminal
      }
      _ => {
        if catalog_contains_payload(catalog, payload) {
          raise ReplayBindingViolation(field="known_payload_unknown_wrapper")
        }
        match schedule {
          Some(bound) if event_is_for_schedule(event, bound) =>
            match observed_effect_state(kind, bound, effects_projection) {
              Some(next) => {
                if terminal_effect_state(state) && next != state {
                  raise CancellationPrecedenceViolation(
                    field="terminal_effect_replacement",
                  )
                }
                state = next
              }
              None => ()
            }
          _ => ()
        }
      }
    }
    working = build_projection(
      empty.workflow,
      empty.policy_ref,
      event.sequence(),
      event.revision(),
      Some(event.event_ref().digest()),
      None,
      schedule,
      latest_clock,
      state,
      current_claim,
      current_owner,
      current_epoch,
      current_fencing,
      current_expires_at,
      claim_active,
      claim_released,
      claim_expired,
      cancellation,
      retries,
    )
  }
  let head = replay.head()
  if head.sequence() != working.sequence ||
    head.revision() != working.revision ||
    head.last_event_digest() != working.last_event_digest {
    raise RecoveryViolation(field="replay_head")
  }
  match schedule {
    Some(bound) => {
      let exact = effect_state(bound, effects_projection)
      if terminal_effect_state(exact) {
        state = exact
      } else if exact == UnknownOutcomeRequiresReconciliation ||
        exact == ReconciliationRequested ||
        exact == EffectObservationPending {
        state = if cancellation is Some(_) {
          CancellationRequestedOutcomeUnresolved
        } else {
          exact
        }
      } else if exact == ReconciledNotAppliedRetryEligible {
        state = if cancellation is Some(_) {
          Terminal
        } else {
          ReconciledNotAppliedRetryEligible
        }
      }
    }
    None => ()
  }
  build_projection(
    empty.workflow,
    empty.policy_ref,
    head.sequence(),
    head.revision(),
    head.last_event_digest(),
    Some(replay.replay_digest()),
    schedule,
    latest_clock,
    state,
    current_claim,
    current_owner,
    current_epoch,
    current_fencing,
    current_expires_at,
    claim_active,
    claim_released,
    claim_expired,
    cancellation,
    retries,
  )
}

///|
fn prepare_record_event(
  projection : OrchestrationProjection,
  event_id : String,
  event_kind : String,
  subject : @contracts.RecordRef,
  attempt_ref : @contracts.RecordRef,
  causation_ref : @contracts.RecordRef,
  idempotency_key : String,
  payload : Bytes,
  payload_previous_digest : @contracts.ContentDigest?,
  evidence : Array[@contracts.EvidenceRef],
) -> @storage.WorkflowEvent raise {
  if payload_previous_digest != projection.last_event_digest() {
    raise DigestMismatch(field="prepared_payload_previous_digest")
  }
  let envelope = event_envelope(
    event_id,
    event_kind,
    projection.workflow(),
    subject,
    payload,
    evidence,
    attempt_ref,
    causation_ref.id(),
    idempotency_key,
    payload_previous_digest,
  )
  let previous_event_digest = projection.last_event_digest()
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    projection.workflow(),
    event_id,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    idempotency_key,
    envelope,
    evidence,
    previous_event_digest?,
  )
}

///|
fn prepare_schedule_event(
  projection : OrchestrationProjection,
  event_id : String,
  schedule : ScheduleIntent,
) -> @storage.WorkflowEvent raise {
  if projection.schedule() is Some(_) ||
    schedule.workflow() != projection.workflow() {
    raise ScheduleStateViolation(field="schedule_already_present_or_foreign")
  }
  prepare_record_event(
    projection,
    event_id,
    "schedule.registered.v1",
    schedule.governed_subject(),
    schedule.effect_intent().attempt_ref(),
    schedule.causation_ref(),
    schedule.idempotency_key(),
    schedule.canonical_bytes(),
    schedule.previous_digest(),
    [
      for value in schedule.evidence() => value
    ],
  )
}

///|
fn prepare_clock_event(
  projection : OrchestrationProjection,
  event_id : String,
  clock : ClockInput,
) -> @storage.WorkflowEvent raise {
  guard projection.schedule() is Some(schedule) else {
    raise OrderingViolation(field="clock_before_schedule")
  }
  match projection.latest_clock() {
    Some(previous) if clock.logical_instant() < previous.logical_instant() =>
      raise ClockRegression(
        previous=previous.logical_instant(),
        incoming=clock.logical_instant(),
      )
    _ => ()
  }
  prepare_record_event(
    projection,
    event_id,
    "schedule.clock.recorded.v1",
    schedule.governed_subject(),
    schedule.effect_intent().attempt_ref(),
    clock.causation_ref(),
    clock.idempotency_key(),
    clock.canonical_bytes(),
    clock.previous_digest(),
    [
      for value in clock.evidence() => value
    ],
  )
}

///|
fn prepare_claim_event(
  projection : OrchestrationProjection,
  event_id : String,
  claim : LeaseClaim,
) -> @storage.WorkflowEvent raise {
  guard projection.schedule() is Some(schedule) else {
    raise OrderingViolation(field="claim_before_schedule")
  }
  if !exact_committed_clock(projection.latest_clock(), claim.clock) ||
    (
      projection.state() != DueUnclaimed &&
      projection.state() != LeaseExpiredReclaimable
    ) {
    raise ScheduleStateViolation(field="claim_not_due_with_exact_clock")
  }
  prepare_record_event(
    projection,
    event_id,
    "schedule.lease.claimed.v1",
    schedule.governed_subject(),
    schedule.effect_intent().attempt_ref(),
    claim.causation_ref,
    claim.idempotency_key,
    claim.canonical_bytes(),
    Some(claim.previous_digest),
    [
      for value in claim.evidence => value
    ],
  )
}

///|
fn prepare_renewal_event(
  projection : OrchestrationProjection,
  event_id : String,
  renewal : LeaseRenewal,
) -> @storage.WorkflowEvent raise {
  guard projection.schedule() is Some(schedule) else {
    raise OrderingViolation(field="renewal_before_schedule")
  }
  if projection.state() != ClaimedRunning ||
    !exact_committed_clock(projection.latest_clock(), renewal.clock) ||
    projection.current_claim.map(value => value.claim_ref()) !=
    Some(renewal.claim_ref) ||
    projection.current_owner != Some(renewal.owner_ref) ||
    renewal.lease_epoch <= projection.current_epoch ||
    renewal.fencing_token <= projection.current_fencing {
    raise LeaseOwnerViolation(field="renewal_current_binding")
  }
  prepare_record_event(
    projection,
    event_id,
    "schedule.lease.renewed.v1",
    schedule.governed_subject(),
    schedule.effect_intent().attempt_ref(),
    renewal.causation_ref,
    renewal.idempotency_key,
    renewal.canonical_bytes(),
    Some(renewal.previous_digest),
    [
      for value in renewal.evidence => value
    ],
  )
}

///|
fn prepare_release_event(
  projection : OrchestrationProjection,
  event_id : String,
  release : LeaseRelease,
) -> @storage.WorkflowEvent raise {
  guard projection.schedule() is Some(schedule) else {
    raise OrderingViolation(field="release_before_schedule")
  }
  if !projection.claim_active ||
    !exact_committed_clock(projection.latest_clock(), release.clock) ||
    projection.current_claim.map(value => value.claim_ref()) !=
    Some(release.claim_ref) ||
    projection.current_owner != Some(release.owner_ref) ||
    release.lease_epoch != projection.current_epoch ||
    release.fencing_token != projection.current_fencing {
    raise LeaseOwnerViolation(field="release_current_binding")
  }
  prepare_record_event(
    projection,
    event_id,
    "schedule.lease.released.v1",
    schedule.governed_subject(),
    schedule.effect_intent().attempt_ref(),
    release.causation_ref,
    release.idempotency_key,
    release.canonical_bytes(),
    Some(release.previous_digest),
    [
      for value in release.evidence => value
    ],
  )
}

///|
fn prepare_expiry_event(
  projection : OrchestrationProjection,
  event_id : String,
  expiry : LeaseExpiry,
) -> @storage.WorkflowEvent raise {
  guard projection.schedule() is Some(schedule) else {
    raise OrderingViolation(field="expiry_before_schedule")
  }
  if !projection.claim_active ||
    !exact_committed_clock(projection.latest_clock(), expiry.clock) ||
    projection.current_claim.map(value => value.claim_ref()) !=
    Some(expiry.claim_ref) ||
    projection.current_owner != Some(expiry.owner_ref) ||
    expiry.lease_epoch != projection.current_epoch ||
    expiry.fencing_token != projection.current_fencing {
    raise LeaseOwnerViolation(field="expiry_current_binding")
  }
  prepare_record_event(
    projection,
    event_id,
    "schedule.lease.expired.v1",
    schedule.governed_subject(),
    schedule.effect_intent().attempt_ref(),
    expiry.causation_ref,
    expiry.idempotency_key,
    expiry.canonical_bytes(),
    Some(expiry.previous_digest),
    [
      for value in expiry.evidence => value
    ],
  )
}

///|
fn prepare_cancellation_event(
  projection : OrchestrationProjection,
  event_id : String,
  cancellation : CancellationRecord,
) -> @storage.WorkflowEvent raise {
  guard projection.schedule() is Some(schedule) else {
    raise OrderingViolation(field="cancellation_before_schedule")
  }
  if !exact_committed_clock(projection.latest_clock(), cancellation.clock) {
    raise OrderingViolation(field="cancellation_without_exact_clock")
  }
  prepare_record_event(
    projection,
    event_id,
    "schedule.cancelled.v1",
    schedule.governed_subject(),
    schedule.effect_intent().attempt_ref(),
    cancellation.causation_ref,
    cancellation.idempotency_key,
    cancellation.canonical_bytes(),
    Some(cancellation.previous_digest),
    [
      for value in cancellation.evidence => value
    ],
  )
}

///|
fn prepare_retry_event(
  projection : OrchestrationProjection,
  event_id : String,
  retry : RetryLink,
) -> @storage.WorkflowEvent raise {
  guard projection.schedule() is Some(schedule) else {
    raise OrderingViolation(field="retry_before_schedule")
  }
  if projection.state() != ReconciledNotAppliedRetryEligible ||
    projection.cancellation is Some(_) {
    raise RetryClassificationViolation(field="retry_current_state")
  }
  prepare_record_event(
    projection,
    event_id,
    "schedule.retry.linked.v1",
    schedule.governed_subject(),
    schedule.effect_intent().attempt_ref(),
    retry.causation_ref,
    retry.idempotency_key,
    retry.canonical_bytes(),
    Some(retry.previous_digest),
    [
      for value in retry.evidence => value
    ],
  )
}
