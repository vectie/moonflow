///|
fn fixture_ref(kind : String, id : String) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode(id)).text(),
  )
}

///|
fn fixture_evidence(id : String) -> @contracts.EvidenceRef {
  try! @contracts.EvidenceRef::new(
    fixture_ref("evidence", id),
    fixture_ref("provenance", "source"),
    @contracts.sha256_digest(@utf8.encode("observed-{id}")).text(),
  )
}

///|
fn fixture_schema(kind : String) -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    "neutral.fixture",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("schema-{kind}")).text(),
  )
}

///|
fn fixture_envelope(
  id : String,
  kind : String,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence? : Array[@contracts.EvidenceRef] = [],
) -> @contracts.WireEnvelope {
  try! @contracts.WireEnvelope::new(
    "neutral.fixture",
    "1.0.0",
    id,
    kind,
    subject,
    fixture_schema(kind),
    payload,
    "neutral-fixture",
    "1.0.0",
    [],
    evidence,
  )
}

///|
struct FixturePreparedEffectCommit {
  intent : @effects.EffectIntent
  request : @storage.CommitRequest
}

///|
fn FixturePreparedEffectCommit::effect_intent(
  self : FixturePreparedEffectCommit,
) -> @effects.EffectIntent {
  self.intent
}

///|
fn FixturePreparedEffectCommit::commit_request(
  self : FixturePreparedEffectCommit,
) -> @storage.CommitRequest {
  self.request
}

///|
fn fixture_prepare_effect_commit(
  projection : @effects.EffectsProjection,
  event_id : String,
  outbox_id : String,
  command_id : String,
  intent : @effects.EffectIntent,
) -> FixturePreparedEffectCommit raise {
  let kind = "effect.intent.requested.v1"
  let evidence = [ for value in intent.evidence() => value ]
  let schema = @contracts.SchemaRef::new(
    "closed-loop.effects",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("closed-loop.effects/{kind}/1")).text(),
  )
  let envelope = @contracts.WireEnvelope::new(
    "closed-loop.effects",
    "1.0.0",
    event_id,
    kind,
    intent.governance().governed_subject(),
    schema,
    intent.canonical_bytes(),
    "effects-protocol",
    "1.0.0",
    [],
    evidence,
    run_ref=projection.workflow(),
    attempt_ref=intent.attempt_ref(),
    correlation_ref=projection.workflow().id(),
    causation_ref=intent.attempt_ref().id(),
    idempotency_ref=intent.external_idempotency_key(),
    previous_digest=projection.last_event_digest().unwrap(),
  )
  let event = @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    projection.workflow(),
    event_id,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    "effect-event/\{intent.external_idempotency_key()}",
    envelope,
    evidence,
    previous_event_digest=projection.last_event_digest().unwrap(),
  )
  let outbox = @storage.OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    outbox_id,
    projection.workflow(),
    event.event_ref(),
    intent.external_idempotency_key(),
    intent.effect_request(),
    evidence,
  )
  {
    intent,
    request: @storage.CommitRequest::new(
      "1.0.0",
      "1.0.0",
      projection.workflow(),
      projection.revision(),
      command_id,
      [event],
      [outbox],
    ),
  }
}

///|
fn fixture_prepare_attempt_registration_event(
  projection : @effects.EffectsProjection,
  event_id : String,
  registration : @effects.AttemptRegistration,
) -> @storage.WorkflowEvent raise {
  guard projection.last_event_digest() is Some(previous_digest) else {
    fail("fixture attempt missing prefix")
  }
  let kind = "attempt.registered.v1"
  let evidence = [ for value in registration.evidence() => value ]
  let schema = @contracts.SchemaRef::new(
    "closed-loop.effects",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("closed-loop.effects/{kind}/1")).text(),
  )
  let envelope = @contracts.WireEnvelope::new(
    "closed-loop.effects",
    "1.0.0",
    event_id,
    kind,
    registration.governance().governed_subject(),
    schema,
    registration.canonical_bytes(),
    "effects-protocol",
    "1.0.0",
    [],
    evidence,
    run_ref=projection.workflow(),
    attempt_ref=registration.attempt_ref(),
    correlation_ref=projection.workflow().id(),
    causation_ref=registration.causal_event_ref().id(),
    idempotency_ref=registration.idempotency_key(),
    previous_digest~,
  )
  @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    projection.workflow(),
    event_id,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    registration.idempotency_key(),
    envelope,
    evidence,
    previous_event_digest=previous_digest,
  )
}

///|
fn fixture_prepare_effect_fact_commit(
  projection : @effects.EffectsProjection,
  event_id : String,
  command_id : String,
  event_kind : String,
  target_ref : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef,
  payload_bytes : Bytes,
  evidence : Array[@contracts.EvidenceRef],
) -> @storage.CommitRequest raise {
  guard projection
    .intents()
    .search_by(value => value.intent_ref() == intent_ref)
    is Some(index) else {
    fail("fixture effect fact missing intent")
  }
  let intent = projection.intents()[index]
  let schema = @contracts.SchemaRef::new(
    "closed-loop.effects",
    "1.0.0",
    event_kind,
    "1.0.0",
    // The protocol schema digest deliberately binds this canonical literal.
    // Keep it byte-for-byte equal to effects::effects_schema.
    @contracts.sha256_digest(@utf8.encode("closed-loop.effects/{kind}/1")).text(),
  )
  let envelope = @contracts.WireEnvelope::new(
    "closed-loop.effects",
    "1.0.0",
    event_id,
    event_kind,
    intent.governance().governed_subject(),
    schema,
    payload_bytes,
    "effects-protocol",
    "1.0.0",
    [],
    evidence,
    run_ref=projection.workflow(),
    attempt_ref=intent.attempt_ref(),
    correlation_ref=projection.workflow().id(),
    causation_ref=intent.intent_ref().id(),
    idempotency_ref=target_ref.id(),
    previous_digest=projection.last_event_digest().unwrap(),
  )
  let event = @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    projection.workflow(),
    event_id,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    target_ref.id(),
    envelope,
    evidence,
    previous_event_digest=projection.last_event_digest().unwrap(),
  )
  @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    projection.workflow(),
    projection.revision(),
    command_id,
    [event],
    [],
  )
}

///|
fn fixture_prepare_dispatch_observation_commit(
  projection : @effects.EffectsProjection,
  event_id : String,
  command_id : String,
  observation : @effects.DispatchObservation,
) -> @storage.CommitRequest raise {
  fixture_prepare_effect_fact_commit(
    projection,
    event_id,
    command_id,
    "effect.dispatch.observed.v1",
    observation.observation_ref(),
    observation.intent_ref(),
    observation.canonical_bytes(),
    [
      for value in observation.evidence() => value
    ],
  )
}

///|
fn fixture_prepare_effect_receipt_commit(
  projection : @effects.EffectsProjection,
  event_id : String,
  command_id : String,
  receipt : @effects.EffectReceipt,
) -> @storage.CommitRequest raise {
  let kind = if receipt.outcome() == Unknown {
    "effect.outcome.unknown.v1"
  } else {
    "effect.receipt.recorded.v1"
  }
  fixture_prepare_effect_fact_commit(
    projection,
    event_id,
    command_id,
    kind,
    receipt.receipt_ref(),
    receipt.intent_ref(),
    receipt.canonical_bytes(),
    [
      for value in receipt.evidence() => value
    ],
  )
}

///|
fn fixture_prepare_reconciliation_request_commit(
  projection : @effects.EffectsProjection,
  event_id : String,
  command_id : String,
  request : @effects.ReconciliationRequest,
) -> @storage.CommitRequest raise {
  fixture_prepare_effect_fact_commit(
    projection,
    event_id,
    command_id,
    "effect.reconciliation.requested.v1",
    request.request_ref(),
    request.intent_ref(),
    request.canonical_bytes(),
    [
      for value in request.evidence() => value
    ],
  )
}

///|
fn fixture_prepare_reconciliation_resolution_commit(
  projection : @effects.EffectsProjection,
  event_id : String,
  command_id : String,
  reconciliation : @effects.ReconciliationRecord,
) -> @storage.CommitRequest raise {
  fixture_prepare_effect_fact_commit(
    projection,
    event_id,
    command_id,
    "effect.reconciliation.resolved.v1",
    reconciliation.reconciliation_ref(),
    reconciliation.intent_ref(),
    reconciliation.canonical_bytes(),
    [
      for value in reconciliation.evidence() => value
    ],
  )
}

///|
fn fixture_clone_event_position(
  event : @storage.WorkflowEvent,
  sequence : Int64,
  revision : Int64,
  previous_event_digest : @contracts.ContentDigest?,
) -> @storage.WorkflowEvent raise {
  let original = event.payload()
  let run_ref = original.run_ref()
  let stage_ref = original.stage_ref()
  let attempt_ref = original.attempt_ref()
  let correlation_ref = original.correlation_ref()
  let causation_ref = original.causation_ref()
  let idempotency_ref = Some(event.idempotency_key())
  let previous_digest = previous_event_digest
  let envelope = @contracts.WireEnvelope::new(
    original.contract_id(),
    original.contract_version().text(),
    original.envelope_id(),
    original.envelope_kind(),
    original.subject(),
    original.schema(),
    original.payload(),
    original.producer_id(),
    original.producer_version().text(),
    [
      for artifact in original.artifacts() => artifact
    ],
    [
      for evidence in original.evidence() => evidence
    ],
    run_ref?,
    stage_ref?,
    attempt_ref?,
    correlation_ref?,
    causation_ref?,
    idempotency_ref?,
    previous_digest?,
    extensions=[ for extension in original.extensions() => extension ],
  )
  @storage.WorkflowEvent::new(
    event.record_version().text(),
    event.schema_version().text(),
    event.workflow(),
    event.event_ref().id(),
    sequence,
    revision,
    event.idempotency_key(),
    envelope,
    [
      for evidence in event.evidence() => evidence
    ],
    previous_event_digest?,
  )
}

///|
struct OrchestrationFixture {
  policy : @governance.GovernancePolicy
  workflow : @contracts.RecordRef
  evidence : Array[@contracts.EvidenceRef]
  store : @storage.MemoryStore
  governance : @effects.GovernanceBinding
  attempt : @effects.AttemptRegistration
  intent : @effects.EffectIntent
  effects : @effects.EffectsProjection
}

///|
fn orchestration_fixture_with_governance_version(
  suffix : String,
  strict_v2 : Bool,
  workflow_override? : @contracts.RecordRef,
  policy_override? : @governance.GovernancePolicy,
  authority_kind? : String = "authority-ref",
  reviewer_kind? : String = "named-human-reviewer",
  root_registration? : ScheduleRegisteredV2,
  governed_subject_override? : @contracts.RecordRef,
  retry_policy_override? : RetryPolicyV2,
) -> OrchestrationFixture raise {
  let policy = policy_override.unwrap_or(
    @governance.GovernancePolicy::new(
      "policy-{suffix}",
      "1.0.0",
      "1.0.0",
      "1.0.0",
      ["authority-ref"],
      ["named-human-reviewer"],
      1,
      1,
      [Approved, Rejected, ChangesRequested],
    ),
  )
  let workflow = workflow_override.unwrap_or(
    fixture_ref("workflow", "workflow-" + suffix),
  )
  let evidence = [fixture_evidence("evidence-{suffix}")]
  let criteria = [fixture_ref("criterion", "criterion-{suffix}")]
  let attachment = @governance.EvidenceAttachment::new(
    policy,
    workflow,
    "attachment-{suffix}",
    "1.0.0",
    evidence,
    fixture_ref("criterion-set", "purpose-{suffix}"),
    1L,
  )
  let mut governance = @governance.GovernanceProjection::new(policy, workflow)
  let events : Array[@storage.WorkflowEvent] = []
  let event1 = @governance.prepare_event(
    governance,
    "gov-{suffix}-1",
    @governance.GovernanceAction::evidence_attached(
      attachment, "gov-key-{suffix}-1",
    ),
  )
  governance = governance.apply_event(event1)
  events.push(event1)
  let authority_subject = fixture_envelope(
    "authority-subject-{suffix}",
    "authority-subject",
    fixture_ref("subject", "authority-subject-{suffix}"),
    b"opaque",
    evidence~,
  )
  let authority_request = @governance.AuthorityRequest::new(
    policy,
    workflow,
    "authority-request-{suffix}",
    "1.0.0",
    attachment,
    authority_subject,
    criteria,
    evidence,
    10L,
    Some(1000L),
    2L,
    "gov-key-{suffix}-2",
  )
  let event2 = @governance.prepare_event(
    governance,
    "gov-{suffix}-2",
    @governance.GovernanceAction::authority_requested(authority_request),
  )
  governance = governance.apply_event(event2)
  events.push(event2)
  let authority = fixture_ref(authority_kind, "authority-{suffix}")
  let grant = @governance.AuthorityDecision::grant(
    policy,
    workflow,
    "authority-grant-{suffix}",
    "1.0.0",
    authority_request,
    fixture_envelope(
      "authority-proof-{suffix}", "authority-proof", authority, b"opaque",
    ),
    authority,
    20L,
    2L,
  )
  let event3 = @governance.prepare_event(
    governance,
    "gov-{suffix}-3",
    @governance.GovernanceAction::authority_decided(grant, "gov-key-{suffix}-3"),
  )
  governance = governance.apply_event(event3)
  events.push(event3)
  let subject = governed_subject_override.unwrap_or(
    fixture_ref("subject", "governed-{suffix}"),
  )
  let review_request = @governance.ReviewRequest::new(
    policy,
    workflow,
    "review-request-{suffix}",
    "1.0.0",
    authority_request,
    grant,
    criteria,
    evidence,
    fixture_envelope(
      "review-subject-{suffix}",
      "review-subject",
      subject,
      b"opaque",
      evidence~,
    ),
    30L,
    4L,
    "gov-key-{suffix}-4",
  )
  let event4 = @governance.prepare_event(
    governance,
    "gov-{suffix}-4",
    @governance.GovernanceAction::review_requested(review_request),
  )
  governance = governance.apply_event(event4)
  events.push(event4)
  let reviewer = fixture_ref(reviewer_kind, "reviewer-{suffix}")
  let review_decision = @governance.ReviewDecision::new(
    policy,
    workflow,
    "review-decision-{suffix}",
    "1.0.0",
    review_request,
    reviewer,
    fixture_envelope(
      "review-proof-{suffix}", "review-proof", reviewer, b"opaque",
    ),
    Approved,
    [@governance.CriterionFinding::new(criteria[0], Satisfied)],
    evidence,
    [],
    40L,
    5L,
  )
  let event5 = @governance.prepare_event(
    governance,
    "gov-{suffix}-5",
    @governance.GovernanceAction::review_decision_recorded(
      review_decision, "gov-key-{suffix}-5",
    ),
  )
  governance = governance.apply_event(event5)
  events.push(event5)
  let receipt = @governance.ReviewReceipt::bind(
    governance, "review-receipt-{suffix}", "1.0.0", 50L,
  )
  let event6 = @governance.prepare_event(
    governance,
    "gov-{suffix}-6",
    @governance.GovernanceAction::review_receipt_bound(
      receipt, "gov-key-{suffix}-6",
    ),
  )
  events.push(event6)
  // GovernanceBinding records a normalized governance-only replay digest.
  // Keep that proof source independent from the mixed root/effects stream;
  // root-prefixed fixtures re-position the same six records in the main store.
  let binding_store = @storage.MemoryStore::new()
  ignore(
    binding_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        0L,
        "governance-binding-{suffix}",
        events,
        [],
      ),
    ),
  )
  let store = @storage.MemoryStore::new()
  let committed_governance_events = match root_registration {
    None => {
      ignore(
        store.commit(
          @storage.CommitRequest::new(
            "1.0.0",
            "1.0.0",
            workflow,
            0L,
            "governance-{suffix}",
            events,
            [],
          ),
        ),
      )
      events
    }
    Some(registration) => {
      if registration.workflow() != workflow {
        raise OrchestrationError::WorkflowMismatch(
          field="fixture_root_registration_workflow",
        )
      }
      let root_request = flow7_prepare_initial_work_fixture(
        store.replay(workflow),
        registration,
        "fixture-root-{suffix}",
        retry_policy?=retry_policy_override,
      )
      ignore(store.commit(root_request))
      let shifted : Array[@storage.WorkflowEvent] = []
      let mut previous = root_request.events()[2].event_ref().digest()
      for index, event in events {
        let cloned = fixture_clone_event_position(
          event,
          4L + index.to_int64(),
          4L + index.to_int64(),
          Some(previous),
        )
        shifted.push(cloned)
        previous = cloned.event_ref().digest()
      }
      ignore(
        store.commit(
          @storage.CommitRequest::new(
            "1.0.0",
            "1.0.0",
            workflow,
            3L,
            "governance-{suffix}",
            shifted,
            [],
          ),
        ),
      )
      shifted
    }
  }
  let binding = if strict_v2 {
    @effects.GovernanceBinding::new_strict_v2(
      policy,
      binding_store.replay(workflow),
      authority_request,
      grant,
      review_request,
      review_decision,
      receipt,
    )
  } else {
    @effects.GovernanceBinding::new(
      policy,
      binding_store.replay(workflow),
      authority_request,
      grant,
      review_request,
      review_decision,
      receipt,
    )
  }
  let effects_empty = @effects.EffectsProjection::new(
    workflow,
    policy.policy_ref(),
  )
  let base = @effects.fold_authoritative_replay(
    effects_empty,
    store.replay(workflow),
    @effects.ReplayCatalog::new([], [], [], [], [], []),
  )
  let committed_governance_tail = committed_governance_events[5]
  let attempt = @effects.AttemptRegistration::new(
    "attempt-{suffix}",
    "1.0.0",
    workflow,
    committed_governance_tail,
    1L,
    fixture_envelope(
      "requested-{suffix}",
      "requested-work",
      subject,
      b"opaque-work",
      evidence~,
    ),
    evidence,
    binding,
    60L,
    "attempt-key-{suffix}",
    committed_governance_tail.event_ref().digest(),
  )
  let attempt_event = fixture_prepare_attempt_registration_event(
    base, "attempt-event-{suffix}", attempt,
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        store.head(workflow).revision(),
        "attempt-{suffix}",
        [attempt_event],
        [],
      ),
    ),
  )
  let after_attempt = @effects.fold_authoritative_replay(
    effects_empty,
    store.replay(workflow),
    @effects.ReplayCatalog::new([attempt], [], [], [], [], []),
  )
  let intent = @effects.EffectIntent::new(
    "intent-{suffix}",
    "1.0.0",
    attempt,
    binding,
    fixture_envelope(
      "effect-request-{suffix}",
      "effect-request",
      subject,
      b"opaque-effect",
      evidence~,
    ),
    evidence,
    "external-{suffix}",
    fixture_ref("capability", "capability-{suffix}"),
    "opaque-capability",
    70L,
    attempt.attempt_ref(),
    after_attempt.last_event_digest().unwrap(),
    true,
    fencing=@effects.FencingBinding::new(
      fixture_ref("fence", "fence-{suffix}"),
      1L,
      10L,
    ),
  )
  let prepared = fixture_prepare_effect_commit(
    after_attempt, "intent-event-{suffix}", "outbox-{suffix}", "intent-{suffix}",
    intent,
  )
  ignore(store.commit(prepared.commit_request()))
  let effects = @effects.fold_authoritative_replay(
    effects_empty,
    store.replay(workflow),
    @effects.ReplayCatalog::new([attempt], [intent], [], [], [], []),
  )
  {
    policy,
    workflow,
    evidence,
    store,
    governance: binding,
    attempt,
    intent,
    effects,
  }
}

///|
fn orchestration_fixture(suffix : String) -> OrchestrationFixture raise {
  orchestration_fixture_with_governance_version(suffix, false)
}

///|
fn orchestration_fixture_strict(suffix : String) -> OrchestrationFixture raise {
  orchestration_fixture_with_governance_version(suffix, true)
}

///|
fn commit_orchestration_event(
  store : @storage.MemoryStore,
  workflow : @contracts.RecordRef,
  event : @storage.WorkflowEvent,
  key : String,
) -> Unit raise {
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        event.revision() - 1L,
        key,
        [event],
        [],
      ),
    ),
  )
}

///|
fn catalog(
  schedules : Array[ScheduleIntent],
  clocks : Array[ClockInput],
  claims : Array[LeaseClaim],
  renewals? : Array[LeaseRenewal] = [],
  releases? : Array[LeaseRelease] = [],
  expiries? : Array[LeaseExpiry] = [],
  cancellations? : Array[CancellationRecord] = [],
) -> OrchestrationCatalog {
  OrchestrationCatalog::new(
    schedules,
    clocks,
    claims,
    renewals,
    releases,
    expiries,
    cancellations,
    [],
  )
}

///|
fn projection(
  fixture : OrchestrationFixture,
  catalog : OrchestrationCatalog,
) -> OrchestrationProjection raise {
  ignore(fixture.attempt.attempt_ordinal())
  fold_orchestration_replay(
    OrchestrationProjection::new(fixture.workflow, fixture.policy.policy_ref()),
    fixture.store.replay(fixture.workflow),
    catalog,
    fixture.effects,
  )
}

///|
test "FLOW-7A explicit clock, claim, renewal, and release" {
  let fixture = orchestration_fixture("happy")
  let empty_catalog = catalog([], [], [])
  let absent = projection(fixture, empty_catalog)
  assert_true(absent.state() is ScheduleAbsent)
  let schedule = ScheduleIntent::new(
    "schedule-happy",
    "1.0.0",
    fixture.workflow,
    fixture.policy.policy_ref(),
    fixture.intent.governance().governed_subject(),
    fixture.intent.governance(),
    fixture.intent,
    fixture.effects,
    100L,
    Some(200L),
    fixture.evidence,
    fixture.intent.intent_ref(),
    "schedule-key",
    previous_digest=absent.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_schedule_event(absent, "schedule-event", schedule),
    "schedule-command",
  )
  let schedules = [schedule]
  let clocks : Array[ClockInput] = []
  let claims : Array[LeaseClaim] = []
  let mut current = projection(fixture, catalog(schedules, clocks, claims))
  assert_true(current.state() is RegisteredWaiting)
  let pre = ClockInput::new(
    "clock-pre",
    "1.0.0",
    fixture.workflow,
    90L,
    fixture_ref("clock-source", "source-pre"),
    fixture.evidence,
    schedule.schedule_ref(),
    "clock-pre-key",
    previous_digest=current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_clock_event(current, "clock-pre-event", pre),
    "clock-pre-command",
  )
  clocks.push(pre)
  current = projection(fixture, catalog(schedules, clocks, claims))
  assert_true(current.state() is RegisteredWaiting)
  let due_clock = ClockInput::new(
    "clock-due",
    "1.0.0",
    fixture.workflow,
    100L,
    fixture_ref("clock-source", "source-due"),
    fixture.evidence,
    pre.clock_ref(),
    "clock-due-key",
    previous_digest=current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_clock_event(current, "clock-due-event", due_clock),
    "clock-due-command",
  )
  clocks.push(due_clock)
  current = projection(fixture, catalog(schedules, clocks, claims))
  assert_true(current.state() is DueUnclaimed)
  let claim = LeaseClaim::new(
    "claim-happy",
    "1.0.0",
    current.due_proof(),
    schedule,
    fixture_ref("owner", "owner-a"),
    due_clock,
    20L,
    1L,
    1L,
    "claim-key",
    fixture.evidence,
    due_clock.clock_ref(),
    current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_claim_event(current, "claim-event", claim),
    "claim-command",
  )
  claims.push(claim)
  current = projection(fixture, catalog(schedules, clocks, claims))
  assert_true(current.state() is ClaimedRunning)
  let renew_clock = ClockInput::new(
    "clock-renew",
    "1.0.0",
    fixture.workflow,
    110L,
    fixture_ref("clock-source", "source-renew"),
    fixture.evidence,
    claim.claim_ref(),
    "clock-renew-key",
    previous_digest=current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_clock_event(current, "clock-renew-event", renew_clock),
    "clock-renew-command",
  )
  clocks.push(renew_clock)
  current = projection(fixture, catalog(schedules, clocks, claims))
  let renewal = LeaseRenewal::new(
    "renewal-happy",
    "1.0.0",
    claim,
    current.claimed_proof(),
    renew_clock,
    30L,
    2L,
    2L,
    "renewal-key",
    fixture.evidence,
    renew_clock.clock_ref(),
    current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_renewal_event(current, "renewal-event", renewal),
    "renewal-command",
  )
  let renewals = [renewal]
  current = projection(fixture, catalog(schedules, clocks, claims, renewals~))
  assert_eq(current.claimed_proof().fencing_token(), 2L)
  let release_clock = ClockInput::new(
    "clock-release",
    "1.0.0",
    fixture.workflow,
    115L,
    fixture_ref("clock-source", "source-release"),
    fixture.evidence,
    renewal.renewal_ref(),
    "clock-release-key",
    previous_digest=current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_clock_event(current, "clock-release-event", release_clock),
    "clock-release-command",
  )
  clocks.push(release_clock)
  current = projection(fixture, catalog(schedules, clocks, claims, renewals~))
  let release = LeaseRelease::new(
    "release-happy",
    "1.0.0",
    claim,
    current.claimed_proof(),
    release_clock,
    "release-key",
    fixture.evidence,
    release_clock.clock_ref(),
    current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_release_event(current, "release-event", release),
    "release-command",
  )
  current = projection(
    fixture,
    catalog(schedules, clocks, claims, renewals~, releases=[release]),
  )
  assert_true(current.state() is DueUnclaimed)
  let reclaim = LeaseClaim::new(
    "claim-reclaim",
    "1.0.0",
    current.due_proof(),
    schedule,
    fixture_ref("owner", "owner-b"),
    release_clock,
    10L,
    3L,
    3L,
    "claim-reclaim-key",
    fixture.evidence,
    release.claim_ref(),
    current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_claim_event(current, "claim-reclaim-event", reclaim),
    "claim-reclaim-command",
  )
  claims.push(reclaim)
  current = projection(
    fixture,
    catalog(schedules, clocks, claims, renewals~, releases=[release]),
  )
  assert_true(current.state() is ClaimedRunning)
  let expiry_clock = ClockInput::new(
    "clock-expiry",
    "1.0.0",
    fixture.workflow,
    125L,
    fixture_ref("clock-source", "source-expiry"),
    fixture.evidence,
    reclaim.claim_ref(),
    "clock-expiry-key",
    previous_digest=current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_clock_event(current, "clock-expiry-event", expiry_clock),
    "clock-expiry-command",
  )
  clocks.push(expiry_clock)
  current = projection(
    fixture,
    catalog(schedules, clocks, claims, renewals~, releases=[release]),
  )
  let expiry = LeaseExpiry::new(
    "expiry-reclaim",
    "1.0.0",
    reclaim,
    current.claimed_proof(),
    expiry_clock,
    "expiry-key",
    fixture.evidence,
    expiry_clock.clock_ref(),
    current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_expiry_event(current, "expiry-event", expiry),
    "expiry-command",
  )
  current = projection(
    fixture,
    catalog(schedules, clocks, claims, renewals~, releases=[release], expiries=[
      expiry,
    ]),
  )
  assert_true(current.state() is LeaseExpiredReclaimable)
  let later = LeaseClaim::new(
    "claim-later",
    "1.0.0",
    current.due_proof(),
    schedule,
    fixture_ref("owner", "owner-c"),
    expiry_clock,
    20L,
    4L,
    4L,
    "claim-later-key",
    fixture.evidence,
    expiry.expiry_ref(),
    current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_claim_event(current, "claim-later-event", later),
    "claim-later-command",
  )
  claims.push(later)
  current = projection(
    fixture,
    catalog(schedules, clocks, claims, renewals~, releases=[release], expiries=[
      expiry,
    ]),
  )
  assert_true(current.state() is ClaimedRunning)
  assert_eq(current.claimed_proof().fencing_token(), 4L)
  let cancellation = CancellationRecord::new(
    "cancellation-happy",
    "1.0.0",
    schedule,
    expiry_clock,
    fixture_ref("cancellation-reason", "reason"),
    "cancellation-key",
    fixture.evidence,
    later.claim_ref(),
    current.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_cancellation_event(current, "cancellation-event", cancellation),
    "cancellation-command",
  )
  current = projection(
    fixture,
    catalog(
      schedules,
      clocks,
      claims,
      renewals~,
      releases=[release],
      expiries=[expiry],
      cancellations=[cancellation],
    ),
  )
  assert_true(current.state() is CancelledBeforeWork)
  inspect(
    schedule.binding_digest().text(),
    content=(
      #|sha256:3068aa937bbd0b522e887cdfefb289da3ff4e972f0a8d303712fb39bc757ac76
    ),
  )
  inspect(
    due_clock.binding_digest().text(),
    content=(
      #|sha256:2170d7b9cc3e6209cc452a90e23e26b9ae1f0ac137b0fead6bd971c0e671b90c
    ),
  )
  inspect(
    claim.binding_digest().text(),
    content=(
      #|sha256:a7e24933897a6f7f4f52d2a6b7e47454432cf61e9837199ced7fbd2ee4c71e20
    ),
  )
  inspect(
    renewal.binding_digest().text(),
    content=(
      #|sha256:4ae327d7e53e559b673113a3501b949385d3448cc23efe2a1565a9ea2b64d41b
    ),
  )
  inspect(
    release.binding_digest().text(),
    content=(
      #|sha256:253790fdbba42bb8680821b66391683a0be1414efb2dfc1a05ffe3e9ec536a4d
    ),
  )
  inspect(
    expiry.binding_digest().text(),
    content=(
      #|sha256:708ae056395a2d562dc8cad4307602956c93312ff1c17b5575ba677e2136e2bd
    ),
  )
  inspect(
    current.state_digest().text(),
    content=(
      #|sha256:4a6862bae10f8ff1ecd3c8bff66a08d7ed8c602db3490249e2cfe7fc89d2b489
    ),
  )
  inspect(
    fixture.effects.registry().state_digest().text(),
    content=(
      #|sha256:71d20faa3e71a07c90f85ce02d8aaed5a55dd7867a0b4445662180d064131ecf
    ),
  )
  assert_true(
    (try! fixture.effects.state_for(fixture.intent.intent_ref())) ==
    @effects.DurableIntentDispatchEligible,
  )
  try current.due_proof() catch {
    ScheduleStateViolation(field="not_due_or_reclaimable") => ()
    _ => fail("unexpected cancelled due-proof error")
  } noraise {
    _ => fail("cancelled schedule produced due proof")
  }
}

///|
test "FLOW-7A deterministic retry timing and forbidden inference classes" {
  let workflow = fixture_ref("workflow", "retry-vectors")
  let source = fixture_ref("source", "clock-source")
  let cause = fixture_ref("cause", "clock-cause")
  let clock = ClockInput::new(
    "clock-retry",
    "1.0.0",
    workflow,
    1000L,
    source,
    [],
    cause,
    "clock-key",
  )
  let policy = RetryPolicy::new(
    "retry-policy",
    "1.0.0",
    5L,
    4L,
    10L,
    100L,
    2L,
    1L,
    7L,
    @contracts.sha256_digest(b"stable-seed"),
    ["generic-transient"],
  )
  let schedule_ref = fixture_ref("orchestration-schedule", "retry-schedule")
  let timing = RetryTiming::compute(policy, schedule_ref, 2L, 1L, clock)
  let repeated = RetryTiming::compute(policy, schedule_ref, 2L, 1L, clock)
  assert_true(timing.binding_digest() == repeated.binding_digest())
  assert_true(timing.delay() >= 20L && timing.delay() <= 27L)
  assert_eq(timing.eligible_at(), 1000L + timing.delay())
  assert_true(policy.allows(KnownFailureClass("generic-transient")))
  assert_true(policy.allows(ReconciledNotApplied))
  assert_false(policy.allows(UnknownOutcome))
  assert_false(policy.allows(MissingReceipt))
  assert_false(policy.allows(ObservationTimeout))
  assert_false(policy.allows(ProcessCrash))
  assert_false(policy.allows(LeaseExpired))
  assert_false(policy.allows(ElapsedTimeOnly))
  inspect(
    policy.binding_digest().text(),
    content=(
      #|sha256:71376a5039bf76fec5e4c60022da589d89bc5a7fdbf78add44e8d3994532d14b
    ),
  )
  inspect(
    clock.binding_digest().text(),
    content=(
      #|sha256:e3d49d967b20dc62268c4fa49a43c9e72e89abd884c6e9cb61fa1a273e27b666
    ),
  )
  inspect(
    timing.binding_digest().text(),
    content=(
      #|sha256:8772f5a957c698128eafd9a668056040c260444958afcd669d3e482c331acdb4
    ),
  )
}

///|
test "FLOW-7A checked clock, retry, and TTL negatives" {
  let workflow = fixture_ref("workflow", "negative")
  let source = fixture_ref("source", "negative-source")
  let cause = fixture_ref("cause", "negative-cause")
  try
    ClockInput::new(
      "negative-clock",
      "1.0.0",
      workflow,
      -1L,
      source,
      [],
      cause,
      "negative-key",
    )
  catch {
    MalformedInput(field="logical_instant") => ()
    _ => fail("unexpected negative-clock error")
  } noraise {
    _ => fail("negative clock accepted")
  }
  try
    RetryPolicy::new(
      "bad-policy",
      "1.0.0",
      1L,
      1L,
      0L,
      0L,
      1L,
      1L,
      0L,
      @contracts.sha256_digest(b"seed"),
      [],
    )
  catch {
    RetryBoundViolation(field="maximum_retry_count") => ()
    _ => fail("unexpected retry-bound error")
  } noraise {
    _ => fail("invalid retry bound accepted")
  }
}

///|
test "FLOW-7A unknown outcome remains blocked through exact reconciliation" {
  let fixture = orchestration_fixture("unknown")
  let absent = projection(fixture, catalog([], [], []))
  let schedule = ScheduleIntent::new(
    "schedule-unknown",
    "1.0.0",
    fixture.workflow,
    fixture.policy.policy_ref(),
    fixture.intent.governance().governed_subject(),
    fixture.intent.governance(),
    fixture.intent,
    fixture.effects,
    100L,
    Some(300L),
    fixture.evidence,
    fixture.intent.intent_ref(),
    "schedule-unknown-key",
    previous_digest=absent.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_schedule_event(absent, "schedule-unknown-event", schedule),
    "schedule-unknown-command",
  )
  let effects_empty = @effects.EffectsProjection::new(
    fixture.workflow,
    fixture.policy.policy_ref(),
  )
  let effects_catalog0 = @effects.ReplayCatalog::new(
    [fixture.attempt],
    [fixture.intent],
    [],
    [],
    [],
    [],
  )
  let after_schedule = @effects.fold_authoritative_replay(
    effects_empty,
    fixture.store.replay(fixture.workflow),
    effects_catalog0,
  )
  let observation = @effects.DispatchObservation::new(
    "dispatch-unknown",
    fixture.intent,
    fixture_envelope(
      "dispatch-observation-unknown",
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      b"opaque-observation",
      evidence=fixture.evidence,
    ),
    110L,
    fixture.evidence,
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_dispatch_observation_commit(
        after_schedule, "dispatch-unknown-event", "dispatch-unknown-command", observation,
      ),
    ),
  )
  let effects_catalog1 = @effects.ReplayCatalog::new(
    [fixture.attempt],
    [fixture.intent],
    [observation],
    [],
    [],
    [],
  )
  let after_observation = @effects.fold_authoritative_replay(
    effects_empty,
    fixture.store.replay(fixture.workflow),
    effects_catalog1,
  )
  let observed_projection = fold_orchestration_replay(
    OrchestrationProjection::new(fixture.workflow, fixture.policy.policy_ref()),
    fixture.store.replay(fixture.workflow),
    catalog([schedule], [], []),
    after_observation,
  )
  assert_true(observed_projection.state() is EffectObservationPending)
  let receipt = @effects.EffectReceipt::new(
    "receipt-unknown",
    "1.0.0",
    fixture.intent,
    fixture_envelope(
      "receipt-envelope-unknown",
      "effect-receipt",
      fixture.intent.governance().governed_subject(),
      b"opaque-receipt",
      evidence=fixture.evidence,
    ),
    Unknown,
    120L,
    fixture.evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_effect_receipt_commit(
        after_observation, "receipt-unknown-event", "receipt-unknown-command", receipt,
      ),
    ),
  )
  let effects_catalog2 = @effects.ReplayCatalog::new(
    [fixture.attempt],
    [fixture.intent],
    [observation],
    [receipt],
    [],
    [],
  )
  let after_unknown = @effects.fold_authoritative_replay(
    effects_empty,
    fixture.store.replay(fixture.workflow),
    effects_catalog2,
  )
  let unknown_projection = fold_orchestration_replay(
    OrchestrationProjection::new(fixture.workflow, fixture.policy.policy_ref()),
    fixture.store.replay(fixture.workflow),
    catalog([schedule], [], []),
    after_unknown,
  )
  assert_true(
    unknown_projection.state() is UnknownOutcomeRequiresReconciliation,
  )
  let request = @effects.ReconciliationRequest::new(
    "reconcile-request-unknown",
    fixture.intent,
    receipt,
    130L,
    fixture.evidence,
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_reconciliation_request_commit(
        after_unknown, "reconcile-request-event", "reconcile-request-command", request,
      ),
    ),
  )
  let effects_catalog3 = @effects.ReplayCatalog::new(
    [fixture.attempt],
    [fixture.intent],
    [observation],
    [receipt],
    [request],
    [],
  )
  let during = @effects.fold_authoritative_replay(
    effects_empty,
    fixture.store.replay(fixture.workflow),
    effects_catalog3,
  )
  let during_projection = fold_orchestration_replay(
    OrchestrationProjection::new(fixture.workflow, fixture.policy.policy_ref()),
    fixture.store.replay(fixture.workflow),
    catalog([schedule], [], []),
    during,
  )
  assert_true(during_projection.state() is ReconciliationRequested)
  let resolution = @effects.ReconciliationRecord::new(
    "reconcile-resolution-unknown",
    fixture.intent,
    request,
    ReconciledNotApplied,
    fixture_envelope(
      "reconcile-observation-unknown",
      "reconciliation-observation",
      fixture.intent.governance().governed_subject(),
      b"opaque-reconciliation",
      evidence=fixture.evidence,
    ),
    140L,
    fixture.evidence,
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_reconciliation_resolution_commit(
        during, "reconcile-resolution-event", "reconcile-resolution-command", resolution,
      ),
    ),
  )
  let resolved = @effects.fold_authoritative_replay(
    effects_empty,
    fixture.store.replay(fixture.workflow),
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [receipt],
      [request],
      [resolution],
    ),
  )
  let resolved_projection = fold_orchestration_replay(
    OrchestrationProjection::new(fixture.workflow, fixture.policy.policy_ref()),
    fixture.store.replay(fixture.workflow),
    catalog([schedule], [], []),
    resolved,
  )
  assert_true(resolved_projection.state() is ReconciledNotAppliedRetryEligible)
}
