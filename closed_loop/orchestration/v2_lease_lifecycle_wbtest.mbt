///|
struct Flow7LifecycleFixture {
  schedule : ScheduleIntentV2
  registration : ScheduleRegisteredV2
  claim : LeaseClaimV2
  claimed : LeaseClaimedV2
}

///|
priv enum Flow7LifecycleAdmissionMutation {
  LifecycleAdmissionExact
  LifecycleAdmissionWrongSubject
  LifecycleAdmissionWrongFence
  LifecycleAdmissionMissingCapability
  LifecycleAdmissionMissingEvidence
  LifecycleAdmissionTwoEvidence
}

///|
fn flow7_lifecycle_fixture(prefix : String) -> Flow7LifecycleFixture raise {
  let (admission, evidence, schedule, registration, _, _) = flow7_durable_fixture()
  let claim = LeaseClaimV2::new(
    prefix + "-claim",
    schedule,
    admission.admission,
    schedule.workflow(),
    flow7_v2_ref("owner", prefix + "-owner", b"flow7-lifecycle-owner"),
    5L,
    0L,
    0L,
    1L,
    1L,
    prefix + "-claim-key",
    [evidence],
    flow7_v2_ref("causation", prefix + "-claim", b"flow7-lifecycle-claim-cause"),
  )
  let claimed = LeaseClaimedV2::new(prefix + "-claimed", registration, claim)
  { schedule, registration, claim, claimed }
}

///|
fn flow7_lifecycle_claimed(
  fixture : Flow7LifecycleFixture,
  prefix : String,
) -> (
  @storage.MemoryStore,
  OrchestrationProjectionV2,
  CommittedLeaseAuthorityReceiptV2,
) raise {
  let store = @storage.MemoryStore::new()
  ignore(
    flow7_commit_schedule_and_first_claim(
      store,
      fixture.schedule,
      fixture.registration,
      fixture.claim,
      fixture.claimed,
      prefix,
    ),
  )
  let projection = replay_orchestration_v2(store, fixture.schedule.workflow())
  guard projection.committed_lease_authority_receipt() is Some(receipt) else {
    fail("expected initial lifecycle receipt")
  }
  (store, projection, receipt)
}

///|
fn flow7_lifecycle_operation_admission(
  prefix : String,
  request : LeaseLifecycleRequestV2,
  head_ref : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  clock : Int64,
  mutation? : Flow7LifecycleAdmissionMutation = LifecycleAdmissionExact,
) -> AdmissionV2 raise OrchestrationError {
  let producer_ref = flow7_v2_ref(
    "producer",
    prefix + "-producer",
    @utf8.encode(prefix + "-producer"),
  )
  let producer = @effects_authorization.ProducerDescriptor::new(
    "fixture.lifecycle",
    "1.0.0",
    producer_ref,
    producer_ref.digest(),
  ).unwrap()
  let decision = flow7_v2_ref(
    "decision",
    prefix + "-decision",
    @utf8.encode(prefix + "-decision"),
  )
  let policy = flow7_v2_ref(
    "policy",
    prefix + "-policy",
    @utf8.encode(prefix + "-policy"),
  )
  let operation_subject = match mutation {
    LifecycleAdmissionWrongSubject =>
      flow7_v2_ref(
        "lease-state",
        prefix + "-wrong-subject",
        @utf8.encode(prefix + "-wrong-subject"),
      )
    _ => request.predecessor_state_ref()
  }
  let governance = @effects_authorization.AuthorizationGovernanceBinding::new(
    decision,
    decision.digest(),
    policy,
    policy.digest(),
    operation_subject,
    0L,
    100L,
  ).unwrap()
  let position = @effects_authorization.ReplayPosition::new(
    head_ref,
    sequence,
    revision,
    head_ref.digest(),
  ).unwrap()
  let eligibility = @effects_authorization.EligibilityBinding::new(
    clock, position,
  ).unwrap()
  let planned = @effects_authorization.PlannedEffectTuple::new(
    request.workflow(),
    operation_subject,
    "lease-lifecycle",
    "2.1.0",
    "lease-lifecycle-operation",
    "2.1.0",
    request.proposed_epoch(),
    request.idempotency_key(),
    request.request_ref(),
    request.digest(),
    request.request_ref(),
    request.digest(),
    request.digest(),
  ).unwrap()
  let evidence_ref = flow7_v2_ref(
    "evidence",
    prefix + "-evidence",
    @utf8.encode(prefix + "-evidence"),
  )
  let evidence = @effects_authorization.EvidenceBinding::new(
    evidence_ref,
    evidence_ref.digest(),
  ).unwrap()
  let second_evidence_ref = flow7_v2_ref(
    "evidence",
    prefix + "-second-evidence",
    @utf8.encode(prefix + "-second-evidence"),
  )
  let second_evidence = @effects_authorization.EvidenceBinding::new(
    second_evidence_ref,
    second_evidence_ref.digest(),
  ).unwrap()
  let capability_ref = flow7_v2_ref(
    "capability",
    prefix + "-capability",
    @utf8.encode(prefix + "-capability"),
  )
  let capability = @effects_authorization.CapabilityBinding::new(
    capability_ref,
    capability_ref.digest(),
  ).unwrap()
  let fence_ref = flow7_v2_ref(
    "fencing",
    prefix + "-fencing",
    @utf8.encode(prefix + "-fencing"),
  )
  let fence_offset = match mutation {
    LifecycleAdmissionWrongFence => 1L
    _ => 0L
  }
  let fencing = @effects_authorization.FencingBinding::new(
    fence_ref,
    request.proposed_epoch() + fence_offset,
    request.proposed_fencing_token() + fence_offset,
  ).unwrap()
  let capability_option = match mutation {
    LifecycleAdmissionMissingCapability => None
    _ => Some(capability)
  }
  let operation_evidence = match mutation {
    LifecycleAdmissionMissingEvidence => []
    LifecycleAdmissionTwoEvidence => [evidence, second_evidence]
    _ => [evidence]
  }
  let controls = @effects_authorization.AuthorizationControls::new(
    capability_option,
    operation_evidence,
    Some(fencing),
    Some(clock),
    100L,
  ).unwrap()
  let authorization = @effects_authorization.PreDispatchAuthorization::new(
    prefix + "-authorization",
    producer,
    governance,
    eligibility,
    planned,
    controls,
  ).unwrap()
  let e0 = flow7_v2_envelope(
    prefix + "-authorization-event",
    @effects_authorization.AuthorizationEventKindV2::pre_dispatch_authorization_committed(),
    authorization.record_ref(),
    authorization.canonical_bytes(),
    0L,
    @effects_authorization.authorization_event_genesis_digest_v2,
  )
  let p0 = @effects_authorization.ReplayPosition::new(
    e0.event_ref(),
    0L,
    0L,
    e0.event_digest(),
  ).unwrap()
  let auth_link = @effects_authorization.AuthorizationLink::new(
    authorization.record_ref(),
    authorization.record_digest(),
    p0,
  ).unwrap()
  let attempt = @effects_authorization.AuthorizedAttemptRegistration::new(
    prefix + "-attempt",
    auth_link,
    producer,
    governance,
    eligibility,
    planned,
    controls,
  ).unwrap()
  let e1 = flow7_v2_envelope(
    prefix + "-attempt-event",
    @effects_authorization.AuthorizationEventKindV2::authorized_attempt_registration_committed(),
    attempt.record_ref(),
    attempt.canonical_bytes(),
    1L,
    e0.event_digest(),
  )
  let p1 = @effects_authorization.ReplayPosition::new(
    e1.event_ref(),
    1L,
    1L,
    e1.event_digest(),
  ).unwrap()
  let attempt_link = @effects_authorization.AttemptLink::new(
    attempt.record_ref(),
    attempt.record_digest(),
    p1,
  ).unwrap()
  let intent = @effects_authorization.AuthorizedEffectIntent::new(
    prefix + "-intent",
    auth_link,
    attempt_link,
    producer,
    governance,
    eligibility,
    planned,
    controls,
  ).unwrap()
  let e2 = flow7_v2_envelope(
    prefix + "-intent-event",
    @effects_authorization.AuthorizationEventKindV2::authorized_effect_intent_committed(),
    intent.record_ref(),
    intent.canonical_bytes(),
    2L,
    e1.event_digest(),
  )
  let store = @effects_authorization.AuthorizationEventStoreV2::new()
  ignore(store.append(e0).unwrap())
  ignore(store.append(e1).unwrap())
  ignore(store.append(e2).unwrap())
  let commit = @effects_authorization.derive_eligible_authorization_proof_commit_v2(
    store,
    prefix + "-proof",
    prefix + "-proof-event",
  ).unwrap()
  AdmissionV2::decode(prefix + "-proof", commit.proof().canonical_bytes())
}

///|
fn flow7_lifecycle_active_authorization(
  prefix : String,
  projection : OrchestrationProjectionV2,
  registration : ScheduleRegisteredV2,
  receipt : CommittedLeaseAuthorityReceiptV2,
  verb : LeaseLifecycleVerbV2,
  ttl : Int64?,
  clock : Int64,
) -> LeaseLifecycleAuthorizationV2 raise OrchestrationError {
  let request = LeaseLifecycleRequestV2::for_active(
    prefix + "-request",
    verb,
    registration,
    receipt,
    ttl,
    prefix + "-key",
    flow7_v2_ref(
      "causation",
      prefix + "-causation",
      @utf8.encode(prefix + "-causation"),
    ),
  )
  let admission = flow7_lifecycle_operation_admission(
    prefix,
    request,
    receipt.committed_event_ref(),
    projection.sequence(),
    projection.revision(),
    clock,
  )
  LeaseLifecycleAuthorizationV2::for_active(
    request, admission, projection, receipt,
  )
}

///|
test "FLOW-7 V2 orphan schedule cannot authorize public lease lifecycle" {
  let fixture = flow7_lifecycle_fixture("flow7-lifecycle-orphan")
  let (_, claimed, receipt) = flow7_lifecycle_claimed(
    fixture, "flow7-lifecycle-orphan-valid",
  )
  let request = LeaseLifecycleRequestV2::for_active(
    "flow7-lifecycle-orphan-request",
    ReleaseLeaseV2,
    fixture.registration,
    receipt,
    None,
    "flow7-lifecycle-orphan-request-key",
    flow7_v2_ref(
      "causation", "flow7-lifecycle-orphan-request", b"flow7-lifecycle-orphan-request",
    ),
  )
  let admission = flow7_lifecycle_operation_admission(
    "flow7-lifecycle-orphan-admission",
    request,
    receipt.committed_event_ref(),
    claimed.sequence(),
    claimed.revision(),
    1L,
  )
  let schedule = fixture.schedule
  let orphan_event = flow7_durable_test_event(
    "flow7-lifecycle-orphan-schedule-event",
    schedule.idempotency_key(),
    schedule.workflow(),
    "schedule.registered.v2",
    fixture.registration.record_ref(),
    fixture.registration.canonical_bytes(),
    [
      for value in schedule.evidence() => value
    ],
    schedule.causation_ref(),
    1L,
    1L,
    None,
  )
  let orphan_store = @storage.MemoryStore::new()
  ignore(
    orphan_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        0L,
        "flow7-lifecycle-orphan-schedule-command",
        [orphan_event],
        [],
      ),
    ),
  )
  let orphan = fold_orchestration_v2(orphan_store.replay(schedule.workflow()))
  try
    LeaseLifecycleAuthorizationV2::for_active(
      request, admission, orphan, receipt,
    )
  catch {
    ReplayBindingViolation(field="initial_work_root_binding_required") => ()
    _ => fail("unexpected orphan lifecycle-authorization error")
  } noraise {
    _ => fail("orphan one-event schedule authorized public lease lifecycle")
  }
}

///|
fn flow7_lifecycle_terminal_authorization(
  prefix : String,
  projection : OrchestrationProjectionV2,
  registration : ScheduleRegisteredV2,
  receipt : CommittedLeaseTerminalReceiptV2,
  owner : @contracts.RecordRef,
  ttl : Int64,
  epoch : Int64,
  fencing_token : Int64,
  clock : Int64,
) -> LeaseLifecycleAuthorizationV2 raise OrchestrationError {
  let request = LeaseLifecycleRequestV2::for_terminal(
    prefix + "-request",
    registration,
    receipt,
    owner,
    ttl,
    epoch,
    fencing_token,
    prefix + "-key",
    flow7_v2_ref(
      "causation",
      prefix + "-causation",
      @utf8.encode(prefix + "-causation"),
    ),
  )
  let admission = flow7_lifecycle_operation_admission(
    prefix,
    request,
    receipt.committed_event_ref(),
    projection.sequence(),
    projection.revision(),
    clock,
  )
  LeaseLifecycleAuthorizationV2::for_terminal(
    request, admission, projection, receipt,
  )
}

///|
fn flow7_lifecycle_release(
  store : @storage.MemoryStore,
  projection : OrchestrationProjectionV2,
  receipt : CommittedLeaseAuthorityReceiptV2,
  fixture : Flow7LifecycleFixture,
  prefix : String,
  observed_at : Int64,
) -> (OrchestrationProjectionV2, LeaseReleaseV2) raise {
  let authorization = flow7_lifecycle_active_authorization(
    prefix + "-release",
    projection,
    fixture.registration,
    receipt,
    ReleaseLeaseV2,
    None,
    observed_at,
  )
  let release = LeaseReleaseV2::new(
    prefix + "-release",
    fixture.registration,
    receipt,
    authorization,
  )
  let request = prepare_lease_released_v2(
    projection,
    prefix + "-release-event",
    release.idempotency_key(),
    prefix + "-release-command",
    release,
  )
  ignore(commit_orchestration_v2(store, request))
  (replay_orchestration_v2(store, fixture.schedule.workflow()), release)
}

///|
test "FLOW-7 V2 renewal remints authority and invalidates old receipt" {
  let fixture = flow7_lifecycle_fixture("flow7-lifecycle-renew")
  let (store, claimed, old_receipt) = flow7_lifecycle_claimed(
    fixture, "flow7-lifecycle-renew",
  )
  let renewal_authorization = flow7_lifecycle_active_authorization(
    "flow7-lifecycle-renewal",
    claimed,
    fixture.registration,
    old_receipt,
    RenewLeaseV2,
    Some(6L),
    12L,
  )
  let renewal = LeaseRenewalV2::new(
    "flow7-lifecycle-renewal",
    fixture.registration,
    old_receipt,
    renewal_authorization,
  )
  let request = prepare_lease_renewed_v2(
    claimed,
    "flow7-lifecycle-renewal-event",
    renewal.idempotency_key(),
    "flow7-lifecycle-renewal-command",
    renewal,
  )
  let first_result = commit_orchestration_v2(store, request)
  let duplicate_result = commit_orchestration_v2(store, request)
  assert_true(first_result == duplicate_result)
  let renewed = replay_orchestration_v2(store, fixture.schedule.workflow())
  guard renewed.committed_lease_authority_receipt() is Some(new_receipt) else {
    fail("expected renewed authority receipt")
  }
  assert_true(new_receipt.owner() == old_receipt.owner())
  assert_eq(new_receipt.epoch(), old_receipt.epoch())
  assert_eq(new_receipt.fencing_token(), old_receipt.fencing_token())
  assert_eq(new_receipt.expires_at(), 18L)
  assert_true(new_receipt.lease_authority_ref() == renewal.record_ref())
  assert_true(
    new_receipt.committed_event_ref() == request.events()[0].event_ref(),
  )
  assert_eq(renewed.revision(), request.expected_revision() + 1L)
  new_receipt.validate_current(renewed, 12L)
  try old_receipt.validate_current(renewed, 12L) catch {
    RevisionMismatch(expected~, actual~) => {
      assert_eq(expected, old_receipt.projection_revision())
      assert_eq(actual, renewed.revision())
    }
    _ => fail("expected old receipt revision rejection")
  } noraise {
    _ => fail("expected old receipt rejection")
  }
  try
    prepare_lease_renewed_v2(
      renewed,
      "flow7-lifecycle-stale-renew-event",
      renewal.idempotency_key(),
      "flow7-lifecycle-stale-renew-command",
      renewal,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected stale receipt predecessor rejection")
  }
}

///|
test "FLOW-7 V2 lifecycle rejects foreign registration proof reuse stale head backdating and deadline overflow" {
  let fixture = flow7_lifecycle_fixture("flow7-lifecycle-negative")
  let (negative_store, projection, receipt) = flow7_lifecycle_claimed(
    fixture, "flow7-lifecycle-negative",
  )
  let foreign = ScheduleRegisteredV2::new(
    "flow7-lifecycle-negative-foreign-registration",
    fixture.schedule,
  )
  try
    LeaseLifecycleRequestV2::for_active(
      "flow7-lifecycle-negative-foreign-request",
      ReleaseLeaseV2,
      foreign,
      receipt,
      None,
      "flow7-lifecycle-negative-foreign-key",
      flow7_v2_ref(
        "causation", "flow7-lifecycle-negative-foreign", b"flow7-lifecycle-negative-foreign",
      ),
    )
  catch {
    ReplayBindingViolation(field="lease_lifecycle_request_v2_registration") =>
      ()
    _ => fail("expected foreign registration rejection")
  } noraise {
    _ => fail("expected foreign registration rejection")
  }

  let request_a = LeaseLifecycleRequestV2::for_active(
    "flow7-lifecycle-negative-proof-a-request",
    ReleaseLeaseV2,
    fixture.registration,
    receipt,
    None,
    "flow7-lifecycle-negative-proof-a-key",
    flow7_v2_ref(
      "causation", "flow7-lifecycle-negative-proof-a", b"flow7-lifecycle-negative-proof-a",
    ),
  )
  let admission_a = flow7_lifecycle_operation_admission(
    "flow7-lifecycle-negative-proof-a",
    request_a,
    receipt.committed_event_ref(),
    projection.sequence(),
    projection.revision(),
    12L,
  )
  let request_b = LeaseLifecycleRequestV2::for_active(
    "flow7-lifecycle-negative-proof-b-request",
    ReleaseLeaseV2,
    fixture.registration,
    receipt,
    None,
    "flow7-lifecycle-negative-proof-b-key",
    flow7_v2_ref(
      "causation", "flow7-lifecycle-negative-proof-b", b"flow7-lifecycle-negative-proof-b",
    ),
  )
  try
    LeaseLifecycleAuthorizationV2::for_active(
      request_b, admission_a, projection, receipt,
    )
  catch {
    EffectProofMismatch(field="lease_lifecycle_operation_v2_request_tuple") =>
      ()
    _ => fail("expected proof reuse rejection")
  } noraise {
    _ => fail("expected proof reuse rejection")
  }

  let renewal_six = LeaseLifecycleRequestV2::for_active(
    "flow7-lifecycle-negative-renew-six",
    RenewLeaseV2,
    fixture.registration,
    receipt,
    Some(6L),
    "flow7-lifecycle-negative-renew-six-key",
    flow7_v2_ref(
      "causation", "flow7-lifecycle-negative-renew-six", b"flow7-lifecycle-negative-renew-six",
    ),
  )
  let renewal_six_admission = flow7_lifecycle_operation_admission(
    "flow7-lifecycle-negative-renew-six",
    renewal_six,
    receipt.committed_event_ref(),
    projection.sequence(),
    projection.revision(),
    12L,
  )
  let renewal_seven = LeaseLifecycleRequestV2::for_active(
    "flow7-lifecycle-negative-renew-seven",
    RenewLeaseV2,
    fixture.registration,
    receipt,
    Some(7L),
    "flow7-lifecycle-negative-renew-seven-key",
    flow7_v2_ref(
      "causation", "flow7-lifecycle-negative-renew-seven", b"flow7-lifecycle-negative-renew-seven",
    ),
  )
  try
    LeaseLifecycleAuthorizationV2::for_active(
      renewal_seven, renewal_six_admission, projection, receipt,
    )
  catch {
    EffectProofMismatch(field="lease_lifecycle_operation_v2_request_tuple") =>
      ()
    _ => fail("expected changed-TTL proof reuse rejection")
  } noraise {
    _ => fail("expected changed-TTL proof reuse rejection")
  }
  try
    LeaseLifecycleAuthorizationV2::for_active(
      renewal_six, admission_a, projection, receipt,
    )
  catch {
    EffectProofMismatch(field="lease_lifecycle_operation_v2_request_tuple") =>
      ()
    _ => fail("expected changed-verb proof reuse rejection")
  } noraise {
    _ => fail("expected changed-verb proof reuse rejection")
  }

  let stale_head_admission = flow7_lifecycle_operation_admission(
    "flow7-lifecycle-negative-stale-head",
    request_a,
    flow7_v2_ref(
      "event", "flow7-lifecycle-negative-stale-head", b"flow7-lifecycle-negative-stale-head",
    ),
    projection.sequence(),
    projection.revision(),
    12L,
  )
  try
    LeaseLifecycleAuthorizationV2::for_active(
      request_a, stale_head_admission, projection, receipt,
    )
  catch {
    ReplayBindingViolation(
      field="lease_lifecycle_operation_v2_authoritative_head"
    ) => ()
    _ => fail("expected stale authoritative head rejection")
  } noraise {
    _ => fail("expected stale authoritative head rejection")
  }

  let wrong_subject = flow7_lifecycle_operation_admission(
    "flow7-lifecycle-negative-subject",
    request_a,
    receipt.committed_event_ref(),
    projection.sequence(),
    projection.revision(),
    12L,
    mutation=LifecycleAdmissionWrongSubject,
  )
  try
    LeaseLifecycleAuthorizationV2::for_active(
      request_a, wrong_subject, projection, receipt,
    )
  catch {
    IdentityMismatch(field="lease_lifecycle_operation_v2_planned_subject") => ()
    _ => fail("expected planned subject rejection")
  } noraise {
    _ => fail("expected planned subject rejection")
  }

  let wrong_fence = flow7_lifecycle_operation_admission(
    "flow7-lifecycle-negative-fence",
    request_a,
    receipt.committed_event_ref(),
    projection.sequence(),
    projection.revision(),
    12L,
    mutation=LifecycleAdmissionWrongFence,
  )
  try
    LeaseLifecycleAuthorizationV2::for_active(
      request_a, wrong_fence, projection, receipt,
    )
  catch {
    EffectProofMismatch(field="lease_lifecycle_operation_v2_fencing") => ()
    _ => fail("expected fencing controls rejection")
  } noraise {
    _ => fail("expected fencing controls rejection")
  }

  let missing_capability = flow7_lifecycle_operation_admission(
    "flow7-lifecycle-negative-capability",
    request_a,
    receipt.committed_event_ref(),
    projection.sequence(),
    projection.revision(),
    12L,
    mutation=LifecycleAdmissionMissingCapability,
  )
  try
    LeaseLifecycleAuthorizationV2::for_active(
      request_a, missing_capability, projection, receipt,
    )
  catch {
    EffectProofMismatch(field="lease_lifecycle_operation_v2_capability") => ()
    _ => fail("expected missing capability rejection")
  } noraise {
    _ => fail("expected missing capability rejection")
  }

  let missing_evidence = flow7_lifecycle_operation_admission(
    "flow7-lifecycle-negative-evidence",
    request_a,
    receipt.committed_event_ref(),
    projection.sequence(),
    projection.revision(),
    12L,
    mutation=LifecycleAdmissionMissingEvidence,
  )
  try
    LeaseLifecycleAuthorizationV2::for_active(
      request_a, missing_evidence, projection, receipt,
    )
  catch {
    EvidenceMismatch(field="lease_lifecycle_operation_v2_evidence_empty") => ()
    _ => fail("expected missing evidence rejection")
  } noraise {
    _ => fail("expected missing evidence rejection")
  }

  try
    flow7_lifecycle_active_authorization(
      "flow7-lifecycle-negative-backdated",
      projection,
      fixture.registration,
      receipt,
      ReleaseLeaseV2,
      None,
      9L,
    )
  catch {
    AuthorityExpired(expires_at=15L, observed_at=9L) => ()
    _ => fail("expected backdated operation rejection")
  } noraise {
    _ => fail("expected backdated operation rejection")
  }

  let oversized_authorization = flow7_lifecycle_active_authorization(
    "flow7-lifecycle-negative-deadline",
    projection,
    fixture.registration,
    receipt,
    RenewLeaseV2,
    Some(90L),
    14L,
  )
  try
    LeaseRenewalV2::new(
      "flow7-lifecycle-negative-deadline",
      fixture.registration,
      receipt,
      oversized_authorization,
    )
  catch {
    AuthorityExpired(expires_at=20L, observed_at=104L) => ()
    _ => fail("expected operation deadline overflow rejection")
  } noraise {
    _ => fail("expected operation deadline overflow rejection")
  }

  let renewal_authorization = LeaseLifecycleAuthorizationV2::for_active(
    renewal_six, renewal_six_admission, projection, receipt,
  )
  let renewal = LeaseRenewalV2::new(
    "flow7-lifecycle-negative-renew-six",
    fixture.registration,
    receipt,
    renewal_authorization,
  )
  ignore(
    commit_orchestration_v2(
      negative_store,
      prepare_lease_renewed_v2(
        projection,
        "flow7-lifecycle-negative-renew-event",
        renewal.idempotency_key(),
        "flow7-lifecycle-negative-renew-command",
        renewal,
      ),
    ),
  )
  let renewed_projection = replay_orchestration_v2(
    negative_store,
    fixture.schedule.workflow(),
  )
  try
    LeaseLifecycleAuthorizationV2::for_active(
      request_a, admission_a, renewed_projection, receipt,
    )
  catch {
    ReplayBindingViolation(field="lease_lifecycle_operation_v2_current_receipt") =>
      ()
    _ => fail("expected stale predecessor receipt rejection")
  } noraise {
    _ => fail("expected stale predecessor receipt rejection")
  }
}

///|
test "FLOW-7 V2 release is terminal and double release fails closed" {
  let fixture = flow7_lifecycle_fixture("flow7-lifecycle-release")
  let (store, claimed, receipt) = flow7_lifecycle_claimed(
    fixture, "flow7-lifecycle-release",
  )
  let (released, release) = flow7_lifecycle_release(
    store, claimed, receipt, fixture, "flow7-lifecycle-release", 12L,
  )
  assert_true(release.owner() == receipt.owner())
  assert_true(!released.has_active_lease())
  assert_true(released.has_terminal_lease())
  assert_true(released.committed_lease_authority_receipt() is None)
  try
    prepare_lease_released_v2(
      released,
      "flow7-lifecycle-double-release-event",
      release.idempotency_key(),
      "flow7-lifecycle-double-release-command",
      release,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected double release rejection")
  }
}

///|
test "FLOW-7 V2 expiry requires exact due clock and removes receipt" {
  let fixture = flow7_lifecycle_fixture("flow7-lifecycle-expiry")
  let (store, claimed, receipt) = flow7_lifecycle_claimed(
    fixture, "flow7-lifecycle-expiry",
  )
  try
    LeaseExpiryV2::new(
      "flow7-lifecycle-early-expiry",
      fixture.registration,
      receipt,
      flow7_lifecycle_active_authorization(
        "flow7-lifecycle-early-expiry",
        claimed,
        fixture.registration,
        receipt,
        ExpireLeaseV2,
        None,
        14L,
      ),
    )
  catch {
    AuthorityExpired(expires_at=15L, observed_at=14L) => ()
    _ => fail("expected before-expiry clock rejection")
  } noraise {
    _ => fail("expected before-expiry clock rejection")
  }
  try
    LeaseExpiryV2::new(
      "flow7-lifecycle-unsupported-expiry",
      fixture.registration,
      receipt,
      flow7_lifecycle_active_authorization(
        "flow7-lifecycle-unsupported-expiry",
        claimed,
        fixture.registration,
        receipt,
        ReleaseLeaseV2,
        None,
        12L,
      ),
    )
  catch {
    ReplayBindingViolation(field="lease_expiry_v2_authorization") => ()
    _ => fail("expected exact expiry verb rejection")
  } noraise {
    _ => fail("expected exact expiry verb rejection")
  }
  let expiry = LeaseExpiryV2::new(
    "flow7-lifecycle-expiry-record",
    fixture.registration,
    receipt,
    flow7_lifecycle_active_authorization(
      "flow7-lifecycle-expiry-record",
      claimed,
      fixture.registration,
      receipt,
      ExpireLeaseV2,
      None,
      15L,
    ),
  )
  let stale_renewal = LeaseRenewalV2::new(
    "flow7-lifecycle-after-expiry-renewal",
    fixture.registration,
    receipt,
    flow7_lifecycle_active_authorization(
      "flow7-lifecycle-after-expiry-renewal",
      claimed,
      fixture.registration,
      receipt,
      RenewLeaseV2,
      Some(6L),
      12L,
    ),
  )
  let request = prepare_lease_expired_v2(
    claimed,
    "flow7-lifecycle-expiry-event",
    expiry.idempotency_key(),
    "flow7-lifecycle-expiry-command",
    expiry,
  )
  ignore(commit_orchestration_v2(store, request))
  let expired = replay_orchestration_v2(store, fixture.schedule.workflow())
  assert_true(!expired.has_active_lease())
  assert_true(expired.has_terminal_lease())
  assert_true(expired.committed_lease_authority_receipt() is None)
  assert_eq(expiry.observed_at(), 15L)
  try
    prepare_lease_renewed_v2(
      expired,
      "flow7-lifecycle-after-expiry-renewal-event",
      stale_renewal.idempotency_key(),
      "flow7-lifecycle-after-expiry-renewal-command",
      stale_renewal,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected renewal after expiry rejection")
  }
}

///|
test "FLOW-7 V2 reclaim is terminal-only monotonic and CAS single-winner" {
  let fixture = flow7_lifecycle_fixture("flow7-lifecycle-reclaim")
  let (store, claimed, receipt) = flow7_lifecycle_claimed(
    fixture, "flow7-lifecycle-reclaim",
  )
  let (released, release) = flow7_lifecycle_release(
    store, claimed, receipt, fixture, "flow7-lifecycle-reclaim", 12L,
  )
  ignore(release)
  let terminal_receipt = released.committed_lease_terminal_receipt().unwrap()
  let owner_a = flow7_v2_ref("owner", "reclaim-a", b"reclaim-a")
  let owner_b = flow7_v2_ref("owner", "reclaim-b", b"reclaim-b")
  let owner_a_request = LeaseLifecycleRequestV2::for_terminal(
    "flow7-lifecycle-owner-a-request",
    fixture.registration,
    terminal_receipt,
    owner_a,
    5L,
    2L,
    2L,
    "flow7-lifecycle-owner-a-key",
    flow7_v2_ref(
      "causation", "flow7-lifecycle-owner-a", b"flow7-lifecycle-owner-a",
    ),
  )
  let owner_a_admission = flow7_lifecycle_operation_admission(
    "flow7-lifecycle-owner-a",
    owner_a_request,
    terminal_receipt.committed_event_ref(),
    released.sequence(),
    released.revision(),
    13L,
  )
  let owner_b_request = LeaseLifecycleRequestV2::for_terminal(
    "flow7-lifecycle-owner-b-request",
    fixture.registration,
    terminal_receipt,
    owner_b,
    5L,
    2L,
    2L,
    "flow7-lifecycle-owner-b-key",
    flow7_v2_ref(
      "causation", "flow7-lifecycle-owner-b", b"flow7-lifecycle-owner-b",
    ),
  )
  try
    LeaseLifecycleAuthorizationV2::for_terminal(
      owner_b_request, owner_a_admission, released, terminal_receipt,
    )
  catch {
    EffectProofMismatch(field="lease_lifecycle_operation_v2_request_tuple") =>
      ()
    _ => fail("expected changed-owner proof reuse rejection")
  } noraise {
    _ => fail("expected changed-owner proof reuse rejection")
  }
  try
    LeaseReclaimV2::new(
      "flow7-lifecycle-equal-reclaim",
      fixture.registration,
      terminal_receipt,
      flow7_lifecycle_terminal_authorization(
        "flow7-lifecycle-equal-reclaim",
        released,
        fixture.registration,
        terminal_receipt,
        owner_a,
        5L,
        1L,
        2L,
        13L,
      ),
    )
  catch {
    LeaseEpochViolation(expected_greater_than=1L, actual=1L) => ()
    _ => fail("expected equal epoch rejection")
  } noraise {
    _ => fail("expected equal epoch rejection")
  }
  try
    LeaseReclaimV2::new(
      "flow7-lifecycle-equal-token-reclaim",
      fixture.registration,
      terminal_receipt,
      flow7_lifecycle_terminal_authorization(
        "flow7-lifecycle-equal-token-reclaim",
        released,
        fixture.registration,
        terminal_receipt,
        owner_a,
        5L,
        2L,
        1L,
        13L,
      ),
    )
  catch {
    FencingViolation(expected_greater_than=1L, actual=1L) => ()
    _ => fail("expected equal fencing token rejection")
  } noraise {
    _ => fail("expected equal fencing token rejection")
  }
  let reclaim_a = LeaseReclaimV2::new(
    "flow7-lifecycle-reclaim-a",
    fixture.registration,
    terminal_receipt,
    flow7_lifecycle_terminal_authorization(
      "flow7-lifecycle-reclaim-a",
      released,
      fixture.registration,
      terminal_receipt,
      owner_a,
      5L,
      2L,
      2L,
      13L,
    ),
  )
  let reclaim_b = LeaseReclaimV2::new(
    "flow7-lifecycle-reclaim-b",
    fixture.registration,
    terminal_receipt,
    flow7_lifecycle_terminal_authorization(
      "flow7-lifecycle-reclaim-b",
      released,
      fixture.registration,
      terminal_receipt,
      owner_b,
      5L,
      3L,
      3L,
      13L,
    ),
  )
  let request_a = prepare_lease_reclaimed_v2(
    released,
    "flow7-lifecycle-reclaim-a-event",
    reclaim_a.idempotency_key(),
    "flow7-lifecycle-reclaim-a-command",
    reclaim_a,
  )
  let request_b = prepare_lease_reclaimed_v2(
    released,
    "flow7-lifecycle-reclaim-b-event",
    reclaim_b.idempotency_key(),
    "flow7-lifecycle-reclaim-b-command",
    reclaim_b,
  )
  try
    prepare_lease_reclaimed_v2(
      claimed,
      "flow7-lifecycle-reclaim-before-terminal-event",
      reclaim_a.idempotency_key(),
      "flow7-lifecycle-reclaim-before-terminal-command",
      reclaim_a,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected reclaim before terminal rejection")
  }
  ignore(commit_orchestration_v2(store, request_a))
  try commit_orchestration_v2(store, request_b) catch {
    @storage.OptimisticRevisionConflict(expected~, actual~, ..) => {
      assert_eq(expected, released.revision())
      assert_eq(actual, released.revision() + 1L)
    }
    _ => fail("expected one reclaim CAS winner")
  } noraise {
    _ => fail("expected one reclaim CAS winner")
  }
  let reclaimed = replay_orchestration_v2(store, fixture.schedule.workflow())
  guard reclaimed.committed_lease_authority_receipt() is Some(new_receipt) else {
    fail("expected reclaim authority receipt")
  }
  assert_true(new_receipt.owner() == owner_a)
  assert_eq(new_receipt.epoch(), 2L)
  assert_eq(new_receipt.fencing_token(), 2L)
  assert_true(new_receipt.lease_authority_ref() == reclaim_a.record_ref())
  assert_true(!reclaimed.has_terminal_lease())
}

///|
fn flow7_lifecycle_append_byte(bytes : Bytes, value : Byte) -> Bytes {
  let buffer = @buffer.Buffer()
  buffer.write_bytes(bytes)
  buffer.write_byte(value)
  buffer.to_bytes()
}

///|
fn flow7_lifecycle_replace_last(bytes : Bytes, value : Byte) -> Bytes {
  let buffer = @buffer.Buffer()
  buffer.write_bytes(bytes[0:bytes.length() - 1])
  buffer.write_byte(value)
  buffer.to_bytes()
}

///|
fn flow7_lifecycle_reject_raw_transport_evidence(
  prefix : String,
  mode : Int,
) -> Unit raise {
  let fixture = flow7_lifecycle_fixture(prefix)
  let (store, projection, receipt) = flow7_lifecycle_claimed(fixture, prefix)
  let request = LeaseLifecycleRequestV2::for_active(
    prefix + "-request",
    RenewLeaseV2,
    fixture.registration,
    receipt,
    Some(6L),
    prefix + "-key",
    flow7_v2_ref(
      "causation",
      prefix + "-causation",
      @utf8.encode(prefix + "-causation"),
    ),
  )
  let admission = flow7_lifecycle_operation_admission(
    prefix,
    request,
    receipt.committed_event_ref(),
    projection.sequence(),
    projection.revision(),
    12L,
    mutation=LifecycleAdmissionTwoEvidence,
  )
  let authorization = LeaseLifecycleAuthorizationV2::for_active(
    request, admission, projection, receipt,
  )
  let renewal = LeaseRenewalV2::new(
    prefix + "-renewal",
    fixture.registration,
    receipt,
    authorization,
  )
  let exact = renewal.evidence()
  assert_eq(exact.length(), 2)
  let transported = match mode {
    0 => [exact[0]]
    1 => [exact[0], exact[0]]
    _ => [exact[1], exact[0]]
  }
  let event = flow7_durable_test_event(
    prefix + "-event",
    renewal.idempotency_key(),
    fixture.schedule.workflow(),
    "lease.renewed.v2",
    renewal.record_ref(),
    renewal.canonical_bytes(),
    transported,
    renewal.causation(),
    projection.sequence() + 1L,
    projection.revision() + 1L,
    projection.last_event_digest(),
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.schedule.workflow(),
        projection.revision(),
        prefix + "-command",
        [event],
        [],
      ),
    ),
  )
  let replay = store.replay(fixture.schedule.workflow())
  try fold_orchestration_v2(replay) catch {
    EvidenceMismatch(field="orchestration_v2_transport_evidence") => ()
    _ => fail("expected exact ordered transport evidence rejection: " + prefix)
  } noraise {
    _ => fail("expected exact ordered transport evidence rejection: " + prefix)
  }
}

///|
test "FLOW-7 V2 raw transport evidence rejects missing duplicate and reordered values" {
  flow7_lifecycle_reject_raw_transport_evidence("flow7-raw-evidence-missing", 0)
  flow7_lifecycle_reject_raw_transport_evidence(
    "flow7-raw-evidence-duplicate", 1,
  )
  flow7_lifecycle_reject_raw_transport_evidence(
    "flow7-raw-evidence-reordered", 2,
  )
}

///|
test "FLOW-7 V2 lifecycle codec rejects wrong id tamper truncation and trailing bytes" {
  let fixture = flow7_lifecycle_fixture("flow7-lifecycle-codec")
  let (_, projection, receipt) = flow7_lifecycle_claimed(
    fixture, "flow7-lifecycle-codec",
  )
  let renewal_authorization = flow7_lifecycle_active_authorization(
    "flow7-lifecycle-codec-renewal",
    projection,
    fixture.registration,
    receipt,
    RenewLeaseV2,
    Some(6L),
    12L,
  )
  let renewal = LeaseRenewalV2::new(
    "flow7-lifecycle-codec-renewal",
    fixture.registration,
    receipt,
    renewal_authorization,
  )
  let bytes = renewal.canonical_bytes()
  let roundtrip = LeaseRenewalV2::decode(
    "flow7-lifecycle-codec-renewal",
    fixture.registration,
    projection,
    receipt,
    bytes,
  )
  assert_true(roundtrip.canonical_bytes() == bytes)
  try
    LeaseRenewalV2::decode(
      "flow7-lifecycle-codec-wrong-id",
      fixture.registration,
      projection,
      receipt,
      bytes,
    )
  catch {
    IdentityMismatch(field=_) => ()
    _ => fail("expected wrong id rejection")
  } noraise {
    _ => fail("expected wrong id rejection")
  }
  try
    LeaseRenewalV2::decode(
      "flow7-lifecycle-codec-renewal",
      fixture.registration,
      projection,
      receipt,
      bytes[0:bytes.length() - 1].to_owned(),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected truncation rejection")
  }
  try
    LeaseRenewalV2::decode(
      "flow7-lifecycle-codec-renewal",
      fixture.registration,
      projection,
      receipt,
      flow7_lifecycle_append_byte(bytes, 0),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected trailing byte rejection")
  }
  try
    LeaseRenewalV2::decode(
      "flow7-lifecycle-codec-renewal",
      fixture.registration,
      projection,
      receipt,
      flow7_lifecycle_replace_last(bytes, 0),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected tamper rejection")
  }
}

///|
test "FLOW-7 V2 release and reclaim codecs reject wrong id truncation trailing bytes and tamper" {
  let fixture = flow7_lifecycle_fixture("flow7-codec-terminal")
  let (store, claimed, receipt) = flow7_lifecycle_claimed(
    fixture, "flow7-codec-terminal",
  )
  let release_authorization = flow7_lifecycle_active_authorization(
    "flow7-codec-release",
    claimed,
    fixture.registration,
    receipt,
    ReleaseLeaseV2,
    None,
    12L,
  )
  let release = LeaseReleaseV2::new(
    "flow7-codec-release",
    fixture.registration,
    receipt,
    release_authorization,
  )
  let release_bytes = release.canonical_bytes()
  assert_true(
    LeaseReleaseV2::decode(
      "flow7-codec-release",
      fixture.registration,
      claimed,
      receipt,
      release_bytes,
    ).canonical_bytes() ==
    release_bytes,
  )
  try
    LeaseReleaseV2::decode(
      "flow7-codec-release-wrong",
      fixture.registration,
      claimed,
      receipt,
      release_bytes,
    )
  catch {
    IdentityMismatch(field=_) => ()
    _ => fail("expected release wrong-id rejection")
  } noraise {
    _ => fail("expected release wrong-id rejection")
  }
  try
    LeaseReleaseV2::decode(
      "flow7-codec-release",
      fixture.registration,
      claimed,
      receipt,
      release_bytes[0:release_bytes.length() - 1].to_owned(),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected release truncation rejection")
  }
  try
    LeaseReleaseV2::decode(
      "flow7-codec-release",
      fixture.registration,
      claimed,
      receipt,
      flow7_lifecycle_append_byte(release_bytes, 0),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected release trailing-byte rejection")
  }
  try
    LeaseReleaseV2::decode(
      "flow7-codec-release",
      fixture.registration,
      claimed,
      receipt,
      flow7_lifecycle_replace_last(release_bytes, 0),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected release tamper rejection")
  }
  ignore(
    commit_orchestration_v2(
      store,
      prepare_lease_released_v2(
        claimed,
        "flow7-codec-release-event",
        release.idempotency_key(),
        "flow7-codec-release-command",
        release,
      ),
    ),
  )
  let released = replay_orchestration_v2(store, fixture.schedule.workflow())
  let terminal_receipt = released.committed_lease_terminal_receipt().unwrap()
  let reclaim_owner = flow7_v2_ref(
    "owner", "flow7-codec-reclaim-owner", b"flow7-codec-reclaim-owner",
  )
  let reclaim_authorization = flow7_lifecycle_terminal_authorization(
    "flow7-codec-reclaim",
    released,
    fixture.registration,
    terminal_receipt,
    reclaim_owner,
    5L,
    2L,
    2L,
    13L,
  )
  let reclaim = LeaseReclaimV2::new(
    "flow7-codec-reclaim",
    fixture.registration,
    terminal_receipt,
    reclaim_authorization,
  )
  let reclaim_bytes = reclaim.canonical_bytes()
  assert_true(
    LeaseReclaimV2::decode(
      "flow7-codec-reclaim",
      fixture.registration,
      released,
      terminal_receipt,
      reclaim_bytes,
    ).canonical_bytes() ==
    reclaim_bytes,
  )
  try
    LeaseReclaimV2::decode(
      "flow7-codec-reclaim-wrong",
      fixture.registration,
      released,
      terminal_receipt,
      reclaim_bytes,
    )
  catch {
    IdentityMismatch(field=_) => ()
    _ => fail("expected reclaim wrong-id rejection")
  } noraise {
    _ => fail("expected reclaim wrong-id rejection")
  }
  try
    LeaseReclaimV2::decode(
      "flow7-codec-reclaim",
      fixture.registration,
      released,
      terminal_receipt,
      reclaim_bytes[0:reclaim_bytes.length() - 1].to_owned(),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected reclaim truncation rejection")
  }
  try
    LeaseReclaimV2::decode(
      "flow7-codec-reclaim",
      fixture.registration,
      released,
      terminal_receipt,
      flow7_lifecycle_append_byte(reclaim_bytes, 0),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected reclaim trailing-byte rejection")
  }
  try
    LeaseReclaimV2::decode(
      "flow7-codec-reclaim",
      fixture.registration,
      released,
      terminal_receipt,
      flow7_lifecycle_replace_last(reclaim_bytes, 0),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected reclaim tamper rejection")
  }
}

///|
test "FLOW-7 V2 expiry codec rejects wrong id truncation trailing bytes and tamper" {
  let fixture = flow7_lifecycle_fixture("flow7-codec-expiry")
  let (_, projection, receipt) = flow7_lifecycle_claimed(
    fixture, "flow7-codec-expiry",
  )
  let authorization = flow7_lifecycle_active_authorization(
    "flow7-codec-expiry",
    projection,
    fixture.registration,
    receipt,
    ExpireLeaseV2,
    None,
    15L,
  )
  let expiry = LeaseExpiryV2::new(
    "flow7-codec-expiry",
    fixture.registration,
    receipt,
    authorization,
  )
  let bytes = expiry.canonical_bytes()
  assert_true(
    LeaseExpiryV2::decode(
      "flow7-codec-expiry",
      fixture.registration,
      projection,
      receipt,
      bytes,
    ).canonical_bytes() ==
    bytes,
  )
  try
    LeaseExpiryV2::decode(
      "flow7-codec-expiry-wrong",
      fixture.registration,
      projection,
      receipt,
      bytes,
    )
  catch {
    IdentityMismatch(field=_) => ()
    _ => fail("expected expiry wrong-id rejection")
  } noraise {
    _ => fail("expected expiry wrong-id rejection")
  }
  try
    LeaseExpiryV2::decode(
      "flow7-codec-expiry",
      fixture.registration,
      projection,
      receipt,
      bytes[0:bytes.length() - 1].to_owned(),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected expiry truncation rejection")
  }
  try
    LeaseExpiryV2::decode(
      "flow7-codec-expiry",
      fixture.registration,
      projection,
      receipt,
      flow7_lifecycle_append_byte(bytes, 0),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected expiry trailing-byte rejection")
  }
  try
    LeaseExpiryV2::decode(
      "flow7-codec-expiry",
      fixture.registration,
      projection,
      receipt,
      flow7_lifecycle_replace_last(bytes, 0),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected expiry tamper rejection")
  }
}

///|
fn flow7_lifecycle_raw_fold_rejects_payload(
  store : @storage.MemoryStore,
  projection : OrchestrationProjectionV2,
  event_kind : String,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  idempotency_key : String,
  prefix : String,
) -> Unit raise {
  let event = flow7_durable_test_event(
    prefix + "-event",
    idempotency_key,
    projection.workflow(),
    event_kind,
    subject,
    payload,
    evidence,
    causation,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    projection.last_event_digest(),
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        projection.workflow(),
        projection.revision(),
        prefix + "-command",
        [event],
        [],
      ),
    ),
  )
  let replay = store.replay(projection.workflow())
  try fold_orchestration_v2(replay) catch {
    _ => ()
  } noraise {
    _ => fail("expected raw successor payload rejection: " + prefix)
  }
}

///|
test "FLOW-7 V2 raw fold rejects malformed renewal release expiry and reclaim payloads" {
  let renewal_fixture = flow7_lifecycle_fixture("flow7-raw-fold-renewal")
  let (renewal_store, renewal_projection, renewal_receipt) = flow7_lifecycle_claimed(
    renewal_fixture, "flow7-raw-fold-renewal",
  )
  let renewal = LeaseRenewalV2::new(
    "flow7-raw-fold-renewal",
    renewal_fixture.registration,
    renewal_receipt,
    flow7_lifecycle_active_authorization(
      "flow7-raw-fold-renewal",
      renewal_projection,
      renewal_fixture.registration,
      renewal_receipt,
      RenewLeaseV2,
      Some(6L),
      12L,
    ),
  )
  flow7_lifecycle_raw_fold_rejects_payload(
    renewal_store,
    renewal_projection,
    "lease.renewed.v2",
    renewal.record_ref(),
    flow7_lifecycle_append_byte(renewal.canonical_bytes(), 0),
    [
      for value in renewal.evidence() => value
    ],
    renewal.causation(),
    renewal.idempotency_key(),
    "flow7-raw-fold-renewal",
  )

  let release_fixture = flow7_lifecycle_fixture("flow7-raw-fold-release")
  let (release_store, release_projection, release_receipt) = flow7_lifecycle_claimed(
    release_fixture, "flow7-raw-fold-release",
  )
  let release = LeaseReleaseV2::new(
    "flow7-raw-fold-release",
    release_fixture.registration,
    release_receipt,
    flow7_lifecycle_active_authorization(
      "flow7-raw-fold-release",
      release_projection,
      release_fixture.registration,
      release_receipt,
      ReleaseLeaseV2,
      None,
      12L,
    ),
  )
  flow7_lifecycle_raw_fold_rejects_payload(
    release_store,
    release_projection,
    "lease.released.v2",
    release.record_ref(),
    flow7_lifecycle_append_byte(release.canonical_bytes(), 0),
    [
      for value in release.evidence() => value
    ],
    release.causation(),
    release.idempotency_key(),
    "flow7-raw-fold-release",
  )

  let expiry_fixture = flow7_lifecycle_fixture("flow7-raw-fold-expiry")
  let (expiry_store, expiry_projection, expiry_receipt) = flow7_lifecycle_claimed(
    expiry_fixture, "flow7-raw-fold-expiry",
  )
  let expiry = LeaseExpiryV2::new(
    "flow7-raw-fold-expiry",
    expiry_fixture.registration,
    expiry_receipt,
    flow7_lifecycle_active_authorization(
      "flow7-raw-fold-expiry",
      expiry_projection,
      expiry_fixture.registration,
      expiry_receipt,
      ExpireLeaseV2,
      None,
      15L,
    ),
  )
  flow7_lifecycle_raw_fold_rejects_payload(
    expiry_store,
    expiry_projection,
    "lease.expired.v2",
    expiry.record_ref(),
    flow7_lifecycle_append_byte(expiry.canonical_bytes(), 0),
    [
      for value in expiry.evidence() => value
    ],
    expiry.causation(),
    expiry.idempotency_key(),
    "flow7-raw-fold-expiry",
  )

  let reclaim_fixture = flow7_lifecycle_fixture("flow7-raw-fold-reclaim")
  let (reclaim_store, reclaim_claimed, reclaim_receipt) = flow7_lifecycle_claimed(
    reclaim_fixture, "flow7-raw-fold-reclaim",
  )
  let (reclaim_released, _) = flow7_lifecycle_release(
    reclaim_store, reclaim_claimed, reclaim_receipt, reclaim_fixture, "flow7-raw-fold-reclaim",
    12L,
  )
  let terminal_receipt = reclaim_released
    .committed_lease_terminal_receipt()
    .unwrap()
  let reclaim = LeaseReclaimV2::new(
    "flow7-raw-fold-reclaim-record",
    reclaim_fixture.registration,
    terminal_receipt,
    flow7_lifecycle_terminal_authorization(
      "flow7-raw-fold-reclaim-record",
      reclaim_released,
      reclaim_fixture.registration,
      terminal_receipt,
      flow7_v2_ref(
        "owner", "flow7-raw-fold-reclaim-owner", b"flow7-raw-fold-reclaim-owner",
      ),
      5L,
      2L,
      2L,
      13L,
    ),
  )
  flow7_lifecycle_raw_fold_rejects_payload(
    reclaim_store,
    reclaim_released,
    "lease.reclaimed.v2",
    reclaim.record_ref(),
    flow7_lifecycle_append_byte(reclaim.canonical_bytes(), 0),
    [
      for value in reclaim.evidence() => value
    ],
    reclaim.causation(),
    reclaim.idempotency_key(),
    "flow7-raw-fold-reclaim",
  )
}
