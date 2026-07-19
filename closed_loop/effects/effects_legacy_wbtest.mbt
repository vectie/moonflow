///|
fn test_ref(kind : String, id : String) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode(id)).text(),
  )
}

///|
fn test_evidence(id : String) -> @contracts.EvidenceRef {
  try! @contracts.EvidenceRef::new(
    test_ref("evidence", id),
    test_ref("provenance", "source-1"),
    @contracts.sha256_digest(@utf8.encode("observed-\{id}")).text(),
  )
}

///|
fn test_schema(kind : String) -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    "neutral.fixture",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("schema-\{kind}")).text(),
  )
}

///|
fn test_envelope(
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
    test_schema(kind),
    payload,
    "neutral-fixture",
    "1.0.0",
    [],
    evidence,
  )
}

///|
fn test_retry_plan(
  attempt_id : String,
  attempt_key : String,
  attempt_ordinal : Int64,
  requested_work : @contracts.WireEnvelope,
  receipt : CommittedRetryEligibilityReceiptV2,
  governance : GovernanceBinding,
  causal_event : @storage.WorkflowEvent,
) -> @retry_authority.RetryPlanProposalV2 raise {
  let policy_bytes = @utf8.encode("test-retry-policy-{attempt_id}")
  let policy_digest = @contracts.sha256_digest(policy_bytes)
  let policy_ref = @contracts.RecordRef::new(
    "orchestration-retry-policy-v2",
    "policy-{attempt_id}",
    "1.0.0",
    policy_digest.text(),
  )
  let timing_bytes = @utf8.encode("test-retry-timing-{attempt_id}")
  let timing_digest = @contracts.sha256_digest(timing_bytes)
  let admission_bytes = @utf8.encode("test-admission-{attempt_id}")
  let admission_digest = @contracts.sha256_digest(admission_bytes)
  let admission_ref = @contracts.RecordRef::new(
    "eligible-authorization-proof-v2",
    "admission-{attempt_id}",
    "1.0.0",
    admission_digest.text(),
  )
  let requested_ref = @contracts.RecordRef::new(
    "requested-work",
    requested_work.envelope_id(),
    "1.0.0",
    requested_work.envelope_digest().text(),
  )
  let due_at = receipt.source_observed_at() + 1L
  let effective_deadline = match governance.authority_expires_at() {
    Some(value) => value - 1L
    None => due_at + 1000L
  }
  let request = @retry_authority.RetryScheduleRequestV2::new(
    "request-{attempt_id}",
    receipt.workflow(),
    receipt.receipt_ref(),
    receipt.digest(),
    receipt.canonical_bytes(),
    policy_ref,
    policy_digest,
    policy_bytes,
    timing_digest,
    timing_bytes,
    due_at,
    receipt.attempt_count(),
    receipt.retry_count(),
    receipt.retry_ordinal(),
    receipt.cause_key(),
    requested_ref,
    requested_work.envelope_digest(),
    "logical-attempt-{attempt_id}",
    "1.0.0",
    "logical-effect-{attempt_id}",
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("artifact-{attempt_id}")),
    attempt_id,
    attempt_ordinal,
    attempt_key,
    "schedule-{attempt_id}",
    "schedule-key-{attempt_id}",
    None,
    effective_deadline,
    effective_deadline,
    effective_deadline,
    governance.authority_expires_at(),
    causal_event.event_ref(),
    causal_event.event_ref().digest(),
    receipt.projection_sequence(),
    receipt.projection_revision(),
    receipt.projection_replay_digest(),
    "schedule-command-{attempt_id}",
  )
  @retry_authority.RetryPlanProposalV2::new(
    "plan-{attempt_id}",
    receipt.workflow(),
    receipt.receipt_ref(),
    receipt.digest(),
    receipt.canonical_bytes(),
    policy_ref,
    policy_digest,
    policy_bytes,
    timing_digest,
    timing_bytes,
    due_at,
    receipt.root_intent_ref(),
    receipt.root_attempt_ref(),
    receipt.source_intent_ref(),
    receipt.source_attempt_ref(),
    receipt.lineage_digest(),
    receipt.attempt_count(),
    receipt.retry_count(),
    receipt.retry_ordinal(),
    receipt.cause_key(),
    requested_ref,
    requested_work.envelope_digest(),
    "logical-attempt-{attempt_id}",
    "1.0.0",
    "logical-effect-{attempt_id}",
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("artifact-{attempt_id}")),
    attempt_id,
    attempt_ordinal,
    attempt_key,
    request.request_ref(),
    request.digest(),
    request.canonical_bytes(),
    admission_ref,
    admission_digest,
    admission_bytes,
    effective_deadline,
    None,
    effective_deadline,
    effective_deadline,
    effective_deadline,
    Some(governance.binding_digest()),
    Some(governance.canonical_bytes()),
    governance.authority_expires_at(),
    "schedule-{attempt_id}",
    "schedule-key-{attempt_id}",
    "schedule-command-{attempt_id}",
    causal_event.event_ref(),
    causal_event.event_ref().digest(),
    receipt.projection_sequence(),
    receipt.projection_revision(),
    receipt.projection_replay_digest(),
  )
}

///|
struct AcceptedFixture {
  policy : @governance.GovernancePolicy
  workflow : @contracts.RecordRef
  evidence : Array[@contracts.EvidenceRef]
  binding : GovernanceBinding
  receipt_event : @storage.WorkflowEvent
  events : Array[@storage.WorkflowEvent]
  subject : @contracts.RecordRef
  authority_request : @governance.AuthorityRequest
  authority_grant : @governance.AuthorityDecision
  review_request : @governance.ReviewRequest
  review_decision : @governance.ReviewDecision
  review_receipt : @governance.ReviewReceipt
}

///|
fn accepted_fixture(
  suffix : String,
  outcome? : @governance.ReviewOutcome = Approved,
  expires_at? : Int64 = 100L,
) -> AcceptedFixture raise {
  let policy = @governance.GovernancePolicy::new(
    "policy-\{suffix}",
    "1.0.0",
    "1.0.0",
    "1.0.0",
    ["authority-ref"],
    ["named-human-reviewer"],
    1,
    1,
    [Approved, Rejected, ChangesRequested],
  )
  let workflow = test_ref("workflow", "workflow-\{suffix}")
  let evidence = [test_evidence("evidence-\{suffix}")]
  let criteria = [test_ref("criterion", "criterion-\{suffix}")]
  let attachment = @governance.EvidenceAttachment::new(
    policy,
    workflow,
    "attachment-\{suffix}",
    "1.0.0",
    evidence,
    test_ref("criterion-set", "purpose-\{suffix}"),
    1L,
  )
  let mut projection = @governance.GovernanceProjection::new(policy, workflow)
  let events : Array[@storage.WorkflowEvent] = []
  let event1 = @governance.prepare_event(
    projection,
    "gov-\{suffix}-1",
    @governance.GovernanceAction::evidence_attached(
      attachment,
      "gov-key-\{suffix}-1",
    ),
  )
  projection = projection.apply_event(event1)
  events.push(event1)
  let authority_subject = test_envelope(
    "authority-subject-\{suffix}",
    "authority-subject",
    test_ref("subject", "authority-subject-\{suffix}"),
    b"opaque",
    evidence~,
  )
  let authority_request = @governance.AuthorityRequest::new(
    policy,
    workflow,
    "authority-request-\{suffix}",
    "1.0.0",
    attachment,
    authority_subject,
    criteria,
    evidence,
    10L,
    Some(expires_at),
    2L,
    "gov-key-\{suffix}-2",
  )
  let event2 = @governance.prepare_event(
    projection,
    "gov-\{suffix}-2",
    @governance.GovernanceAction::authority_requested(authority_request),
  )
  projection = projection.apply_event(event2)
  events.push(event2)
  let authority = test_ref("authority-ref", "authority-\{suffix}")
  let grant = @governance.AuthorityDecision::grant(
    policy,
    workflow,
    "authority-grant-\{suffix}",
    "1.0.0",
    authority_request,
    test_envelope(
      "authority-proof-\{suffix}",
      "authority-proof",
      authority,
      b"opaque",
    ),
    authority,
    20L,
    2L,
  )
  let event3 = @governance.prepare_event(
    projection,
    "gov-\{suffix}-3",
    @governance.GovernanceAction::authority_decided(
      grant,
      "gov-key-\{suffix}-3",
    ),
  )
  projection = projection.apply_event(event3)
  events.push(event3)
  let subject = test_ref("subject", "governed-\{suffix}")
  let review_request = @governance.ReviewRequest::new(
    policy,
    workflow,
    "review-request-\{suffix}",
    "1.0.0",
    authority_request,
    grant,
    criteria,
    evidence,
    test_envelope(
      "review-subject-\{suffix}",
      "review-subject",
      subject,
      b"opaque",
      evidence~,
    ),
    30L,
    4L,
    "gov-key-\{suffix}-4",
  )
  let event4 = @governance.prepare_event(
    projection,
    "gov-\{suffix}-4",
    @governance.GovernanceAction::review_requested(review_request),
  )
  projection = projection.apply_event(event4)
  events.push(event4)
  let disposition = match outcome {
    Approved => @governance.Satisfied
    Rejected => Unsatisfied
    ChangesRequested => NeedsRevision
  }
  let reviewer = test_ref("named-human-reviewer", "reviewer-\{suffix}")
  let review_decision = @governance.ReviewDecision::new(
    policy,
    workflow,
    "review-decision-\{suffix}",
    "1.0.0",
    review_request,
    reviewer,
    test_envelope("review-proof-\{suffix}", "review-proof", reviewer, b"opaque"),
    outcome,
    [@governance.CriterionFinding::new(criteria[0], disposition)],
    evidence,
    [],
    40L,
    5L,
  )
  let event5 = @governance.prepare_event(
    projection,
    "gov-\{suffix}-5",
    @governance.GovernanceAction::review_decision_recorded(
      review_decision,
      "gov-key-\{suffix}-5",
    ),
  )
  projection = projection.apply_event(event5)
  events.push(event5)
  let receipt = @governance.ReviewReceipt::bind(
    projection,
    "review-receipt-\{suffix}",
    "1.0.0",
    50L,
  )
  let event6 = @governance.prepare_event(
    projection,
    "gov-\{suffix}-6",
    @governance.GovernanceAction::review_receipt_bound(
      receipt,
      "gov-key-\{suffix}-6",
    ),
  )
  projection = projection.apply_event(event6)
  events.push(event6)
  let governance_store = @storage.MemoryStore::new()
  ignore(
    governance_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        0L,
        "governance-proof-\{suffix}",
        events,
        [],
      ),
    ),
  )
  let binding = GovernanceBinding::new(
    policy,
    governance_store.replay(workflow),
    authority_request,
    grant,
    review_request,
    review_decision,
    receipt,
  )
  {
    policy,
    workflow,
    evidence,
    binding,
    receipt_event: event6,
    events,
    subject,
    authority_request,
    authority_grant: grant,
    review_request,
    review_decision,
    review_receipt: receipt,
  }
}

///|
struct IntentFixture {
  accepted : AcceptedFixture
  store : @storage.MemoryStore
  attempt : AttemptRegistration
  intent : EffectIntent
  projection : EffectsProjection
  requests : Array[@storage.CommitRequest]
}

///|
fn durable_intent(suffix : String) -> IntentFixture raise {
  let accepted = accepted_fixture(suffix)
  let governance_request = @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    accepted.workflow,
    0L,
    "governance-batch-\{accepted.workflow.id()}",
    accepted.events,
    [],
  )
  let store = @storage.MemoryStore::new()
  ignore(store.commit(governance_request))
  let empty = EffectsProjection::new(
    accepted.workflow,
    accepted.policy.policy_ref(),
  )
  let base = fold_authoritative_replay(
    empty,
    store.replay(accepted.workflow),
    ReplayCatalog::new([], [], [], [], [], []),
  )
  let requested = test_envelope(
    "requested-\{suffix}",
    "requested-work",
    accepted.subject,
    b"opaque-work",
    evidence=accepted.evidence,
  )
  let attempt = AttemptRegistration::new(
    "attempt-\{suffix}",
    "1.0.0",
    accepted.workflow,
    accepted.receipt_event,
    1L,
    requested,
    accepted.evidence,
    accepted.binding,
    60L,
    "attempt-key-\{suffix}",
    accepted.receipt_event.event_ref().digest(),
  )
  let attempt_event = prepare_attempt_registration_event(
    base,
    "attempt-event-\{suffix}",
    attempt,
  )
  let attempt_request = @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    accepted.workflow,
    6L,
    "attempt-command-\{suffix}",
    [attempt_event],
    [],
  )
  ignore(store.commit(attempt_request))
  let after_attempt = fold_authoritative_replay(
    empty,
    store.replay(accepted.workflow),
    ReplayCatalog::new([attempt], [], [], [], [], []),
  )
  let fence = FencingBinding::new(test_ref("fence", "fence-\{suffix}"), 1L, 10L)
  let intent = EffectIntent::new(
    "intent-\{suffix}",
    "1.0.0",
    attempt,
    accepted.binding,
    test_envelope(
      "effect-request-\{suffix}",
      "effect-request",
      accepted.subject,
      b"opaque-effect",
      evidence=accepted.evidence,
    ),
    accepted.evidence,
    "external-key-\{suffix}",
    test_ref("capability", "capability-\{suffix}"),
    "opaque-capability",
    70L,
    attempt.attempt_ref(),
    after_attempt.last_event_digest().unwrap(),
    true,
    fencing=fence,
  )
  let prepared = prepare_effect_commit(
    after_attempt,
    "intent-event-\{suffix}",
    "outbox-\{suffix}",
    "intent-command-\{suffix}",
    intent,
  )
  assert_eq(
    fold_authoritative_replay(
      empty,
      store.replay(accepted.workflow),
      ReplayCatalog::new([attempt], [intent], [], [], [], []),
    )
    .dispatch_eligible_intents()
    .length(),
    0,
  )
  ignore(store.commit(prepared.commit_request()))
  let projection = fold_authoritative_replay(
    empty,
    store.replay(accepted.workflow),
    ReplayCatalog::new([attempt], [intent], [], [], [], []),
  )
  {
    accepted,
    store,
    attempt,
    intent,
    projection,
    requests: [governance_request, attempt_request, prepared.commit_request()],
  }
}

///|
test "FLOW-6A atomic replay is the only dispatch eligibility proof" {
  let fixture = durable_intent("happy")
  ignore(fixture.requests.length())
  assert_eq(fixture.projection.dispatch_eligible_intents().length(), 1)
  assert_true(
    fixture.projection.state_for(fixture.intent.intent_ref()) ==
    DurableIntentDispatchEligible,
  )
  assert_eq(fixture.projection.registry().entries().length(), 1)
  let restarted = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new([fixture.attempt], [fixture.intent], [], [], [], []),
  )
  assert_eq(restarted.canonical_bytes(), fixture.projection.canonical_bytes())
  assert_true(restarted.state_digest() == fixture.projection.state_digest())
  assert_true(
    restarted.registry().state_digest() ==
    fixture.projection.registry().state_digest(),
  )
}

///|
fn projection_after_observation(
  fixture : IntentFixture,
  suffix : String,
) -> (DispatchObservation, EffectsProjection) raise {
  let observation = DispatchObservation::new(
    "observation-\{suffix}",
    fixture.intent,
    test_envelope(
      "observation-envelope-\{suffix}",
      "dispatch-observation",
      fixture.accepted.subject,
      b"opaque-observation",
    ),
    71L,
    [],
  )
  ignore(
    fixture.store.commit(
      prepare_dispatch_observation_commit(
        fixture.projection,
        "observation-event-\{suffix}",
        "observation-command-\{suffix}",
        observation,
      ),
    ),
  )
  let projected = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [],
      [],
      [],
    ),
  )
  (observation, projected)
}

///|
test "FLOW-6A known success and failure remain external observations" {
  for pair in [("success", Succeeded), ("failure", Failed)] {
    let (suffix, outcome) = pair
    let fixture = durable_intent(suffix)
    let (observation, projected) = projection_after_observation(fixture, suffix)
    let receipt = EffectReceipt::new(
      "receipt-\{suffix}",
      "1.0.0",
      fixture.intent,
      test_envelope(
        "receipt-envelope-\{suffix}",
        "dispatcher-receipt",
        fixture.accepted.subject,
        b"opaque-receipt",
      ),
      outcome,
      72L,
      [],
      observed_fencing=fixture.intent.fencing().unwrap(),
    )
    let receipt_request = prepare_effect_receipt_commit(
      projected,
      "receipt-event-\{suffix}",
      "receipt-command-\{suffix}",
      receipt,
    )
    let first_commit = fixture.store.commit(receipt_request)
    ignore(
      fold_authoritative_replay(
        EffectsProjection::new(
          fixture.accepted.workflow,
          fixture.accepted.policy.policy_ref(),
        ),
        fixture.store.replay(fixture.accepted.workflow),
        ReplayCatalog::new(
          [fixture.attempt],
          [fixture.intent],
          [observation],
          [receipt],
          [],
          [],
        ),
      ),
    )
    let duplicate_commit = fixture.store.commit(receipt_request)
    assert_true(duplicate_commit == first_commit)
    let final_projection = fold_authoritative_replay(
      EffectsProjection::new(
        fixture.accepted.workflow,
        fixture.accepted.policy.policy_ref(),
      ),
      fixture.store.replay(fixture.accepted.workflow),
      ReplayCatalog::new(
        [fixture.attempt],
        [fixture.intent],
        [observation],
        [receipt],
        [],
        [],
      ),
    )
    let expected = if outcome == Succeeded {
      KnownSuccess
    } else {
      KnownFailure
    }
    let strict_projection = fold_committed_effects_bytes(
      EffectsProjection::new(
        fixture.accepted.workflow,
        fixture.accepted.policy.policy_ref(),
      ),
      fixture.store.replay(fixture.accepted.workflow),
    )
    assert_true(
      final_projection.state_for(fixture.intent.intent_ref()) == expected,
    )
    if outcome == Succeeded {
      assert_true(
        strict_projection.committed_retry_eligibility_receipt(
          fixture.intent.intent_ref(),
        )
        is None,
      )
    } else {
      guard strict_projection.committed_retry_eligibility_receipt(
          fixture.intent.intent_ref(),
        )
        is Some(retry_receipt) else {
        fail("expected committed terminal-failure retry receipt")
      }
      assert_eq(retry_receipt.cause_key(), "terminal_failed")
      assert_eq(retry_receipt.attempt_count(), 1L)
      assert_eq(retry_receipt.retry_count(), 0L)
      assert_eq(retry_receipt.retry_ordinal(), 0L)
      assert_true(
        retry_receipt.root_intent_ref() == fixture.intent.intent_ref(),
      )
      assert_true(
        retry_receipt.root_attempt_ref() == fixture.attempt.attempt_ref(),
      )
      assert_true(retry_receipt.source_record_ref() == receipt.receipt_ref())
      assert_eq(retry_receipt.source_observed_at(), 72L)
      guard strict_projection.committed_retry_eligibility_receipt(
          fixture.intent.intent_ref(),
        )
        is Some(first_retry_receipt) else {
        fail("expected pre-duplicate retry receipt")
      }
      assert_true(
        retry_receipt.canonical_bytes() == first_retry_receipt.canonical_bytes(),
      )
      assert_true(
        retry_receipt.receipt_ref() == first_retry_receipt.receipt_ref(),
      )
      assert_true(retry_receipt.digest() == first_retry_receipt.digest())
      retry_receipt.validate_current(strict_projection)
    }
    assert_true(
      fixture.intent.governance().review_receipt_ref() ==
      fixture.accepted.binding.review_receipt_ref(),
    )
    let governance_receipts = fixture.store
      .replay(fixture.accepted.workflow)
      .events()
      .filter(event => event.payload().envelope_kind() == "ReviewReceiptBound")
    assert_eq(governance_receipts.length(), 1)
    assert_eq(
      governance_receipts[0].payload().payload(),
      fixture.accepted.review_receipt.canonical_bytes(),
    )
  }
}

///|
test "FLOW-6A unknown blocks retry until exact reconciliation" {
  let fixture = durable_intent("unknown")
  let (observation, projected) = projection_after_observation(
    fixture, "unknown",
  )
  let unknown = EffectReceipt::new(
    "receipt-unknown",
    "1.0.0",
    fixture.intent,
    test_envelope(
      "unknown-envelope",
      "dispatcher-receipt",
      fixture.accepted.subject,
      b"opaque-unknown",
    ),
    Unknown,
    72L,
    [],
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  ignore(
    fixture.store.commit(
      prepare_effect_receipt_commit(
        projected, "unknown-event", "unknown-command", unknown,
      ),
    ),
  )
  let catalog1 = ReplayCatalog::new(
    [fixture.attempt],
    [fixture.intent],
    [observation],
    [unknown],
    [],
    [],
  )
  let blocked = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    catalog1,
  )
  let strict_blocked = fold_committed_effects_bytes(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
  )
  assert_false(blocked.retry_eligible(fixture.intent.intent_ref()))
  assert_true(
    strict_blocked.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is None,
  )
  let request = ReconciliationRequest::new(
    "reconcile-request",
    fixture.intent,
    unknown,
    73L,
    [],
  )
  ignore(
    fixture.store.commit(
      prepare_reconciliation_request_commit(
        blocked, "reconcile-request-event", "reconcile-request-command", request,
      ),
    ),
  )
  let requested = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [unknown],
      [request],
      [],
    ),
  )
  let strict_requested = fold_committed_effects_bytes(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
  )
  assert_false(requested.retry_eligible(fixture.intent.intent_ref()))
  assert_true(
    strict_requested.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is None,
  )
  let resolution = ReconciliationRecord::new(
    "reconcile-resolution",
    fixture.intent,
    request,
    ReconciledNotApplied,
    test_envelope(
      "reconcile-envelope",
      "reconciliation-observation",
      fixture.accepted.subject,
      b"not-applied",
    ),
    74L,
    [],
  )
  let resolution_commit = prepare_reconciliation_resolution_commit(
    requested, "reconcile-resolution-event", "reconcile-resolution-command", resolution,
  )
  ignore(fixture.store.commit(resolution_commit))
  let resolved = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [unknown],
      [request],
      [resolution],
    ),
  )
  let strict_resolved = fold_committed_effects_bytes(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
  )
  assert_true(resolved.retry_eligible(fixture.intent.intent_ref()))
  try
    AttemptRegistration::new(
      "attempt-unknown-retry-without-receipt",
      "1.0.0",
      fixture.accepted.workflow,
      resolution_commit.events()[0],
      2L,
      test_envelope(
        "requested-unknown-retry-without-receipt",
        "requested-work",
        fixture.accepted.subject,
        b"opaque-retry",
        evidence=fixture.accepted.evidence,
      ),
      fixture.accepted.evidence,
      fixture.accepted.binding,
      75L,
      "attempt-key-unknown-retry-without-receipt",
      resolution_commit.events()[0].event_ref().digest(),
      retry_of_intent_ref=fixture.intent.intent_ref(),
    )
  catch {
    EffectsError::RetryEligibilityViolation(
      field="retry_attempt_receipt_missing"
    ) => ()
    _ => fail("expected exact missing retry receipt rejection")
  } noraise {
    _ => fail("expected missing retry receipt rejection")
  }
  let retry_receipt_option = strict_resolved.committed_retry_eligibility_receipt(
    fixture.intent.intent_ref(),
  )
  guard retry_receipt_option is Some(retry_receipt) else {
    fail("expected reconciled-not-applied retry receipt")
  }
  assert_eq(retry_receipt.cause_key(), "reconciled_not_applied")
  assert_eq(retry_receipt.attempt_count(), 1L)
  assert_eq(retry_receipt.retry_count(), 0L)
  assert_true(
    retry_receipt.source_record_ref() == resolution.reconciliation_ref(),
  )
  assert_eq(retry_receipt.source_observed_at(), 74L)
  retry_receipt.validate_current(strict_resolved)
  let retry_requested_work = test_envelope(
    "requested-unknown-retry",
    "requested-work",
    fixture.accepted.subject,
    b"opaque-retry",
    evidence=fixture.accepted.evidence,
  )
  let retry_plan = test_retry_plan(
    "attempt-unknown-retry",
    "attempt-key-unknown-retry",
    2L,
    retry_requested_work,
    retry_receipt,
    fixture.accepted.binding,
    resolution_commit.events()[0],
  )
  let retry_attempt = AttemptRegistration::new(
    "attempt-unknown-retry",
    "1.0.0",
    fixture.accepted.workflow,
    resolution_commit.events()[0],
    2L,
    retry_requested_work,
    fixture.accepted.evidence,
    fixture.accepted.binding,
    75L,
    "attempt-key-unknown-retry",
    resolution_commit.events()[0].event_ref().digest(),
    retry_of_intent_ref=fixture.intent.intent_ref(),
    retry_eligibility_receipt=retry_receipt,
    retry_plan~,
  )
  let retry_event = prepare_attempt_registration_event(
    strict_resolved, "attempt-event-unknown-retry", retry_attempt,
  )
  assert_true(retry_attempt.attempt_ref() != fixture.attempt.attempt_ref())
  assert_eq(retry_event.revision(), resolved.revision() + 1L)
  ignore(
    fixture.store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.accepted.workflow,
        resolved.revision(),
        "attempt-command-unknown-retry",
        [retry_event],
        [],
      ),
    ),
  )
  let consumed = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt, retry_attempt],
      [fixture.intent],
      [observation],
      [unknown],
      [request],
      [resolution],
    ),
  )
  let strict_consumed = fold_committed_effects_bytes(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
  )
  let consumed_receipt_option = strict_consumed.committed_retry_eligibility_receipt(
    fixture.intent.intent_ref(),
  )
  assert_true(consumed_receipt_option is None)
  let reused_requested_work = test_envelope(
    "requested-unknown-retry-reused",
    "requested-work",
    fixture.accepted.subject,
    b"opaque-retry-reused",
    evidence=fixture.accepted.evidence,
  )
  let reused_plan = test_retry_plan(
    "attempt-unknown-retry-reused",
    "attempt-key-unknown-retry-reused",
    2L,
    reused_requested_work,
    retry_receipt,
    fixture.accepted.binding,
    resolution_commit.events()[0],
  )
  let reused = AttemptRegistration::new(
    "attempt-unknown-retry-reused",
    "1.0.0",
    fixture.accepted.workflow,
    resolution_commit.events()[0],
    2L,
    reused_requested_work,
    fixture.accepted.evidence,
    fixture.accepted.binding,
    76L,
    "attempt-key-unknown-retry-reused",
    resolution_commit.events()[0].event_ref().digest(),
    retry_of_intent_ref=fixture.intent.intent_ref(),
    retry_eligibility_receipt=retry_receipt,
    retry_plan=reused_plan,
  )
  try
    prepare_attempt_registration_event(
      strict_consumed, "attempt-event-unknown-retry-reused", reused,
    )
  catch {
    EffectsError::RevisionMismatch(expected~, actual~) => {
      assert_eq(expected, strict_resolved.revision())
      assert_eq(actual, strict_consumed.revision())
    }
    _ => fail("expected exact one-shot receipt consumption failure")
  } noraise {
    _ => fail("expected retry receipt reuse to fail")
  }
  let retry_intent = EffectIntent::new(
    "intent-unknown-retry",
    "1.0.0",
    retry_attempt,
    fixture.accepted.binding,
    test_envelope(
      "effect-request-unknown-retry",
      "effect-request",
      fixture.accepted.subject,
      b"opaque-effect-retry",
      evidence=fixture.accepted.evidence,
    ),
    fixture.accepted.evidence,
    "external-key-unknown-retry",
    test_ref("capability", "capability-unknown-retry"),
    "opaque-capability",
    76L,
    retry_attempt.attempt_ref(),
    consumed.last_event_digest().unwrap(),
    true,
    fencing=FencingBinding::new(
      fixture.intent.fencing().unwrap().fence_ref(),
      2L,
      11L,
    ),
  )
  let retry_intent_commit = prepare_effect_commit(
    consumed, "intent-event-unknown-retry", "outbox-unknown-retry", "intent-command-unknown-retry",
    retry_intent,
  )
  ignore(fixture.store.commit(retry_intent_commit.commit_request()))
  let retry_dispatchable = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt, retry_attempt],
      [fixture.intent, retry_intent],
      [observation],
      [unknown],
      [request],
      [resolution],
    ),
  )
  let retry_observation = DispatchObservation::new(
    "observation-unknown-retry",
    retry_intent,
    test_envelope(
      "observation-envelope-unknown-retry",
      "dispatch-observation",
      fixture.accepted.subject,
      b"opaque-observation-retry",
    ),
    77L,
    [],
  )
  ignore(
    fixture.store.commit(
      prepare_dispatch_observation_commit(
        retry_dispatchable, "observation-event-unknown-retry", "observation-command-unknown-retry",
        retry_observation,
      ),
    ),
  )
  let retry_pending = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt, retry_attempt],
      [fixture.intent, retry_intent],
      [observation, retry_observation],
      [unknown],
      [request],
      [resolution],
    ),
  )
  let retry_failed = EffectReceipt::new(
    "receipt-unknown-retry-failed",
    "1.0.0",
    retry_intent,
    test_envelope(
      "receipt-envelope-unknown-retry-failed",
      "dispatcher-receipt",
      fixture.accepted.subject,
      b"opaque-retry-failed",
    ),
    Failed,
    78L,
    [],
    observed_fencing=retry_intent.fencing().unwrap(),
  )
  let retry_failed_request = prepare_effect_receipt_commit(
    retry_pending, "receipt-event-unknown-retry-failed", "receipt-command-unknown-retry-failed",
    retry_failed,
  )
  ignore(fixture.store.commit(retry_failed_request))
  let strict_retry_terminal = fold_committed_effects_bytes(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
  )
  let next_receipt_option = strict_retry_terminal.committed_retry_eligibility_receipt(
    retry_intent.intent_ref(),
  )
  guard next_receipt_option is Some(next_receipt) else {
    fail("expected second-lineage terminal retry receipt")
  }
  assert_true(next_receipt.root_intent_ref() == fixture.intent.intent_ref())
  assert_true(next_receipt.root_attempt_ref() == fixture.attempt.attempt_ref())
  assert_true(next_receipt.source_intent_ref() == retry_intent.intent_ref())
  assert_true(next_receipt.source_attempt_ref() == retry_attempt.attempt_ref())
  assert_eq(next_receipt.attempt_count(), 2L)
  assert_eq(next_receipt.retry_count(), 1L)
  assert_eq(next_receipt.retry_ordinal(), 1L)
  next_receipt.validate_current(strict_retry_terminal)
}

///|
test "FLOW-6A rejects non-approved governance and expired authority" {
  try accepted_fixture("rejected", outcome=Rejected) catch {
    EffectsError::ReviewReceiptViolation(_) => ()
    _ => fail("expected terminal review rejection")
  } noraise {
    _ => fail("expected governance binding failure")
  }
  let accepted = accepted_fixture("expired", expires_at=65L)
  let requested = test_envelope(
    "expired-request",
    "requested-work",
    accepted.subject,
    b"opaque",
  )
  try
    AttemptRegistration::new(
      "expired-attempt",
      "1.0.0",
      accepted.workflow,
      accepted.receipt_event,
      1L,
      requested,
      [],
      accepted.binding,
      65L,
      "expired-key",
      accepted.receipt_event.event_ref().digest(),
    )
  catch {
    AuthorityExpired(_) => ()
    _ => fail("expected authority expiry")
  } noraise {
    _ => fail("expected authority expiry")
  }
}

///|
test "FLOW-6A capability evidence has no transition and ports expose no acceptance" {
  let capability = CapabilityReceipt::new(
    test_ref("capability", "capability-inert"),
    test_envelope(
      "capability-observation",
      "capability-observation",
      test_ref("subject", "capability-subject"),
      b"opaque",
    ),
    1L,
  )
  assert_true(capability.binding_digest().text().has_prefix("sha256:"))
}

///|
test "FLOW-6A deterministic digest vectors" {
  let fixture = durable_intent("digest-vector")
  let eligible = fixture.projection.dispatch_eligible_intents()[0]
  inspect(
    [
      "attempt=\{fixture.attempt.binding_digest().text()}",
      "intent=\{fixture.intent.binding_digest().text()}",
      "projection=\{fixture.projection.state_digest().text()}",
      "eligibility=\{eligible.authoritative_replay_digest().text()}",
      "registry=\{fixture.projection.registry().state_digest().text()}",
    ].join("\n"),
    content=(
      #|attempt=sha256:fc2d5b267ff89867f3244a342d6c8cc558afa2764a87806209b3c3fc31cefd23
      #|intent=sha256:c3f3b69c6ad7bedfd2246cf934b70417426cba2b25f4b32382887fc1955c4463
      #|projection=sha256:79de93ee8027d02bcab2e4aacab176df8abd21a942b0abe14ade7ebdc991b2e4
      #|eligibility=sha256:d5f18e5beec4170d23a5311941d333365f6d2ace239428b9376716adda8b03d9
      #|registry=sha256:29c6d2f935102d15a1588689957debafc4a6aa671d272895588a5130b7931b65
    ),
  )
}

///|
fn resolved_state(
  suffix : String,
  resolution : ReconciliationResolution,
) -> ReconciliationState raise {
  let fixture = durable_intent(suffix)
  let (observation, observed) = projection_after_observation(fixture, suffix)
  let unknown = EffectReceipt::new(
    "receipt-\{suffix}",
    "1.0.0",
    fixture.intent,
    test_envelope(
      "unknown-envelope-\{suffix}",
      "dispatcher-receipt",
      fixture.accepted.subject,
      b"opaque-unknown",
    ),
    Unknown,
    72L,
    [],
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  ignore(
    fixture.store.commit(
      prepare_effect_receipt_commit(
        observed,
        "unknown-event-\{suffix}",
        "unknown-command-\{suffix}",
        unknown,
      ),
    ),
  )
  let unknown_projection = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [unknown],
      [],
      [],
    ),
  )
  let request = ReconciliationRequest::new(
    "reconciliation-request-\{suffix}",
    fixture.intent,
    unknown,
    73L,
    [],
  )
  ignore(
    fixture.store.commit(
      prepare_reconciliation_request_commit(
        unknown_projection,
        "reconciliation-request-event-\{suffix}",
        "reconciliation-request-command-\{suffix}",
        request,
      ),
    ),
  )
  let requested = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [unknown],
      [request],
      [],
    ),
  )
  let reconciled = ReconciliationRecord::new(
    "reconciliation-\{suffix}",
    fixture.intent,
    request,
    resolution,
    test_envelope(
      "reconciliation-envelope-\{suffix}",
      "reconciliation-observation",
      fixture.accepted.subject,
      b"opaque-reconciliation",
    ),
    74L,
    [],
  )
  ignore(
    fixture.store.commit(
      prepare_reconciliation_resolution_commit(
        requested,
        "reconciliation-event-\{suffix}",
        "reconciliation-command-\{suffix}",
        reconciled,
      ),
    ),
  )
  fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [unknown],
      [request],
      [reconciled],
    ),
  ).state_for(fixture.intent.intent_ref())
}

///|
test "FLOW-6A reconciled success and failure remain distinct observations" {
  assert_true(
    resolved_state("reconciled-success", ReconciledSucceeded) ==
    ReconciledSuccessState,
  )
  assert_true(
    resolved_state("reconciled-failure", ReconciledFailed) ==
    ReconciledFailureState,
  )
}

///|
test "FLOW-6A idempotency and fencing conflicts fail closed" {
  let fixture = durable_intent("conflicts")
  let changed = EffectIntent::new(
    "intent-conflict",
    "1.0.0",
    fixture.attempt,
    fixture.accepted.binding,
    test_envelope(
      "effect-request-conflict",
      "effect-request",
      fixture.accepted.subject,
      b"changed-effect",
      evidence=fixture.accepted.evidence,
    ),
    fixture.accepted.evidence,
    fixture.intent.external_idempotency_key(),
    fixture.intent.capability_ref(),
    fixture.intent.capability_kind(),
    71L,
    fixture.attempt.attempt_ref(),
    fixture.projection.last_event_digest().unwrap(),
    true,
    fencing=fixture.intent.fencing().unwrap(),
  )
  try
    prepare_effect_commit(
      fixture.projection,
      "conflict-event",
      "conflict-outbox",
      "conflict-command",
      changed,
    )
  catch {
    EffectsError::IdempotencyConflict(_) => ()
    _ => fail("expected external idempotency conflict")
  } noraise {
    _ => fail("expected external idempotency conflict")
  }
  let stale = EffectIntent::new(
    "intent-stale-fence",
    "1.0.0",
    fixture.attempt,
    fixture.accepted.binding,
    test_envelope(
      "effect-request-stale-fence",
      "effect-request",
      fixture.accepted.subject,
      b"stale-fence-effect",
      evidence=fixture.accepted.evidence,
    ),
    fixture.accepted.evidence,
    "external-key-stale-fence",
    fixture.intent.capability_ref(),
    fixture.intent.capability_kind(),
    71L,
    fixture.attempt.attempt_ref(),
    fixture.projection.last_event_digest().unwrap(),
    true,
    fencing=FencingBinding::new(
      fixture.intent.fencing().unwrap().fence_ref(),
      0L,
      9L,
    ),
  )
  try
    prepare_effect_commit(
      fixture.projection,
      "stale-fence-event",
      "stale-fence-outbox",
      "stale-fence-command",
      stale,
    )
  catch {
    EffectsError::FencingViolation(_) => ()
    _ => fail("expected stale fencing failure")
  } noraise {
    _ => fail("expected stale fencing failure")
  }
}

///|
fn governance_replay(accepted : AcceptedFixture) -> @storage.ReplayResult raise {
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        accepted.workflow,
        0L,
        "governance-regression-\{accepted.workflow.id()}",
        accepted.events,
        [],
      ),
    ),
  )
  store.replay(accepted.workflow)
}

///|
fn expect_governance_binding_failure(
  policy : @governance.GovernancePolicy,
  replay : @storage.ReplayResult,
  authority_request : @governance.AuthorityRequest,
  authority_grant : @governance.AuthorityDecision,
  review_request : @governance.ReviewRequest,
  review_decision : @governance.ReviewDecision,
  review_receipt : @governance.ReviewReceipt,
) -> Unit raise {
  try
    GovernanceBinding::new(
      policy, replay, authority_request, authority_grant, review_request, review_decision,
      review_receipt,
    )
  catch {
    GovernanceViolation(_) | IdentityMismatch(_) | ReviewReceiptViolation(_) =>
      ()
    _ => fail("expected typed governance replay rejection")
  } noraise {
    _ => fail("expected governance replay rejection")
  }
}

///|
test "FLOW-6B governance binding requires one exact authoritative chain" {
  let accepted = accepted_fixture("governance-authoritative")
  let foreign = accepted_fixture("governance-foreign")
  let replay = governance_replay(accepted)
  expect_governance_binding_failure(
    foreign.policy,
    replay,
    accepted.authority_request,
    accepted.authority_grant,
    accepted.review_request,
    accepted.review_decision,
    accepted.review_receipt,
  )
  expect_governance_binding_failure(
    accepted.policy,
    replay,
    foreign.authority_request,
    accepted.authority_grant,
    accepted.review_request,
    accepted.review_decision,
    accepted.review_receipt,
  )
  expect_governance_binding_failure(
    accepted.policy,
    replay,
    accepted.authority_request,
    foreign.authority_grant,
    accepted.review_request,
    accepted.review_decision,
    accepted.review_receipt,
  )
  expect_governance_binding_failure(
    accepted.policy,
    replay,
    accepted.authority_request,
    accepted.authority_grant,
    foreign.review_request,
    accepted.review_decision,
    accepted.review_receipt,
  )
  expect_governance_binding_failure(
    accepted.policy,
    replay,
    accepted.authority_request,
    accepted.authority_grant,
    accepted.review_request,
    foreign.review_decision,
    accepted.review_receipt,
  )
  expect_governance_binding_failure(
    accepted.policy,
    replay,
    accepted.authority_request,
    accepted.authority_grant,
    accepted.review_request,
    accepted.review_decision,
    foreign.review_receipt,
  )
  let empty = @storage.MemoryStore::new()
  expect_governance_binding_failure(
    accepted.policy,
    empty.replay(accepted.workflow),
    accepted.authority_request,
    accepted.authority_grant,
    accepted.review_request,
    accepted.review_decision,
    accepted.review_receipt,
  )
  let stale = @storage.MemoryStore::new()
  ignore(
    stale.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        accepted.workflow,
        0L,
        "governance-stale",
        accepted.events[:5].to_owned(),
        [],
      ),
    ),
  )
  expect_governance_binding_failure(
    accepted.policy,
    stale.replay(accepted.workflow),
    accepted.authority_request,
    accepted.authority_grant,
    accepted.review_request,
    accepted.review_decision,
    accepted.review_receipt,
  )
}

///|
test "FLOW-6B tampered authoritative governance replay is rejected" {
  let accepted = accepted_fixture("governance-tamper")
  let original = accepted.events[5]
  let envelope = original.payload()
  let tampered_envelope = @contracts.WireEnvelope::new(
    envelope.contract_id(),
    envelope.contract_version().text(),
    envelope.envelope_id(),
    envelope.envelope_kind(),
    envelope.subject(),
    envelope.schema(),
    b"tampered-governance-record",
    envelope.producer_id(),
    envelope.producer_version().text(),
    [
      for item in envelope.artifacts() => item
    ],
    [
      for item in envelope.evidence() => item
    ],
    run_ref=envelope.run_ref().unwrap(),
    correlation_ref=envelope.correlation_ref().unwrap(),
    causation_ref=envelope.causation_ref().unwrap(),
    idempotency_ref=envelope.idempotency_ref().unwrap(),
    previous_digest=envelope.previous_digest().unwrap(),
  )
  let tampered_event = @storage.WorkflowEvent::new(
    original.record_version().text(),
    original.schema_version().text(),
    original.workflow(),
    original.event_ref().id(),
    original.sequence(),
    original.revision(),
    original.idempotency_key(),
    tampered_envelope,
    [
      for item in original.evidence() => item
    ],
    previous_event_digest=original.previous_event_digest().unwrap(),
  )
  let events = accepted.events[:5].to_owned()
  events.push(tampered_event)
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        accepted.workflow,
        0L,
        "governance-tampered",
        events,
        [],
      ),
    ),
  )
  expect_governance_binding_failure(
    accepted.policy,
    store.replay(accepted.workflow),
    accepted.authority_request,
    accepted.authority_grant,
    accepted.review_request,
    accepted.review_decision,
    accepted.review_receipt,
  )
}

///|
test "FLOW-6B dispatch observation rejects a foreign subject" {
  let fixture = durable_intent("foreign-observation-subject")
  try
    DispatchObservation::new(
      "foreign-observation",
      fixture.intent,
      test_envelope(
        "foreign-observation-envelope",
        "dispatch-observation",
        test_ref("subject", "foreign-observation-subject"),
        b"opaque",
      ),
      71L,
      [],
    )
  catch {
    IdentityMismatch(_) => ()
    _ => fail("expected foreign observation subject rejection")
  } noraise {
    _ => fail("expected foreign observation subject rejection")
  }
}

///|
fn flow6_schema(kind : String) -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    "closed-loop.effects",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("closed-loop.effects/{kind}/1")).text(),
  )
}

///|
fn commit_raw_fact(
  store : @storage.MemoryStore,
  projection : EffectsProjection,
  event_id : String,
  event_kind : String,
  intent : EffectIntent,
  record_id : String,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
) -> Unit raise {
  let previous = projection.last_event_digest().unwrap()
  let envelope = @contracts.WireEnvelope::new(
    "closed-loop.effects",
    "1.0.0",
    event_id,
    event_kind,
    intent.governance().governed_subject(),
    flow6_schema(event_kind),
    payload,
    "effects-protocol",
    "1.0.0",
    [],
    evidence,
    run_ref=projection.workflow(),
    attempt_ref=intent.attempt_ref(),
    correlation_ref=projection.workflow().id(),
    causation_ref=intent.intent_ref().id(),
    idempotency_ref=record_id,
    previous_digest=previous,
  )
  let event = @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    projection.workflow(),
    event_id,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    record_id,
    envelope,
    evidence,
    previous_event_digest=previous,
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        projection.workflow(),
        projection.revision(),
        "raw-command-\{event_id}",
        [event],
        [],
      ),
    ),
  )
}

///|
fn expect_effect_replay_failure(
  fixture : IntentFixture,
  observations : Array[DispatchObservation],
  receipts : Array[EffectReceipt],
  requests : Array[ReconciliationRequest],
  reconciliations : Array[ReconciliationRecord],
) -> Unit raise {
  try
    fold_authoritative_replay(
      EffectsProjection::new(
        fixture.accepted.workflow,
        fixture.accepted.policy.policy_ref(),
      ),
      fixture.store.replay(fixture.accepted.workflow),
      ReplayCatalog::new(
        [fixture.attempt],
        [fixture.intent],
        observations,
        receipts,
        requests,
        reconciliations,
      ),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected effects replay rejection")
  }
}

///|
fn make_observation(
  fixture : IntentFixture,
  id : String,
) -> DispatchObservation raise {
  DispatchObservation::new(
    id,
    fixture.intent,
    test_envelope(
      "\{id}-envelope",
      "dispatch-observation",
      fixture.accepted.subject,
      b"opaque-observation",
    ),
    71L,
    [],
  )
}

///|
fn make_receipt(
  fixture : IntentFixture,
  id : String,
  outcome : ExternalOutcome,
) -> EffectReceipt raise {
  EffectReceipt::new(
    id,
    "1.0.0",
    fixture.intent,
    test_envelope(
      "\{id}-envelope",
      "dispatcher-receipt",
      fixture.accepted.subject,
      b"opaque-receipt",
    ),
    outcome,
    72L,
    [],
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
}

///|
fn fold_chain(
  fixture : IntentFixture,
  observations : Array[DispatchObservation],
  receipts : Array[EffectReceipt],
  requests : Array[ReconciliationRequest],
  reconciliations : Array[ReconciliationRecord],
) -> EffectsProjection raise {
  fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      observations,
      receipts,
      requests,
      reconciliations,
    ),
  )
}

///|
test "FLOW-6B replay rejects repeated and post-outcome observations" {
  let repeated = durable_intent("replay-second-observation")
  let (first_observation, first_projection) = projection_after_observation(
    repeated, "replay-second-observation-first",
  )
  let second_observation = make_observation(
    repeated, "replay-second-observation-second",
  )
  commit_raw_fact(
    repeated.store,
    first_projection,
    "replay-second-observation-event",
    "effect.dispatch.observed.v1",
    repeated.intent,
    second_observation.observation_ref().id(),
    second_observation.canonical_bytes(),
    [],
  )
  expect_effect_replay_failure(
    repeated,
    [first_observation, second_observation],
    [],
    [],
    [],
  )

  for pair in [("known", Succeeded), ("unknown", Unknown)] {
    let (suffix, outcome) = pair
    let fixture = durable_intent("post-\{suffix}-observation")
    let (observation, pending) = projection_after_observation(
      fixture,
      "post-\{suffix}-observation-first",
    )
    let receipt = make_receipt(fixture, "post-\{suffix}-receipt", outcome)
    ignore(
      fixture.store.commit(
        prepare_effect_receipt_commit(
          pending,
          "post-\{suffix}-receipt-event",
          "post-\{suffix}-receipt-command",
          receipt,
        ),
      ),
    )
    let terminal = fold_chain(fixture, [observation], [receipt], [], [])
    let later = make_observation(fixture, "post-\{suffix}-observation-later")
    commit_raw_fact(
      fixture.store,
      terminal,
      "post-\{suffix}-observation-later-event",
      "effect.dispatch.observed.v1",
      fixture.intent,
      later.observation_ref().id(),
      later.canonical_bytes(),
      [],
    )
    expect_effect_replay_failure(fixture, [observation, later], [receipt], [], [])
  }
}

///|
test "FLOW-6B replay rejects receipt request and resolution in wrong state" {
  let receipt_fixture = durable_intent("wrong-state-receipt")
  let receipt = make_receipt(
    receipt_fixture,
    "wrong-state-receipt-record",
    Succeeded,
  )
  commit_raw_fact(
    receipt_fixture.store,
    receipt_fixture.projection,
    "wrong-state-receipt-event",
    "effect.receipt.recorded.v1",
    receipt_fixture.intent,
    receipt.receipt_ref().id(),
    receipt.canonical_bytes(),
    [],
  )
  expect_effect_replay_failure(receipt_fixture, [], [receipt], [], [])

  let request_fixture = durable_intent("wrong-state-request")
  let unknown = make_receipt(
    request_fixture,
    "wrong-state-uncommitted-unknown",
    Unknown,
  )
  let request = ReconciliationRequest::new(
    "wrong-state-request-record",
    request_fixture.intent,
    unknown,
    73L,
    [],
  )
  commit_raw_fact(
    request_fixture.store,
    request_fixture.projection,
    "wrong-state-request-event",
    "effect.reconciliation.requested.v1",
    request_fixture.intent,
    request.request_ref().id(),
    request.canonical_bytes(),
    [],
  )
  expect_effect_replay_failure(request_fixture, [], [unknown], [request], [])

  let resolution_fixture = durable_intent("wrong-state-resolution")
  let unresolved_unknown = make_receipt(
    resolution_fixture,
    "wrong-state-resolution-unknown",
    Unknown,
  )
  let unresolved_request = ReconciliationRequest::new(
    "wrong-state-resolution-request",
    resolution_fixture.intent,
    unresolved_unknown,
    73L,
    [],
  )
  let resolution = ReconciliationRecord::new(
    "wrong-state-resolution-record",
    resolution_fixture.intent,
    unresolved_request,
    ReconciledNotApplied,
    test_envelope(
      "wrong-state-resolution-envelope",
      "reconciliation-observation",
      resolution_fixture.accepted.subject,
      b"opaque",
    ),
    74L,
    [],
  )
  commit_raw_fact(
    resolution_fixture.store,
    resolution_fixture.projection,
    "wrong-state-resolution-event",
    "effect.reconciliation.resolved.v1",
    resolution_fixture.intent,
    resolution.reconciliation_ref().id(),
    resolution.canonical_bytes(),
    [],
  )
  expect_effect_replay_failure(
    resolution_fixture,
    [],
    [unresolved_unknown],
    [unresolved_request],
    [resolution],
  )
}

///|
test "FLOW-6B forged intent wrapper is rejected with a matching causal outbox" {
  let fixture = durable_intent("forged-intent-wrapper-outbox")
  let store = @storage.MemoryStore::new()
  for request in fixture.requests[:2] {
    ignore(store.commit(request))
  }
  let original_event = fixture.requests[2].events()[0]
  let original_envelope = original_event.payload()
  let forged_envelope = @contracts.WireEnvelope::new(
    original_envelope.contract_id(),
    original_envelope.contract_version().text(),
    original_envelope.envelope_id(),
    original_envelope.envelope_kind(),
    test_ref("subject", "forged-intent-wrapper-subject"),
    original_envelope.schema(),
    original_envelope.payload(),
    original_envelope.producer_id(),
    original_envelope.producer_version().text(),
    [
      for item in original_envelope.artifacts() => item
    ],
    [
      for item in original_envelope.evidence() => item
    ],
    run_ref=original_envelope.run_ref().unwrap(),
    attempt_ref=original_envelope.attempt_ref().unwrap(),
    correlation_ref=original_envelope.correlation_ref().unwrap(),
    causation_ref=original_envelope.causation_ref().unwrap(),
    idempotency_ref=original_envelope.idempotency_ref().unwrap(),
    previous_digest=original_envelope.previous_digest().unwrap(),
  )
  let forged_event = @storage.WorkflowEvent::new(
    original_event.record_version().text(),
    original_event.schema_version().text(),
    original_event.workflow(),
    original_event.event_ref().id(),
    original_event.sequence(),
    original_event.revision(),
    original_event.idempotency_key(),
    forged_envelope,
    [
      for item in original_event.evidence() => item
    ],
    previous_event_digest=original_event.previous_event_digest().unwrap(),
  )
  let original_outbox = fixture.requests[2].intents()[0]
  let forged_outbox = @storage.OutboxIntent::new(
    original_outbox.record_version().text(),
    original_outbox.schema_version().text(),
    original_outbox.intent_ref().id(),
    original_outbox.workflow(),
    forged_event.event_ref(),
    original_outbox.idempotency_key(),
    original_outbox.payload(),
    [
      for item in original_outbox.evidence() => item
    ],
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.accepted.workflow,
        7L,
        "forged-intent-wrapper-command",
        [forged_event],
        [forged_outbox],
      ),
    ),
  )
  try
    fold_authoritative_replay(
      EffectsProjection::new(
        fixture.accepted.workflow,
        fixture.accepted.policy.policy_ref(),
      ),
      store.replay(fixture.accepted.workflow),
      ReplayCatalog::new([fixture.attempt], [fixture.intent], [], [], [], []),
    )
  catch {
    EffectsError::IdentityMismatch(_) => ()
    _ => fail("expected exact intent wrapper rejection")
  } noraise {
    _ => fail("expected exact intent wrapper rejection")
  }
}

///|
test "FLOW-6B replay rejects an observation after reconciliation" {
  let fixture = durable_intent("post-reconciliation-observation")
  let (observation, pending) = projection_after_observation(
    fixture, "post-reconciliation-observation-first",
  )
  let unknown = make_receipt(
    fixture,
    "post-reconciliation-observation-unknown",
    Unknown,
  )
  ignore(
    fixture.store.commit(
      prepare_effect_receipt_commit(
        pending, "post-reconciliation-unknown-event", "post-reconciliation-unknown-command",
        unknown,
      ),
    ),
  )
  let unknown_projection = fold_chain(fixture, [observation], [unknown], [], [])
  let request = ReconciliationRequest::new(
    "post-reconciliation-request",
    fixture.intent,
    unknown,
    73L,
    [],
  )
  ignore(
    fixture.store.commit(
      prepare_reconciliation_request_commit(
        unknown_projection, "post-reconciliation-request-event", "post-reconciliation-request-command",
        request,
      ),
    ),
  )
  let requested = fold_chain(fixture, [observation], [unknown], [request], [])
  let resolution = ReconciliationRecord::new(
    "post-reconciliation-resolution",
    fixture.intent,
    request,
    ReconciledSucceeded,
    test_envelope(
      "post-reconciliation-resolution-envelope",
      "reconciliation-observation",
      fixture.accepted.subject,
      b"opaque",
    ),
    74L,
    [],
  )
  ignore(
    fixture.store.commit(
      prepare_reconciliation_resolution_commit(
        requested, "post-reconciliation-resolution-event", "post-reconciliation-resolution-command",
        resolution,
      ),
    ),
  )
  let resolved = fold_chain(fixture, [observation], [unknown], [request], [
    resolution,
  ])
  let later = make_observation(fixture, "post-reconciliation-observation-later")
  commit_raw_fact(
    fixture.store,
    resolved,
    "post-reconciliation-observation-later-event",
    "effect.dispatch.observed.v1",
    fixture.intent,
    later.observation_ref().id(),
    later.canonical_bytes(),
    [],
  )
  expect_effect_replay_failure(
    fixture,
    [observation, later],
    [unknown],
    [request],
    [resolution],
  )
}

///|
test "FLOW-6B deterministic receipt and reconciliation digest vectors" {
  let fixture = durable_intent("digest-reconciliation-vector")
  let receipt = make_receipt(fixture, "digest-reconciliation-receipt", Unknown)
  let request = ReconciliationRequest::new(
    "digest-reconciliation-request",
    fixture.intent,
    receipt,
    73L,
    [],
  )
  let reconciliation = ReconciliationRecord::new(
    "digest-reconciliation-record",
    fixture.intent,
    request,
    ReconciledNotApplied,
    test_envelope(
      "digest-reconciliation-envelope",
      "reconciliation-observation",
      fixture.accepted.subject,
      b"opaque-reconciliation",
    ),
    74L,
    [],
  )
  inspect(
    [
      "receipt=\{receipt.binding_digest().text()}",
      "request=\{@contracts.sha256_digest(request.canonical_bytes()).text()}",
      "reconciliation=\{@contracts.sha256_digest(reconciliation.canonical_bytes()).text()}",
    ].join("\n"),
    content=(
      #|receipt=sha256:380a0b0a58e954db96b91059d148a90d0547c313c5dd5246af185a9617db25ed
      #|request=sha256:6c3cd32b1894463d6a2cddeef868139eef6601efe8b3fffac297aa9cee6f7084
      #|reconciliation=sha256:dcf974f1a7d4879c875c1b736f840778a72f91e67e9cfd578f0b7187caaaae48
    ),
  )
}

///|
test "FLOW-6B exact authoritative commit duplicates remain idempotent" {
  let fixture = durable_intent("exact-duplicate")
  let before = fixture.store.replay(fixture.accepted.workflow).replay_digest()
  ignore(fixture.store.commit(fixture.requests[2]))
  let after = fixture.store.replay(fixture.accepted.workflow)
  assert_true(before == after.replay_digest())
  let replayed = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    after,
    ReplayCatalog::new([fixture.attempt], [fixture.intent], [], [], [], []),
  )
  assert_eq(replayed.dispatch_eligible_intents().length(), 1)

  let (observation, pending) = projection_after_observation(
    fixture, "exact-duplicate-observation",
  )
  let receipt = make_receipt(fixture, "exact-duplicate-receipt", Succeeded)
  let receipt_commit = prepare_effect_receipt_commit(
    pending, "exact-duplicate-receipt-event", "exact-duplicate-receipt-command",
    receipt,
  )
  ignore(fixture.store.commit(receipt_commit))
  let receipt_digest = fixture.store
    .replay(fixture.accepted.workflow)
    .replay_digest()
  ignore(fixture.store.commit(receipt_commit))
  assert_true(
    receipt_digest ==
    fixture.store.replay(fixture.accepted.workflow).replay_digest(),
  )
  let terminal = fold_chain(fixture, [observation], [receipt], [], [])
  assert_true(terminal.state_for(fixture.intent.intent_ref()) == KnownSuccess)
}
