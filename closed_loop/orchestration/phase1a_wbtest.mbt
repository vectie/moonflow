///|
fn phase1a_wb_ref(
  kind : String,
  id : String,
  bytes : Bytes,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    "2.2.0",
    @contracts.sha256_digest(bytes).text(),
  )
}

///|
fn phase1a_replace_occurrence(
  source : Bytes,
  needle : Bytes,
  occurrence : Int,
  replacement : Byte,
) -> Bytes {
  let changed = source.to_array()
  let mut seen = 0
  let mut replaced = false
  if needle.is_empty() || source.length() < needle.length() {
    abort("invalid replacement needle")
  }
  for offset in 0..<=(source.length() - needle.length()) {
    let mut matches = true
    for index in 0..<needle.length() {
      if source[offset + index] != needle[index] {
        matches = false
      }
    }
    if matches {
      if seen == occurrence {
        changed[offset] = replacement
        replaced = true
      }
      seen = seen + 1
    }
  }
  if !replaced {
    abort("replacement occurrence missing")
  }
  Bytes::from_array(changed)
}

///|
priv struct Phase1aWbInitial {
  authorization : InitialWorkAuthorizationV2
  registration : ScheduleRegisteredV2
  e1 : @storage.WorkflowEvent
  e2 : @storage.WorkflowEvent
  e3 : @storage.WorkflowEvent
  r2 : CommittedRetryPolicyBindingV2
  r3 : CommittedCancellationGovernanceBindingV2
}

///|
fn phase1a_wb_retry_policy() -> RetryPolicyV2 raise OrchestrationError {
  RetryPolicyV2::new(
    "flow7-retry-policy",
    "2.0.0",
    5L,
    4L,
    10L,
    1000L,
    2L,
    1L,
    31L,
    @contracts.sha256_digest(b"flow7-v2-retry-seed"),
    ["terminal_failed", "reconciled_not_applied"],
  )
}

///|
fn phase1a_wb_position() -> @effects_authorization.ReplayPosition raise OrchestrationError {
  orchestration_genesis_position_v2(
    phase1a_wb_ref("workflow", "proof-v2-workflow", b"proof-v2-workflow"),
  )
}

///|
fn phase1a_wb_policy() -> @governance.GovernancePolicy {
  try! @governance.GovernancePolicy::new(
    "proof-v2-policy",
    "1.0.0",
    "1.0.0",
    "1.0.0",
    ["authority"],
    ["reviewer"],
    1,
    1,
    [@governance.Approved],
  )
}

///|
fn phase1a_wb_admission(
  proof_suffix? : String = "",
) -> AdmissionV2 raise OrchestrationError {
  let producer_ref = phase1a_wb_ref(
    "producer", "proof-v2-producer", b"proof-v2-producer",
  )
  let producer = @effects_authorization.ProducerDescriptor::new(
    "fixture.producer",
    "1.0.0",
    producer_ref,
    producer_ref.digest(),
  ).unwrap()
  let decision = phase1a_wb_ref(
    "decision", "proof-v2-decision", b"proof-v2-decision",
  )
  let subject = phase1a_wb_ref(
    "subject", "proof-v2-subject", b"proof-v2-subject",
  )
  let policy_ref = phase1a_wb_policy().policy_ref()
  let governance = @effects_authorization.AuthorizationGovernanceBinding::new(
    decision,
    decision.digest(),
    policy_ref,
    policy_ref.digest(),
    subject,
    10L,
    20L,
  ).unwrap()
  let workflow = phase1a_wb_ref(
    "workflow", "proof-v2-workflow", b"proof-v2-workflow",
  )
  let requested = phase1a_wb_ref(
    "requested-work", "proof-v2-requested", b"proof-v2-requested",
  )
  let effect = phase1a_wb_ref(
    "effect-request", "proof-v2-effect", b"proof-v2-effect",
  )
  let planned = @effects_authorization.PlannedEffectTuple::new(
    workflow,
    subject,
    "attempt",
    "1",
    "effect",
    "1",
    1L,
    "proof-v2-idempotency",
    requested,
    requested.digest(),
    effect,
    effect.digest(),
    @contracts.sha256_digest(b"proof-v2-artifact"),
  ).unwrap()
  let evidence_ref = phase1a_wb_ref(
    "evidence", "proof-v2-evidence", b"proof-v2-evidence",
  )
  let evidence = @effects_authorization.EvidenceBinding::new(
    evidence_ref,
    evidence_ref.digest(),
  ).unwrap()
  let capability_ref = phase1a_wb_ref(
    "capability", "proof-v2-capability", b"proof-v2-capability",
  )
  let capability = @effects_authorization.CapabilityBinding::new(
    capability_ref,
    capability_ref.digest(),
  ).unwrap()
  let fencing_ref = phase1a_wb_ref(
    "fencing", "proof-v2-fencing", b"proof-v2-fencing",
  )
  let fencing = @effects_authorization.FencingBinding::new(fencing_ref, 1L, 1L).unwrap()
  let controls = @effects_authorization.AuthorizationControls::new(
    Some(capability),
    [evidence],
    Some(fencing),
    Some(10L),
    20L,
  ).unwrap()
  let eligibility = @effects_authorization.EligibilityBinding::new(
    10L,
    phase1a_wb_position(),
  ).unwrap()
  let authorization = @effects_authorization.PreDispatchAuthorization::new(
    "proof-v2-authorization", producer, governance, eligibility, planned, controls,
  ).unwrap()
  let e0 = @effects_authorization.AuthorizationEventEnvelopeV2::new(
    "flow7-v2-authorization-event",
    @effects_authorization.AuthorizationEventKindV2::pre_dispatch_authorization_committed(),
    @effects_authorization.contract_version,
    "FLOW-6C.authorization-event-envelope.v2",
    authorization.record_ref(),
    authorization.record_digest(),
    0L,
    0L,
    @effects_authorization.authorization_event_genesis_digest_v2,
    @effects_authorization.authorization_event_genesis_digest_v2,
    authorization.canonical_bytes(),
  ).unwrap()
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
    "proof-v2-attempt", auth_link, producer, governance, eligibility, planned, controls,
  ).unwrap()
  let e1 = @effects_authorization.AuthorizationEventEnvelopeV2::new(
    "flow7-v2-attempt-event",
    @effects_authorization.AuthorizationEventKindV2::authorized_attempt_registration_committed(),
    @effects_authorization.contract_version,
    "FLOW-6C.authorization-event-envelope.v2",
    attempt.record_ref(),
    attempt.record_digest(),
    1L,
    1L,
    e0.event_digest(),
    e0.event_digest(),
    attempt.canonical_bytes(),
  ).unwrap()
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
    "proof-v2-intent", auth_link, attempt_link, producer, governance, eligibility,
    planned, controls,
  ).unwrap()
  let e2 = @effects_authorization.AuthorizationEventEnvelopeV2::new(
    "flow7-v2-intent-event",
    @effects_authorization.AuthorizationEventKindV2::authorized_effect_intent_committed(),
    @effects_authorization.contract_version,
    "FLOW-6C.authorization-event-envelope.v2",
    intent.record_ref(),
    intent.record_digest(),
    2L,
    2L,
    e1.event_digest(),
    e1.event_digest(),
    intent.canonical_bytes(),
  ).unwrap()
  let auth_store = @effects_authorization.AuthorizationEventStoreV2::new()
  ignore(auth_store.append(e0).unwrap())
  ignore(auth_store.append(e1).unwrap())
  ignore(auth_store.append(e2).unwrap())
  let proof = @effects_authorization.derive_eligible_authorization_proof_commit_v2(
      auth_store,
      "flow7-v2-proof" + proof_suffix,
      "flow7-v2-proof-event" + proof_suffix,
    )
    .unwrap()
    .proof()
  AdmissionV2::decode("flow7-v2-proof" + proof_suffix, proof.canonical_bytes())
}

///|
fn phase1a_wb_schedule() -> ScheduleIntentV2 raise OrchestrationError {
  let admission = phase1a_wb_admission()
  let evidence_record = phase1a_wb_ref(
    "evidence", "proof-v2-evidence", b"proof-v2-evidence",
  )
  let provenance = phase1a_wb_ref(
    "provenance", "proof-v2-provenance", b"proof-v2-provenance",
  )
  let evidence = try! @contracts.EvidenceRef::new(
    evidence_record,
    provenance,
    evidence_record.digest().text(),
  )
  ScheduleIntentV2::new(
    "flow7-v2-schedule",
    "2.0.0",
    admission,
    admission.planned().workflow(),
    10L,
    Some(20L),
    [evidence],
    phase1a_wb_ref("causation", "flow7-v2-schedule", b"flow7-v2-schedule"),
    "flow7-v2-schedule-idempotency",
  )
}

///|
fn phase1a_wb_initial_with_retry_policy(
  retry_policy : RetryPolicyV2,
) -> Phase1aWbInitial raise {
  let schedule = phase1a_wb_schedule()
  let registration = ScheduleRegisteredV2::new(
    "phase1a-wb-registration", schedule,
  )
  let store = @storage.MemoryStore::new()
  let policy = phase1a_wb_policy()
  let empty_effects = @effects.EffectsProjection::new(
    schedule.workflow(),
    policy.policy_ref(),
  )
  let aggregate = fold_empty_closed_loop_v22(
    empty_effects,
    store.replay(schedule.workflow()),
  )
  let authorization = authorize_initial_work_v22(
    "phase1a-wb-authorization",
    aggregate,
    registration,
    retry_policy,
    policy,
    phase1a_wb_ref("governance-stream", "phase1a-wb-governance", b"governance"),
    20L,
    "phase1a-wb-e1",
    "phase1a-wb-r2",
    "phase1a-wb-e2",
    "phase1a-wb-e2-key",
    "phase1a-wb-r3",
    "phase1a-wb-e3",
    "phase1a-wb-e3-key",
    "phase1a-wb-command",
  )
  let request = prepare_initial_work_v22(authorization, registration)
  let e1 = request.events()[0]
  let e2 = request.events()[1]
  let e3 = request.events()[2]
  let r2 = verify_retry_policy_binding_v22(
    e2.payload().subject(),
    e1,
    e2.payload().payload(),
  )
  let r3 = verify_cancellation_governance_binding_v22(
    e3.payload().subject(),
    e1,
    r2,
    e2,
    e3.payload().payload(),
  )
  { authorization, registration, e1, e2, e3, r2, r3 }
}

///|
fn phase1a_wb_initial() -> Phase1aWbInitial raise {
  phase1a_wb_initial_with_retry_policy(phase1a_wb_retry_policy())
}

///|
test "FLOW-7 Phase1A initial authorization private codec is strict" {
  let authorization = phase1a_wb_initial().authorization
  let canonical = authorization.canonical
  let decoded = decode_initial_work_authorization_v22(
    authorization.authorization_ref,
    canonical,
  )
  assert_true(decoded.canonical == canonical)
  let invalid_tag = phase1a_replace_occurrence(
    canonical, b"FLOW7/INITIAL-WORK-AUTHORIZATION-V2/2.2.0", 0, b'X',
  )
  try
    decode_initial_work_authorization_v22(
      authorization.authorization_ref,
      invalid_tag,
    )
  catch {
    MalformedInput(field="initial_work_authorization_tag") => ()
    _ => fail("unexpected authorization-tag error")
  } noraise {
    _ => fail("accepted invalid authorization tag")
  }
  let unsupported = phase1a_replace_occurrence(canonical, b"2.2.0", 1, b'9')
  try
    decode_initial_work_authorization_v22(
      authorization.authorization_ref,
      unsupported,
    )
  catch {
    UnsupportedVersion(field="initial_work_authorization", version="9.2.0") =>
      ()
    _ => fail("unexpected authorization-version error")
  } noraise {
    _ => fail("accepted unsupported authorization version")
  }
  let wrong_identity = try! @contracts.RecordRef::new(
    authorization.authorization_ref.kind(),
    authorization.authorization_ref.id() + "-wrong",
    authorization.authorization_ref.version().text(),
    authorization.authorization_ref.digest().text(),
  )
  try decode_initial_work_authorization_v22(wrong_identity, canonical) catch {
    DigestMismatch(field="initial_work_authorization_expected_ref") => ()
    _ => fail("unexpected authorization expected-identity error")
  } noraise {
    _ => fail("accepted wrong authorization identity")
  }
  let wrong_digest = try! @contracts.RecordRef::new(
    authorization.authorization_ref.kind(),
    authorization.authorization_ref.id(),
    authorization.authorization_ref.version().text(),
    @contracts.sha256_digest(b"wrong-authorization-digest").text(),
  )
  try decode_initial_work_authorization_v22(wrong_digest, canonical) catch {
    DigestMismatch(field="initial_work_authorization_expected_ref") => ()
    _ => fail("unexpected authorization expected-digest error")
  } noraise {
    _ => fail("accepted wrong authorization digest")
  }
  for
    noncanonical in [
      canonical[:canonical.length() - 1].to_owned(),
      canonical + b"trailing",
    ] {
    try
      decode_initial_work_authorization_v22(
        authorization.authorization_ref,
        noncanonical,
      )
    catch {
      MalformedInput(field=_) | DigestMismatch(field=_) => ()
      _ => fail("unexpected noncanonical authorization error")
    } noraise {
      _ => fail("accepted noncanonical authorization bytes")
    }
  }
}

///|
fn phase1a_wb_replay(
  fixture : Phase1aWbInitial,
  registration? : ScheduleRegisteredV2,
  evidence? : Array[@contracts.EvidenceRef],
  causation? : @contracts.RecordRef,
  e1_key? : String,
  e2_evidence? : Array[@contracts.EvidenceRef],
  e2_causation? : @contracts.RecordRef,
  e2_key? : String,
  e3_evidence? : Array[@contracts.EvidenceRef],
  e3_causation? : @contracts.RecordRef,
  e3_key? : String,
  command_key? : String,
  swapped? : Bool = false,
  extra? : Bool = false,
) -> @storage.ReplayResult raise {
  let authorization = fixture.authorization
  let registration = registration.unwrap_or(fixture.registration)
  let schedule = registration.schedule()
  let evidence = evidence.unwrap_or(
    [
      for value in schedule.evidence() => value
    ],
  )
  let causation = causation.unwrap_or(schedule.causation_ref())
  let e2_evidence = e2_evidence.unwrap_or(evidence)
  let e2_causation = e2_causation.unwrap_or(causation)
  let e3_evidence = e3_evidence.unwrap_or(evidence)
  let e3_causation = e3_causation.unwrap_or(causation)
  let e1 = phase1a_event_v22(
    registration.workflow(),
    authorization.schedule_event_id,
    schedule_registered_event_kind_v2,
    registration.record_ref(),
    registration.canonical_bytes(),
    evidence,
    causation,
    e1_key.unwrap_or(schedule.idempotency_key()),
    1L,
    1L,
    None,
  )
  let r2 = build_retry_policy_binding_v22(
    authorization.retry_binding_id,
    registration,
    e1,
    authorization,
  )
  let e2 = phase1a_event_v22(
    registration.workflow(),
    authorization.retry_binding_event_id,
    retry_policy_bound_event_kind_v22,
    r2.record_ref(),
    r2.canonical_bytes(),
    e2_evidence,
    e2_causation,
    e2_key.unwrap_or(authorization.retry_binding_event_key),
    2L,
    2L,
    Some(e1.event_ref().digest()),
  )
  let r3 = build_cancellation_governance_binding_v22(
    authorization.governance_binding_id,
    registration,
    e1,
    r2,
    e2,
    authorization.governance_stream_ref,
    authorization.governance_policy.policy_ref(),
    authorization.governance_policy.canonical_bytes(),
    authorization.governance_valid_until_inclusive,
  )
  let e3 = phase1a_event_v22(
    registration.workflow(),
    authorization.governance_binding_event_id,
    cancellation_governance_bound_event_kind_v22,
    r3.record_ref(),
    r3.canonical_bytes(),
    e3_evidence,
    e3_causation,
    e3_key.unwrap_or(authorization.governance_binding_event_key),
    3L,
    3L,
    Some(e2.event_ref().digest()),
  )
  let events : Array[@storage.WorkflowEvent] = if swapped {
    let swapped_e2 = phase1a_event_v22(
      registration.workflow(),
      authorization.retry_binding_event_id,
      cancellation_governance_bound_event_kind_v22,
      r3.record_ref(),
      r3.canonical_bytes(),
      evidence,
      causation,
      authorization.retry_binding_event_key,
      2L,
      2L,
      Some(e1.event_ref().digest()),
    )
    let swapped_e3 = phase1a_event_v22(
      registration.workflow(),
      authorization.governance_binding_event_id,
      retry_policy_bound_event_kind_v22,
      r2.record_ref(),
      r2.canonical_bytes(),
      evidence,
      causation,
      authorization.governance_binding_event_key,
      3L,
      3L,
      Some(swapped_e2.event_ref().digest()),
    )
    [e1, swapped_e2, swapped_e3]
  } else if extra {
    let e4 = phase1a_event_v22(
      registration.workflow(),
      authorization.governance_binding_event_id + "-extra",
      cancellation_governance_bound_event_kind_v22,
      r3.record_ref(),
      r3.canonical_bytes(),
      evidence,
      causation,
      authorization.governance_binding_event_key + "-extra",
      4L,
      4L,
      Some(e3.event_ref().digest()),
    )
    [e1, e2, e3, e4]
  } else {
    [e1, e2, e3]
  }
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        registration.workflow(),
        0L,
        command_key.unwrap_or(authorization.command_idempotency_key),
        events,
        [],
      ),
    ),
  )
  store.replay(registration.workflow())
}

///|
fn phase1a_expect_receipt_rejection(
  empty_effects : @effects.EffectsProjection,
  replay : @storage.ReplayResult,
  expected : String,
) -> Unit raise {
  try fold_initial_work_receipt_v22(empty_effects, replay) catch {
    ReplayBindingViolation(field~) => assert_eq(field, expected)
    PolicyMismatch(field~) => assert_eq(field, expected)
    _ => fail("unexpected strict initial-work replay rejection")
  } noraise {
    _ => fail("accepted invalid re-chained initial-work replay")
  }
}

///|
test "FLOW-7 Phase1A rejects re-chained wrapper batch and admission substitutions" {
  let fixture = phase1a_wb_initial()
  let workflow = fixture.registration.workflow()
  let empty_effects = @effects.EffectsProjection::new(
    workflow,
    fixture.authorization.governance_policy.policy_ref(),
  )
  let bad_evidence_record = phase1a_wb_ref(
    "evidence", "phase1a-bad-evidence", b"phase1a-bad-evidence",
  )
  let bad_evidence = try! @contracts.EvidenceRef::new(
    bad_evidence_record,
    phase1a_wb_ref(
      "provenance", "phase1a-bad-provenance", b"phase1a-bad-provenance",
    ),
    bad_evidence_record.digest().text(),
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(fixture, evidence=[bad_evidence]),
    "initial_work_wrapper_binding",
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(
      fixture,
      causation=phase1a_wb_ref(
        "causation", "phase1a-bad-cause", b"phase1a-bad-cause",
      ),
    ),
    "initial_work_wrapper_binding",
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(fixture, e1_key="phase1a-bad-e1-key"),
    "initial_work_wrapper_binding",
  )
  for stage in ["e2", "e3"] {
    let stage_evidence = if stage == "e2" { Some([bad_evidence]) } else { None }
    let stage_e3_evidence = if stage == "e3" {
      Some([bad_evidence])
    } else {
      None
    }
    phase1a_expect_receipt_rejection(
      empty_effects,
      phase1a_wb_replay(
        fixture,
        e2_evidence?=stage_evidence,
        e3_evidence?=stage_e3_evidence,
      ),
      "initial_work_wrapper_binding",
    )
  }
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(
      fixture,
      e2_causation=phase1a_wb_ref(
        "causation", "phase1a-bad-e2-cause", b"phase1a-bad-e2-cause",
      ),
    ),
    "initial_work_wrapper_binding",
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(fixture, e2_key="phase1a-bad-e2-key"),
    "initial_work_wrapper_binding",
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(
      fixture,
      e3_causation=phase1a_wb_ref(
        "causation", "phase1a-bad-e3-cause", b"phase1a-bad-e3-cause",
      ),
    ),
    "initial_work_wrapper_binding",
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(fixture, e3_key="phase1a-bad-e3-key"),
    "initial_work_wrapper_binding",
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(fixture, command_key="phase1a-bad-command"),
    "initial_admission_v22_r2",
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(fixture, swapped=true),
    "root_retry_policy_binding_missing",
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(fixture, extra=true),
    "initial_admission_v22_batch",
  )
  let substituted_admission = phase1a_wb_admission(proof_suffix="-substitute")
  let schedule = fixture.registration.schedule()
  let substituted_schedule = ScheduleIntentV2::new(
    "flow7-v2-schedule-substitute",
    "2.0.0",
    substituted_admission,
    workflow,
    10L,
    Some(20L),
    [
      for value in schedule.evidence() => value
    ],
    schedule.causation_ref(),
    "flow7-v2-schedule-substitute-key",
  )
  let substituted_registration = ScheduleRegisteredV2::new(
    "phase1a-wb-registration-substitute", substituted_schedule,
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    phase1a_wb_replay(fixture, registration=substituted_registration),
    "retry_policy_binding_v22_e1",
  )
}

///|
test "FLOW-7 Phase1A rejects duplicated interleaved and outbox-bearing root history" {
  let fixture = phase1a_wb_initial()
  let authorization = fixture.authorization
  let workflow = fixture.registration.workflow()
  let schedule = fixture.registration.schedule()
  let evidence = [ for value in schedule.evidence() => value ]
  let empty_effects = @effects.EffectsProjection::new(
    workflow,
    authorization.governance_policy.policy_ref(),
  )

  let duplicate_store = @storage.MemoryStore::new()
  ignore(
    duplicate_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        0L,
        authorization.command_idempotency_key,
        [fixture.e1, fixture.e2, fixture.e3],
        [],
      ),
    ),
  )
  let duplicate_e1 = phase1a_event_v22(
    workflow,
    authorization.schedule_event_id + "-duplicate",
    schedule_registered_event_kind_v2,
    fixture.registration.record_ref(),
    fixture.registration.canonical_bytes(),
    evidence,
    schedule.causation_ref(),
    schedule.idempotency_key() + "-duplicate",
    4L,
    4L,
    Some(fixture.e3.event_ref().digest()),
  )
  let duplicate_r2 = build_retry_policy_binding_v22(
    authorization.retry_binding_id,
    fixture.registration,
    duplicate_e1,
    authorization,
  )
  let duplicate_e2 = phase1a_event_v22(
    workflow,
    authorization.retry_binding_event_id + "-duplicate",
    retry_policy_bound_event_kind_v22,
    duplicate_r2.record_ref(),
    duplicate_r2.canonical_bytes(),
    evidence,
    schedule.causation_ref(),
    authorization.retry_binding_event_key + "-duplicate",
    5L,
    5L,
    Some(duplicate_e1.event_ref().digest()),
  )
  let duplicate_r3 = build_cancellation_governance_binding_v22(
    authorization.governance_binding_id,
    fixture.registration,
    duplicate_e1,
    duplicate_r2,
    duplicate_e2,
    authorization.governance_stream_ref,
    authorization.governance_policy.policy_ref(),
    authorization.governance_policy.canonical_bytes(),
    authorization.governance_valid_until_inclusive,
  )
  let duplicate_e3 = phase1a_event_v22(
    workflow,
    authorization.governance_binding_event_id + "-duplicate",
    cancellation_governance_bound_event_kind_v22,
    duplicate_r3.record_ref(),
    duplicate_r3.canonical_bytes(),
    evidence,
    schedule.causation_ref(),
    authorization.governance_binding_event_key + "-duplicate",
    6L,
    6L,
    Some(duplicate_e2.event_ref().digest()),
  )
  ignore(
    duplicate_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        3L,
        authorization.command_idempotency_key + "-duplicate",
        [duplicate_e1, duplicate_e2, duplicate_e3],
        [],
      ),
    ),
  )
  try
    fold_initial_work_receipt_v22(
      empty_effects,
      duplicate_store.replay(workflow),
    )
  catch {
    ReplayBindingViolation(field="initial_admission_v22_duplicate_root") => ()
    _ => fail("unexpected duplicated-root error")
  } noraise {
    _ => fail("accepted correctly re-chained duplicated root history")
  }

  let unrelated = phase1a_event_v22(
    workflow,
    "phase1a-interleaved-unrelated",
    "unrelated.root.probe.v2",
    fixture.registration.record_ref(),
    b"unrelated",
    evidence,
    schedule.causation_ref(),
    "phase1a-interleaved-unrelated-key",
    2L,
    2L,
    Some(fixture.e1.event_ref().digest()),
  )
  let interleaved_e2 = phase1a_event_v22(
    workflow,
    authorization.retry_binding_event_id,
    retry_policy_bound_event_kind_v22,
    fixture.r2.record_ref(),
    fixture.r2.canonical_bytes(),
    evidence,
    schedule.causation_ref(),
    authorization.retry_binding_event_key,
    3L,
    3L,
    Some(unrelated.event_ref().digest()),
  )
  let interleaved_r3 = build_cancellation_governance_binding_v22(
    authorization.governance_binding_id,
    fixture.registration,
    fixture.e1,
    fixture.r2,
    interleaved_e2,
    authorization.governance_stream_ref,
    authorization.governance_policy.policy_ref(),
    authorization.governance_policy.canonical_bytes(),
    authorization.governance_valid_until_inclusive,
  )
  let interleaved_e3 = phase1a_event_v22(
    workflow,
    authorization.governance_binding_event_id,
    cancellation_governance_bound_event_kind_v22,
    interleaved_r3.record_ref(),
    interleaved_r3.canonical_bytes(),
    evidence,
    schedule.causation_ref(),
    authorization.governance_binding_event_key,
    4L,
    4L,
    Some(interleaved_e2.event_ref().digest()),
  )
  let interleaved_store = @storage.MemoryStore::new()
  ignore(
    interleaved_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        0L,
        "phase1a-interleaved-command",
        [fixture.e1, unrelated, interleaved_e2, interleaved_e3],
        [],
      ),
    ),
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    interleaved_store.replay(workflow),
    "root_retry_policy_binding_missing",
  )

  let root_intent = @storage.OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    "phase1a-root-outbox",
    workflow,
    fixture.e3.event_ref(),
    "phase1a-root-outbox-key",
    fixture.e3.payload(),
    evidence,
  )
  let outbox_store = @storage.MemoryStore::new()
  ignore(
    outbox_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        0L,
        "phase1a-root-outbox-command",
        [fixture.e1, fixture.e2, fixture.e3],
        [root_intent],
      ),
    ),
  )
  phase1a_expect_receipt_rejection(
    empty_effects,
    outbox_store.replay(workflow),
    "initial_admission_v22_batch",
  )
}

///|
fn phase1a_r2_signing_fixture(
  binding_id : String,
  workflow : @contracts.RecordRef,
  registration_ref : @contracts.RecordRef,
  e1 : @storage.WorkflowEvent,
  authorization : InitialWorkAuthorizationV2,
  e1_ref_override? : @contracts.RecordRef,
  e1_digest_override? : Bytes,
  e1_bytes_override? : Bytes,
  retry_policy_bytes_override? : Bytes,
  trailing? : Bytes,
) -> Bytes raise OrchestrationError {
  let e1_ref = e1_ref_override.unwrap_or(e1.event_ref())
  let policy_bytes = authorization.retry_policy.canonical_bytes()
  let policy_ref = authorization.retry_policy.policy_ref()
  let proof_bytes = authorization.admission_proof_bytes
  let proof_ref = authorization.admission_proof_ref
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-RETRY-POLICY-BINDING-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(binding_id)
  write_ref(writer, workflow)
  write_ref(writer, registration_ref)
  write_ref(writer, e1_ref)
  writer.bytes(
    e1_digest_override.unwrap_or(@utf8.encode(e1_ref.digest().text())),
  )
  writer.bytes(e1_bytes_override.unwrap_or(e1.canonical_bytes()))
  write_ref(writer, policy_ref)
  writer.bytes(@utf8.encode(policy_ref.digest().text()))
  writer.bytes(retry_policy_bytes_override.unwrap_or(policy_bytes))
  write_ref(writer, proof_ref)
  writer.bytes(@utf8.encode(proof_ref.digest().text()))
  writer.bytes(proof_bytes)
  write_ref(writer, authorization.authorization_ref)
  writer.bytes(@utf8.encode(authorization.digest.text()))
  writer.bytes(authorization.canonical)
  writer.string(authorization.schedule_event_id)
  writer.string(authorization.retry_binding_event_id)
  writer.string(authorization.retry_binding_event_key)
  writer.string(authorization.governance_binding_id)
  writer.string(authorization.governance_binding_event_id)
  writer.string(authorization.governance_binding_event_key)
  writer.string(authorization.command_idempotency_key)
  match trailing {
    None => ()
    Some(value) => writer.bytes(value)
  }
  writer.finish()
}

///|
fn phase1a_expect_r2_rejection(
  expected_ref : @contracts.RecordRef,
  e1 : @storage.WorkflowEvent,
  bytes : Bytes,
) -> Unit raise {
  try verify_retry_policy_binding_v22(expected_ref, e1, bytes) catch {
    MalformedInput(field=_)
    | DigestMismatch(field=_)
    | ReplayBindingViolation(field=_)
    | UnsupportedVersion(field=_, version=_) => ()
    _ => fail("expected strict R2 rejection")
  } noraise {
    _ => fail("expected strict R2 rejection")
  }
}

///|
test "FLOW-7 Phase1A R2 signing bytes are acyclic and strictly verified" {
  let fixture = phase1a_wb_initial()
  let authorization = fixture.authorization
  let workflow = fixture.registration.workflow()
  let registration_ref = fixture.registration.record_ref()
  let e1 = fixture.e1
  let bytes = phase1a_r2_signing_fixture(
    authorization.retry_binding_id,
    workflow,
    registration_ref,
    e1,
    authorization,
  )
  let expected_ref = self_ref_v22(
    "orchestration-committed-retry-policy-binding-v2",
    authorization.retry_binding_id,
    @contracts.sha256_digest(bytes),
  )
  let decoded = verify_retry_policy_binding_v22(expected_ref, e1, bytes)
  assert_true(decoded.record_ref() == expected_ref)
  assert_true(decoded.canonical_bytes() == bytes)

  phase1a_expect_r2_rejection(
    expected_ref,
    e1,
    phase1a_replace_occurrence(
      bytes, b"FLOW7/COMMITTED-RETRY-POLICY-BINDING-V2/2.2.0", 0, b'X',
    ),
  )
  phase1a_expect_r2_rejection(
    expected_ref,
    e1,
    phase1a_replace_occurrence(bytes, b"2.2.0", 1, b'9'),
  )
  let noncanonical_retry = phase1a_r2_signing_fixture(
    authorization.retry_binding_id,
    workflow,
    registration_ref,
    e1,
    authorization,
    retry_policy_bytes_override=authorization.retry_policy.canonical_bytes() +
      b"trailing",
  )
  phase1a_expect_r2_rejection(
    self_ref_v22(
      "orchestration-committed-retry-policy-binding-v2",
      authorization.retry_binding_id,
      @contracts.sha256_digest(noncanonical_retry),
    ),
    e1,
    noncanonical_retry,
  )

  phase1a_expect_r2_rejection(
    self_ref_v22(
      "orchestration-committed-retry-policy-binding-v2",
      "phase1a-r2-wrong",
      @contracts.sha256_digest(bytes),
    ),
    e1,
    bytes,
  )
  phase1a_expect_r2_rejection(
    expected_ref,
    e1,
    phase1a_r2_signing_fixture(
      authorization.retry_binding_id,
      workflow,
      registration_ref,
      e1,
      authorization,
      e1_digest_override=b"wrong-e1-digest",
    ),
  )
  let other_e1 = phase1a_event_v22(
    workflow,
    "phase1a-r2-other-e1",
    schedule_registered_event_kind_v2,
    registration_ref,
    fixture.registration.canonical_bytes(),
    [
      for value in fixture.registration.schedule().evidence() => value
    ],
    fixture.registration.schedule().causation_ref(),
    fixture.registration.schedule().idempotency_key(),
    1L,
    1L,
    None,
  )
  phase1a_expect_r2_rejection(expected_ref, other_e1, bytes)
  phase1a_expect_r2_rejection(
    expected_ref,
    e1,
    phase1a_r2_signing_fixture(
      authorization.retry_binding_id,
      workflow,
      registration_ref,
      e1,
      authorization,
      e1_bytes_override=b"wrong-e1-bytes",
    ),
  )
  // An embedded own ref/digest/bytes or carrying E2 encoding is trailing data
  // under the frozen R2 grammar and must be rejected.
  phase1a_expect_r2_rejection(
    expected_ref,
    e1,
    phase1a_r2_signing_fixture(
      authorization.retry_binding_id,
      workflow,
      registration_ref,
      e1,
      authorization,
      trailing=b"embedded-self-or-e2",
    ),
  )
  phase1a_expect_r2_rejection(
    expected_ref,
    e1,
    bytes[:bytes.length() - 1].to_owned(),
  )
  phase1a_expect_r2_rejection(expected_ref, e1, bytes + b"trailing")
}

///|
fn phase1a_r3_signing_fixture(
  binding_id : String,
  workflow : @contracts.RecordRef,
  registration_ref : @contracts.RecordRef,
  e1 : @storage.WorkflowEvent,
  r2 : CommittedRetryPolicyBindingV2,
  e2 : @storage.WorkflowEvent,
  e1_ref_override? : @contracts.RecordRef,
  e1_bytes_override? : Bytes,
  r2_ref_override? : @contracts.RecordRef,
  r2_bytes_override? : Bytes,
  e2_ref_override? : @contracts.RecordRef,
  e2_bytes_override? : Bytes,
  governance_policy_bytes_override? : Bytes,
  trailing? : Bytes,
) -> Bytes raise OrchestrationError {
  let authorization = decode_initial_work_authorization_v22(
    r2.initial_authorization_ref,
    r2.initial_authorization_bytes,
  )
  let policy_bytes = authorization.governance_policy.canonical_bytes()
  let policy_ref = authorization.governance_policy.policy_ref()
  let governance_stream = authorization.governance_stream_ref
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-CANCELLATION-GOVERNANCE-BINDING-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(binding_id)
  write_ref(writer, workflow)
  write_ref(writer, registration_ref)
  write_ref(writer, e1_ref_override.unwrap_or(e1.event_ref()))
  writer.bytes(e1_bytes_override.unwrap_or(e1.canonical_bytes()))
  write_ref(writer, r2_ref_override.unwrap_or(r2.record_ref()))
  writer.bytes(r2_bytes_override.unwrap_or(r2.canonical_bytes()))
  write_ref(writer, e2_ref_override.unwrap_or(e2.event_ref()))
  writer.bytes(e2_bytes_override.unwrap_or(e2.canonical_bytes()))
  write_ref(writer, governance_stream)
  write_ref(writer, policy_ref)
  writer.bytes(@utf8.encode(policy_ref.digest().text()))
  writer.bytes(governance_policy_bytes_override.unwrap_or(policy_bytes))
  writer.int64(authorization.governance_valid_until_inclusive)
  match trailing {
    None => ()
    Some(value) => writer.bytes(value)
  }
  writer.finish()
}

///|
fn phase1a_expect_r3_rejection(
  expected_ref : @contracts.RecordRef,
  e1 : @storage.WorkflowEvent,
  r2 : CommittedRetryPolicyBindingV2,
  e2 : @storage.WorkflowEvent,
  bytes : Bytes,
) -> Unit raise {
  try
    verify_cancellation_governance_binding_v22(expected_ref, e1, r2, e2, bytes)
  catch {
    MalformedInput(field=_)
    | DigestMismatch(field=_)
    | ReplayBindingViolation(field=_)
    | PolicyMismatch(field=_)
    | UnsupportedVersion(field=_, version=_) => ()
    _ => fail("expected strict R3 rejection")
  } noraise {
    _ => fail("expected strict R3 rejection")
  }
}

///|
fn phase1a_r3_ref(binding_id : String, bytes : Bytes) -> @contracts.RecordRef {
  self_ref_v22(
    "orchestration-committed-cancellation-governance-binding-v2",
    binding_id,
    @contracts.sha256_digest(bytes),
  )
}

///|
test "FLOW-7 Phase1A R3 binds exact E1 R2 E2 and excludes self and E3" {
  let fixture = phase1a_wb_initial()
  let authorization = fixture.authorization
  let workflow = fixture.registration.workflow()
  let registration_ref = fixture.registration.record_ref()
  let e1 = fixture.e1
  let r2 = fixture.r2
  let e2 = fixture.e2
  let bytes = phase1a_r3_signing_fixture(
    authorization.governance_binding_id,
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
  )
  let expected_ref = phase1a_r3_ref(authorization.governance_binding_id, bytes)
  let decoded = verify_cancellation_governance_binding_v22(
    expected_ref, e1, r2, e2, bytes,
  )
  assert_true(decoded.record_ref() == expected_ref)
  assert_true(decoded.canonical_bytes() == bytes)

  phase1a_expect_r3_rejection(
    expected_ref,
    e1,
    r2,
    e2,
    phase1a_replace_occurrence(
      bytes, b"FLOW7/COMMITTED-CANCELLATION-GOVERNANCE-BINDING-V2/2.2.0", 0, b'X',
    ),
  )
  phase1a_expect_r3_rejection(
    expected_ref,
    e1,
    r2,
    e2,
    phase1a_replace_occurrence(bytes, b"2.2.0", 1, b'9'),
  )

  phase1a_expect_r3_rejection(
    self_ref_v22(
      "orchestration-committed-cancellation-governance-binding-v2",
      "phase1a-r3-wrong",
      @contracts.sha256_digest(bytes),
    ),
    e1,
    r2,
    e2,
    bytes,
  )
  let other_e1 = phase1a_event_v22(
    workflow,
    "phase1a-r3-other-e1",
    schedule_registered_event_kind_v2,
    registration_ref,
    fixture.registration.canonical_bytes(),
    [
      for value in fixture.registration.schedule().evidence() => value
    ],
    fixture.registration.schedule().causation_ref(),
    fixture.registration.schedule().idempotency_key(),
    1L,
    1L,
    None,
  )
  phase1a_expect_r3_rejection(expected_ref, other_e1, r2, e2, bytes)
  let wrong_e1_ref_bytes = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    e1_ref_override=phase1a_wb_ref(
      "workflow-event", "phase1a-r3-wrong-e1-ref", b"wrong-e1-ref",
    ),
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", wrong_e1_ref_bytes),
    e1,
    r2,
    e2,
    wrong_e1_ref_bytes,
  )
  let wrong_e1_digest_bytes = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    e1_ref_override=phase1a_wb_ref(
      e1.event_ref().kind(),
      e1.event_ref().id(),
      b"wrong-e1-digest",
    ),
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", wrong_e1_digest_bytes),
    e1,
    r2,
    e2,
    wrong_e1_digest_bytes,
  )
  let wrong_e1_bytes = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    e1_bytes_override=b"wrong-e1-bytes",
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", wrong_e1_bytes),
    e1,
    r2,
    e2,
    wrong_e1_bytes,
  )
  let other_e2 = phase1a_event_v22(
    workflow,
    "phase1a-r3-other-e2",
    retry_policy_bound_event_kind_v22,
    r2.record_ref(),
    r2.canonical_bytes(),
    [],
    fixture.registration.schedule().causation_ref(),
    "phase1a-r3-other-e2-key",
    2L,
    2L,
    Some(e1.event_ref().digest()),
  )
  phase1a_expect_r3_rejection(expected_ref, e1, r2, other_e2, bytes)
  let wrong_r2_ref_bytes = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    r2_ref_override=phase1a_wb_ref(
      "orchestration-committed-retry-policy-binding-v2", "phase1a-r3-wrong-r2-ref",
      b"wrong-r2-ref",
    ),
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", wrong_r2_ref_bytes),
    e1,
    r2,
    e2,
    wrong_r2_ref_bytes,
  )
  let wrong_r2_digest_bytes = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    r2_ref_override=phase1a_wb_ref(
      r2.record_ref().kind(),
      r2.record_ref().id(),
      b"wrong-r2-digest",
    ),
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", wrong_r2_digest_bytes),
    e1,
    r2,
    e2,
    wrong_r2_digest_bytes,
  )
  let wrong_r2_bytes = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    r2_bytes_override=b"wrong-r2-bytes",
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", wrong_r2_bytes),
    e1,
    r2,
    e2,
    wrong_r2_bytes,
  )
  let wrong_e2_ref_bytes = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    e2_ref_override=phase1a_wb_ref(
      "workflow-event", "phase1a-r3-wrong-e2-ref", b"wrong-e2-ref",
    ),
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", wrong_e2_ref_bytes),
    e1,
    r2,
    e2,
    wrong_e2_ref_bytes,
  )
  let wrong_e2_digest_bytes = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    e2_ref_override=phase1a_wb_ref(
      e2.event_ref().kind(),
      e2.event_ref().id(),
      b"wrong-e2-digest",
    ),
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", wrong_e2_digest_bytes),
    e1,
    r2,
    e2,
    wrong_e2_digest_bytes,
  )
  let wrong_e2_bytes = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    e2_bytes_override=b"wrong-e2-bytes",
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", wrong_e2_bytes),
    e1,
    r2,
    e2,
    wrong_e2_bytes,
  )
  let own_ref_injection = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    trailing=b"embedded-own-ref",
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", own_ref_injection),
    e1,
    r2,
    e2,
    own_ref_injection,
  )
  let own_digest_injection = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    trailing=b"embedded-own-digest",
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", own_digest_injection),
    e1,
    r2,
    e2,
    own_digest_injection,
  )
  let own_bytes_injection = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    trailing=b"embedded-own-bytes",
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", own_bytes_injection),
    e1,
    r2,
    e2,
    own_bytes_injection,
  )
  let e3_injection = phase1a_r3_signing_fixture(
    "phase1a-r3-binding",
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    trailing=b"embedded-e3",
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", e3_injection),
    e1,
    r2,
    e2,
    e3_injection,
  )
  let noncanonical_policy = phase1a_r3_signing_fixture(
    authorization.governance_binding_id,
    workflow,
    registration_ref,
    e1,
    r2,
    e2,
    governance_policy_bytes_override=authorization.governance_policy.canonical_bytes() +
      b"trailing",
  )
  phase1a_expect_r3_rejection(
    phase1a_r3_ref(authorization.governance_binding_id, noncanonical_policy),
    e1,
    r2,
    e2,
    noncanonical_policy,
  )
  let truncated = bytes[:bytes.length() - 1].to_owned()
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", truncated),
    e1,
    r2,
    e2,
    truncated,
  )
  let noncanonical_trailing = bytes + b"trailing"
  phase1a_expect_r3_rejection(
    phase1a_r3_ref("phase1a-r3-binding", noncanonical_trailing),
    e1,
    r2,
    e2,
    noncanonical_trailing,
  )
}

///|
test "FLOW-7 Phase1A internal terminal scaffold preserves exact six outcomes" {
  let workflow = phase1a_wb_ref("workflow", "phase1a-terminal", b"workflow")
  let registration = phase1a_wb_ref(
    "orchestration-schedule-registered-v2", "phase1a-terminal-registration", b"registration",
  )
  let causation = phase1a_wb_ref("causation", "phase1a-terminal", b"cause")
  let outcomes = [
    WorkTerminalOutcomeV2::SucceededV2,
    WorkTerminalOutcomeV2::FailedNonRetryableV2,
    WorkTerminalOutcomeV2::FailedRetryExhaustedV2,
    WorkTerminalOutcomeV2::FailedCancellationStoppedRetryV2,
    WorkTerminalOutcomeV2::CancelledBeforeEffectIntentV2,
    WorkTerminalOutcomeV2::CancelledAfterReconciledNotAppliedV2,
  ]
  for index, outcome in outcomes {
    let terminal = new_work_terminal_foundation_v22(
      "phase1a-terminal-{index}",
      workflow,
      registration,
      outcome,
      index.to_int64(),
      [],
      causation,
      "phase1a-terminal-key-{index}",
    )
    let decoded = decode_work_terminal_v22(
      terminal.terminal_ref(),
      terminal.canonical_bytes(),
    )
    assert_true(decoded.outcome() == outcome)
  }
}
