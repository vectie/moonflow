///|
fn flow7_v2_retry_policy() -> RetryPolicyV2 raise OrchestrationError {
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
fn flow7_committed_retry_receipt(
  suffix : String,
  reconciled : Bool,
) -> @effects.CommittedRetryEligibilityReceiptV2 raise {
  let fixture = orchestration_fixture("v2-retry-" + suffix)
  let observation = @effects.DispatchObservation::new(
    "v2-retry-observation-" + suffix,
    fixture.intent,
    fixture_envelope(
      "v2-retry-observation-envelope-" + suffix,
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      b"opaque-observation",
    ),
    71L,
    [],
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_dispatch_observation_commit(
        fixture.effects,
        "v2-retry-observation-event-" + suffix,
        "v2-retry-observation-command-" + suffix,
        observation,
      ),
    ),
  )
  let pending = @effects.fold_authoritative_replay(
    @effects.EffectsProjection::new(
      fixture.workflow,
      fixture.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.workflow),
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [],
      [],
      [],
    ),
  )
  let outcome = if reconciled { @effects.Unknown } else { Failed }
  let effect_receipt = @effects.EffectReceipt::new(
    "v2-retry-effect-receipt-" + suffix,
    "1.0.0",
    fixture.intent,
    fixture_envelope(
      "v2-retry-effect-receipt-envelope-" + suffix,
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      b"opaque-receipt",
    ),
    outcome,
    72L,
    [],
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_effect_receipt_commit(
        pending,
        "v2-retry-effect-receipt-event-" + suffix,
        "v2-retry-effect-receipt-command-" + suffix,
        effect_receipt,
      ),
    ),
  )
  let terminal = @effects.fold_authoritative_replay(
    @effects.EffectsProjection::new(
      fixture.workflow,
      fixture.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.workflow),
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [effect_receipt],
      [],
      [],
    ),
  )
  let final_projection = if !reconciled {
    terminal
  } else {
    let request = @effects.ReconciliationRequest::new(
      "v2-retry-request-" + suffix,
      fixture.intent,
      effect_receipt,
      73L,
      [],
    )
    ignore(
      fixture.store.commit(
        fixture_prepare_reconciliation_request_commit(
          terminal,
          "v2-retry-request-event-" + suffix,
          "v2-retry-request-command-" + suffix,
          request,
        ),
      ),
    )
    let requested = @effects.fold_authoritative_replay(
      @effects.EffectsProjection::new(
        fixture.workflow,
        fixture.policy.policy_ref(),
      ),
      fixture.store.replay(fixture.workflow),
      @effects.ReplayCatalog::new(
        [fixture.attempt],
        [fixture.intent],
        [observation],
        [effect_receipt],
        [request],
        [],
      ),
    )
    let resolution = @effects.ReconciliationRecord::new(
      "v2-retry-resolution-" + suffix,
      fixture.intent,
      request,
      ReconciledNotApplied,
      fixture_envelope(
        "v2-retry-resolution-envelope-" + suffix,
        "reconciliation-observation",
        fixture.intent.governance().governed_subject(),
        b"not-applied",
      ),
      74L,
      [],
    )
    ignore(
      fixture.store.commit(
        fixture_prepare_reconciliation_resolution_commit(
          requested,
          "v2-retry-resolution-event-" + suffix,
          "v2-retry-resolution-command-" + suffix,
          resolution,
        ),
      ),
    )
    @effects.fold_authoritative_replay(
      @effects.EffectsProjection::new(
        fixture.workflow,
        fixture.policy.policy_ref(),
      ),
      fixture.store.replay(fixture.workflow),
      @effects.ReplayCatalog::new(
        [fixture.attempt],
        [fixture.intent],
        [observation],
        [effect_receipt],
        [request],
        [resolution],
      ),
    )
  }
  ignore(final_projection)
  let strict_final_projection = @effects.fold_committed_effects_bytes(
    @effects.EffectsProjection::new(
      fixture.workflow,
      fixture.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.workflow),
  )
  guard strict_final_projection.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is Some(receipt) else {
    fail("expected replay-minted retry receipt")
  }
  receipt
}

///|
test "orchestration v2 retry policy strict codec and closed causes" {
  let policy = flow7_v2_retry_policy()
  let decoded = RetryPolicyV2::decode(
    policy.policy_ref().id(),
    policy.canonical_bytes(),
  )
  assert_true(decoded.canonical_bytes() == policy.canonical_bytes())
  assert_true(decoded.digest() == policy.digest())
  assert_true(decoded.policy_ref() == policy.policy_ref())
  assert_true(decoded.maximum_attempt_count() == policy.maximum_attempt_count())
  assert_true(decoded.maximum_retry_count() == policy.maximum_retry_count())
  try
    RetryPolicyV2::new(
      "unsupported-retry-policy",
      "2.0.0",
      5L,
      4L,
      10L,
      1000L,
      2L,
      1L,
      0L,
      @contracts.sha256_digest(b"unsupported-retry-policy"),
      ["transient"],
    )
  catch {
    RetryClassificationViolation(field="unsupported_failure_class") => ()
    _ => fail("expected exact unsupported retry class rejection")
  } noraise {
    _ => fail("expected unsupported retry class rejection")
  }
}

///|
test "orchestration v2 retry policy strict decoder rejects malformed identity" {
  let policy = flow7_v2_retry_policy()
  try
    RetryPolicyV2::decode("wrong-retry-policy-v2-id", policy.canonical_bytes())
  catch {
    IdentityMismatch(field="retry_policy_v2_id") => ()
    _ => fail("expected exact retry policy identity rejection")
  } noraise {
    _ => fail("expected retry policy identity rejection")
  }
  let bytes = policy.canonical_bytes()
  try
    RetryPolicyV2::decode(
      policy.policy_ref().id(),
      flow7_v2_proper_prefix(bytes, bytes.length() - 1),
    )
  catch {
    MalformedInput(field=_) => ()
    _ => fail("expected truncated retry policy rejection")
  } noraise {
    _ => fail("expected truncated retry policy rejection")
  }
  try RetryPolicyV2::decode(policy.policy_ref().id(), bytes + b"x") catch {
    MalformedInput(field="trailing_bytes") => ()
    _ => fail("expected trailing retry policy rejection")
  } noraise {
    _ => fail("expected trailing retry policy rejection")
  }
}

///|
test "orchestration v2 retry timing consumes only committed receipt" {
  let policy = flow7_v2_retry_policy()
  let failed = flow7_committed_retry_receipt("failed", false)
  let reconciled = flow7_committed_retry_receipt("reconciled", true)
  let first = RetryTimingV2::compute(policy, failed)
  let same = RetryTimingV2::compute(policy, failed)
  let other = RetryTimingV2::compute(policy, reconciled)
  assert_true(first.canonical_bytes() == same.canonical_bytes())
  assert_true(first.digest() == same.digest())
  assert_true(first.digest() != other.digest())
  assert_eq(first.retry_ordinal(), failed.retry_ordinal())
  assert_true(
    @contracts.sha256_digest(first.canonical_bytes()) == first.digest(),
  )
  let due = first.due_at()
  assert_true(first.authorized_at(due, Some(due)))
  assert_true(!first.authorized_at(due + 1L, Some(due)))
  assert_true(!first.authorized_at(due, Some(due - 1L)))
}

///|
test "orchestration v2 retry policy disallows unconfigured committed cause" {
  let failed = flow7_committed_retry_receipt("disallowed", false)
  let policy = RetryPolicyV2::new(
    "reconciled-only-policy",
    "2.0.0",
    5L,
    4L,
    10L,
    1000L,
    2L,
    1L,
    0L,
    @contracts.sha256_digest(b"reconciled-only-policy"),
    ["reconciled_not_applied"],
  )
  assert_false(policy.allows(failed))
  try RetryTimingV2::compute(policy, failed) catch {
    RetryClassificationViolation(field="retry_eligibility") => ()
    _ => fail("expected exact unconfigured committed cause rejection")
  } noraise {
    _ => fail("expected unconfigured committed cause rejection")
  }
}

///|
fn flow7_v2_ref(
  kind : String,
  id : String,
  seed : Bytes,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    @contracts.sha256_digest(seed).text(),
  )
}

///|
fn flow7_v2_position() -> @effects_authorization.ReplayPosition raise OrchestrationError {
  let workflow = flow7_v2_ref(
    "workflow", "proof-v2-workflow", b"proof-v2-workflow",
  )
  orchestration_genesis_position_v2(workflow)
}

///|
fn flow7_v2_producer() -> @effects_authorization.ProducerDescriptor {
  let record = flow7_v2_ref(
    "producer", "proof-v2-producer", b"proof-v2-producer",
  )
  @effects_authorization.ProducerDescriptor::new(
    "fixture.producer",
    "1.0.0",
    record,
    record.digest(),
  ).unwrap()
}

///|
fn flow7_v2_governance_policy() -> @governance.GovernancePolicy {
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
fn flow7_v2_governance() -> @effects_authorization.AuthorizationGovernanceBinding {
  let decision = flow7_v2_ref(
    "decision", "proof-v2-decision", b"proof-v2-decision",
  )
  let policy = flow7_v2_governance_policy().policy_ref()
  let subject = flow7_v2_ref("subject", "proof-v2-subject", b"proof-v2-subject")
  @effects_authorization.AuthorizationGovernanceBinding::new(
    decision,
    decision.digest(),
    policy,
    policy.digest(),
    subject,
    10L,
    20L,
  ).unwrap()
}

///|
fn flow7_v2_planned() -> @effects_authorization.PlannedEffectTuple {
  let subject = flow7_v2_ref("subject", "proof-v2-subject", b"proof-v2-subject")
  let workflow = flow7_v2_ref(
    "workflow", "proof-v2-workflow", b"proof-v2-workflow",
  )
  let requested = flow7_v2_ref(
    "requested-work", "proof-v2-requested", b"proof-v2-requested",
  )
  let effect = flow7_v2_ref(
    "effect-request", "proof-v2-effect", b"proof-v2-effect",
  )
  @effects_authorization.PlannedEffectTuple::new(
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
}

///|
fn flow7_v2_controls(
  include_capability? : Bool = true,
  include_evidence? : Bool = true,
) -> @effects_authorization.AuthorizationControls {
  let evidence_ref = flow7_v2_ref(
    "evidence", "proof-v2-evidence", b"proof-v2-evidence",
  )
  let evidence = @effects_authorization.EvidenceBinding::new(
    evidence_ref,
    evidence_ref.digest(),
  ).unwrap()
  let capability_ref = flow7_v2_ref(
    "capability", "proof-v2-capability", b"proof-v2-capability",
  )
  let capability = @effects_authorization.CapabilityBinding::new(
    capability_ref,
    capability_ref.digest(),
  ).unwrap()
  let fencing_ref = flow7_v2_ref(
    "fencing", "proof-v2-fencing", b"proof-v2-fencing",
  )
  let fencing = @effects_authorization.FencingBinding::new(fencing_ref, 1L, 1L).unwrap()
  @effects_authorization.AuthorizationControls::new(
    if include_capability {
      Some(capability)
    } else {
      None
    },
    if include_evidence {
      [evidence]
    } else {
      []
    },
    Some(fencing),
    Some(10L),
    20L,
  ).unwrap()
}

///|
struct Flow7V2AdmissionFixture {
  proof : @effects_authorization.EligibleAuthorizationProofV2
  admission : AdmissionV2
}

///|
fn flow7_v2_envelope(
  event_id : String,
  kind : @effects_authorization.AuthorizationEventKindV2,
  record_ref : @contracts.RecordRef,
  payload : Bytes,
  position : Int64,
  previous : @contracts.ContentDigest,
) -> @effects_authorization.AuthorizationEventEnvelopeV2 {
  @effects_authorization.AuthorizationEventEnvelopeV2::new(
    event_id,
    kind,
    @effects_authorization.contract_version,
    "FLOW-6C.authorization-event-envelope.v2",
    record_ref,
    record_ref.digest(),
    position,
    position,
    previous,
    previous,
    payload,
  ).unwrap()
}

///|
fn flow7_v2_admission(
  include_capability? : Bool = true,
  include_evidence? : Bool = true,
) -> Flow7V2AdmissionFixture raise OrchestrationError {
  let authorization = @effects_authorization.PreDispatchAuthorization::new(
    "proof-v2-authorization",
    flow7_v2_producer(),
    flow7_v2_governance(),
    @effects_authorization.EligibilityBinding::new(10L, flow7_v2_position()).unwrap(),
    flow7_v2_planned(),
    flow7_v2_controls(include_capability~, include_evidence~),
  ).unwrap()
  let e0 = flow7_v2_envelope(
    "flow7-v2-authorization-event",
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
    "proof-v2-attempt",
    auth_link,
    authorization.producer(),
    authorization.governance(),
    authorization.eligibility(),
    authorization.planned(),
    authorization.controls(),
  ).unwrap()
  let e1 = flow7_v2_envelope(
    "flow7-v2-attempt-event",
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
    "proof-v2-intent",
    auth_link,
    attempt_link,
    authorization.producer(),
    authorization.governance(),
    authorization.eligibility(),
    authorization.planned(),
    authorization.controls(),
  ).unwrap()
  let e2 = flow7_v2_envelope(
    "flow7-v2-intent-event",
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
    store, "flow7-v2-proof", "flow7-v2-proof-event",
  ).unwrap()
  let proof = commit.proof()
  let admission = AdmissionV2::decode("flow7-v2-proof", proof.canonical_bytes())
  { proof, admission }
}

///|
fn flow7_v2_evidence() -> @contracts.EvidenceRef {
  let record = flow7_v2_ref(
    "evidence", "proof-v2-evidence", b"proof-v2-evidence",
  )
  let provenance = flow7_v2_ref(
    "provenance", "proof-v2-provenance", b"proof-v2-provenance",
  )
  try! @contracts.EvidenceRef::new(record, provenance, record.digest().text())
}

///|
fn flow7_v2_schedule_intent(
  admission : AdmissionV2,
  evidence : @contracts.EvidenceRef,
) -> ScheduleIntentV2 raise OrchestrationError {
  ScheduleIntentV2::new(
    "flow7-v2-schedule",
    "2.0.0",
    admission,
    admission.planned().workflow(),
    10L,
    Some(20L),
    [evidence],
    flow7_v2_ref("causation", "flow7-v2-schedule", b"flow7-v2-schedule"),
    "flow7-v2-schedule-idempotency",
  )
}

///|
test "FLOW-7 V2 rejects V1 schedule version" {
  let fixture = flow7_v2_admission()
  let evidence = flow7_v2_evidence()
  try
    ScheduleIntentV2::new(
      "flow7-v1-schedule-rejected",
      "1.0.0",
      fixture.admission,
      fixture.admission.planned().workflow(),
      10L,
      Some(20L),
      [evidence],
      flow7_v2_ref(
        "causation", "flow7-v1-schedule-rejected", b"flow7-v1-schedule-rejected",
      ),
      "flow7-v1-schedule-rejected-idempotency",
    )
  catch {
    UnsupportedVersion(field="schedule_intent_v2", version="1.0.0") => ()
    _ => fail("expected V1 schedule version to be rejected")
  } noraise {
    _ => fail("expected V1 schedule version to be rejected")
  }
}

///|
test "FLOW-7 V2 valid lease claim" {
  let fixture = flow7_v2_admission()
  let lease_evidence = flow7_v2_evidence()
  let schedule = flow7_v2_schedule_intent(fixture.admission, lease_evidence)
  let evidence : Array[@contracts.EvidenceRef] = [lease_evidence]
  let owner = flow7_v2_ref("owner", "flow7-v2-owner", b"flow7-v2-owner")
  let causation = flow7_v2_ref(
    "causation", "flow7-v2-lease-claim", b"flow7-v2-lease-claim",
  )
  let first = LeaseClaimV2::new(
    "flow7-v2-lease-claim",
    schedule,
    fixture.admission,
    fixture.admission.planned().workflow(),
    owner,
    10L,
    0L,
    0L,
    1L,
    1L,
    "flow7-v2-lease-idempotency",
    evidence,
    causation,
  )
  let same = LeaseClaimV2::new(
    "flow7-v2-lease-claim",
    schedule,
    fixture.admission,
    fixture.admission.planned().workflow(),
    owner,
    10L,
    0L,
    0L,
    1L,
    1L,
    "flow7-v2-lease-idempotency",
    evidence,
    causation,
  )
  assert_true(first.canonical_bytes() == same.canonical_bytes())
  assert_true(first.digest() == same.digest())
  assert_true(
    @contracts.sha256_digest(first.canonical_bytes()) == first.digest(),
  )
  assert_true(first.state_ref().digest() == first.digest())
  assert_true(first.state_ref().version().text() == "2.0.0")
  assert_true(first.schedule_ref() == schedule.schedule_ref())
  assert_true(first.schedule_digest() == schedule.digest())
  assert_true(first.admission_ref() == fixture.admission.proof_ref())
  assert_true(first.admission_digest() == fixture.admission.proof_digest())
  assert_true(first.intent_ref() == fixture.admission.intent_ref())
  assert_true(first.intent_digest() == fixture.admission.intent_digest())
  assert_true(first.workflow() == fixture.admission.planned().workflow())
  assert_true(first.owner() == owner)
  assert_eq(first.observed_at(), 10L)
  assert_eq(first.expires_at(), 20L)
  assert_eq(first.epoch(), 1L)
  assert_eq(first.fencing_token(), 1L)
  assert_true(first.evidence().length() == 1)
  let snapshot = first.canonical_bytes()
  evidence.push(flow7_v2_evidence())
  assert_true(first.evidence().length() == 1)
  assert_true(first.canonical_bytes() == snapshot)
}

///|
fn flow7_v2_replace_byte(
  bytes : Bytes,
  index : Int,
  replacement : Byte,
) -> Bytes {
  let copied : Array[Byte] = []
  for byte in bytes {
    copied.push(byte)
  }
  copied[index] = replacement
  Bytes::from_array(copied)
}

///|
fn flow7_v2_proper_prefix(bytes : Bytes, length : Int) -> Bytes {
  let copied : Array[Byte] = []
  for index = 0; index < length; index = index + 1 {
    copied.push(bytes[index])
  }
  Bytes::from_array(copied)
}

///|
test "FLOW-7 V2 valid admission" {
  let fixture = flow7_v2_admission()
  let admission = fixture.admission
  let proof = fixture.proof
  assert_true(admission.proof_ref() == proof.record_ref())
  assert_true(admission.proof_digest() == proof.digest())
  assert_true(admission.authorization() == proof.authorization())
  assert_true(admission.attempt() == proof.attempt())
  assert_true(admission.intent_ref() == proof.intent_ref())
  assert_true(admission.intent_digest() == proof.intent_digest())
  assert_true(admission.planned() == proof.planned())
  assert_true(admission.governance() == proof.governance())
  assert_true(admission.controls() == proof.controls())
  assert_true(admission.governance().accepts(10L))
  assert_true(admission.governance().accepts(20L))
  assert_false(admission.governance().accepts(21L))
  assert_true(admission.controls().accepts(10L))
  assert_true(admission.controls().accepts(20L))
  assert_false(admission.controls().accepts(21L))
  assert_true(
    @contracts.sha256_digest(admission.canonical_bytes()) == admission.digest(),
  )
}

///|
test "FLOW-7 V2 rejects wrong proof id" {
  let fixture = flow7_v2_admission()
  try
    AdmissionV2::decode("wrong-proof-id", fixture.proof.canonical_bytes())
  catch {
    MalformedInput(field="eligible_authorization_proof_v2") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected malformed input")
  }
}

///|
test "FLOW-7 V2 rejects non-V2 bytes" {
  let fixture = flow7_v2_admission()
  try
    AdmissionV2::decode(fixture.proof.record_ref().id(), b"not-a-v2-proof")
  catch {
    MalformedInput(field="eligible_authorization_proof_v2") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected malformed input")
  }
}

///|
test "FLOW-7 V2 rejects tampered proof" {
  let fixture = flow7_v2_admission()
  let bytes = fixture.proof.canonical_bytes()
  let last = bytes.length() - 1
  let replacement : Byte = if bytes[last] == 0 { 1 } else { 0 }
  let tampered = flow7_v2_replace_byte(bytes, last, replacement)
  try AdmissionV2::decode(fixture.proof.record_ref().id(), tampered) catch {
    MalformedInput(field="eligible_authorization_proof_v2") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected malformed input")
  }
}

///|
test "FLOW-7 V2 rejects truncated proof" {
  let fixture = flow7_v2_admission()
  let bytes = fixture.proof.canonical_bytes()
  let truncated = flow7_v2_proper_prefix(bytes, bytes.length() - 1)
  try AdmissionV2::decode(fixture.proof.record_ref().id(), truncated) catch {
    MalformedInput(field="eligible_authorization_proof_v2") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected malformed input")
  }
}
