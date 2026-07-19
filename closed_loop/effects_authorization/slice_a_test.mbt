///|
fn slice_a_ref(
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
fn slice_a_wrong_digest() -> @contracts.ContentDigest {
  @contracts.sha256_digest(b"FLOW-6C-wrong-digest")
}

///|
fn slice_a_head() -> ReplayPosition {
  let event = slice_a_ref("event", "event-fixture", b"event-fixture")
  ReplayPosition::new(event, 7L, 3L, event.digest()).unwrap()
}

///|
fn slice_a_producer() -> ProducerDescriptor {
  let record = slice_a_ref("producer", "producer-fixture", b"producer-fixture")
  ProducerDescriptor::new("fixture.producer", "1.0.0", record, record.digest()).unwrap()
}

///|
fn slice_a_governance() -> AuthorizationGovernanceBinding {
  let decision = slice_a_ref(
    "decision", "decision-fixture", b"decision-fixture",
  )
  let policy = slice_a_ref("policy", "policy-fixture", b"policy-fixture")
  let subject = slice_a_ref("subject", "subject-fixture", b"subject-fixture")
  AuthorizationGovernanceBinding::new(
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
fn slice_a_planned(
  subject? : @contracts.RecordRef = slice_a_ref(
    "subject", "subject-fixture", b"subject-fixture",
  ),
) -> PlannedEffectTuple {
  let workflow = slice_a_ref(
    "workflow", "workflow-fixture", b"workflow-fixture",
  )
  let requested = slice_a_ref(
    "requested-work", "requested-fixture", b"requested-fixture",
  )
  let effect = slice_a_ref(
    "effect-request", "effect-fixture", b"effect-fixture",
  )
  PlannedEffectTuple::new(
    workflow,
    subject,
    "attempt",
    "1",
    "effect",
    "1",
    1L,
    "idempotency",
    requested,
    requested.digest(),
    effect,
    effect.digest(),
    @contracts.sha256_digest(b"artifact-fixture"),
  ).unwrap()
}

///|
fn slice_a_evidence(id : String) -> EvidenceBinding {
  let evidence = slice_a_ref("evidence", id, id.to_bytes())
  EvidenceBinding::new(evidence, evidence.digest()).unwrap()
}

///|
fn slice_a_capability() -> CapabilityBinding {
  let capability = slice_a_ref(
    "capability", "capability-fixture", b"capability-fixture",
  )
  CapabilityBinding::new(capability, capability.digest()).unwrap()
}

///|
fn slice_a_fencing() -> FencingBinding {
  let fencing = slice_a_ref("fencing", "fencing-fixture", b"fencing-fixture")
  FencingBinding::new(fencing, 1L, 1L).unwrap()
}

///|
fn slice_a_controls(
  evidence? : Array[EvidenceBinding] = [],
) -> AuthorizationControls {
  AuthorizationControls::new(
    Some(slice_a_capability()),
    evidence,
    Some(slice_a_fencing()),
    Some(10L),
    20L,
  ).unwrap()
}

///|
fn slice_a_eligibility(clock? : Int64 = 10L) -> EligibilityBinding {
  EligibilityBinding::new(clock, slice_a_head()).unwrap()
}

///|
fn slice_a_authorization(
  id? : String = "authorization-fixture",
  eligibility? : EligibilityBinding = slice_a_eligibility(),
  planned? : PlannedEffectTuple = slice_a_planned(),
) -> PreDispatchAuthorization {
  PreDispatchAuthorization::new(
    id,
    slice_a_producer(),
    slice_a_governance(),
    eligibility,
    planned,
    slice_a_controls(evidence=[slice_a_evidence("evidence-fixture")]),
  ).unwrap()
}

///|
fn slice_a_replace_byte(
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
fn slice_a_authorization_link() -> AuthorizationLink {
  let authorization = slice_a_authorization()
  let commit_ref = slice_a_ref(
    "commit-event", "commit-event-fixture", b"commit-event-fixture",
  )
  let position = ReplayPosition::new(commit_ref, 8L, 4L, commit_ref.digest()).unwrap()
  AuthorizationLink::new(
    authorization.record_ref(),
    authorization.record_digest(),
    position,
  ).unwrap()
}

///|
fn slice_a_attempt(
  id? : String = "attempt-fixture",
) -> AuthorizedAttemptRegistration {
  AuthorizedAttemptRegistration::new(
    id,
    slice_a_authorization_link(),
    slice_a_producer(),
    slice_a_governance(),
    slice_a_eligibility(),
    slice_a_planned(),
    slice_a_controls(evidence=[slice_a_evidence("evidence-fixture")]),
  ).unwrap()
}

///|
fn slice_a_attempt_link() -> AttemptLink {
  let attempt = slice_a_attempt()
  let commit_ref = slice_a_ref(
    "commit-event", "attempt-commit-event-fixture", b"attempt-commit-event-fixture",
  )
  let position = ReplayPosition::new(commit_ref, 9L, 5L, commit_ref.digest()).unwrap()
  AttemptLink::new(attempt.record_ref(), attempt.record_digest(), position).unwrap()
}

///|
fn slice_a_intent(id? : String = "intent-fixture") -> AuthorizedEffectIntent {
  AuthorizedEffectIntent::new(
    id,
    slice_a_authorization_link(),
    slice_a_attempt_link(),
    slice_a_producer(),
    slice_a_governance(),
    slice_a_eligibility(),
    slice_a_planned(),
    slice_a_controls(evidence=[slice_a_evidence("evidence-fixture")]),
  ).unwrap()
}

///|
test "FLOW-6C Slice A public decoders fail closed" {
  let authorization_bytes = slice_a_authorization(id="authorization-fixture").canonical_bytes()
  assert_true(
    decode_pre_dispatch_authorization("authorization-fixture", b"") is Err(_),
  )
  assert_true(
    decode_pre_dispatch_authorization(
      "authorization-fixture",
      authorization_bytes + b"x",
    )
    is Err(_),
  )
  assert_true(
    decode_pre_dispatch_authorization(
      "authorization-fixture",
      slice_a_replace_byte(authorization_bytes, 4, b'X'),
    )
    is Err(_),
  )
  for length = 0; length < authorization_bytes.length(); length = length + 1 {
    assert_true(
      decode_pre_dispatch_authorization(
        "authorization-fixture",
        authorization_bytes[0:length].to_owned(),
      )
      is Err(_),
    )
  }
  assert_true(
    decode_pre_dispatch_authorization(
      "authorization-fixture", authorization_bytes,
    )
    is Ok(_),
  )

  let attempt_bytes = slice_a_attempt(id="attempt-fixture").canonical_bytes()
  assert_true(
    decode_authorized_attempt_registration("attempt-fixture", b"") is Err(_),
  )
  assert_true(
    decode_authorized_attempt_registration(
      "attempt-fixture",
      attempt_bytes + b"x",
    )
    is Err(_),
  )
  assert_true(
    decode_authorized_attempt_registration(
      "attempt-fixture",
      slice_a_replace_byte(attempt_bytes, 4, b'X'),
    )
    is Err(_),
  )
  for length = 0; length < attempt_bytes.length(); length = length + 1 {
    assert_true(
      decode_authorized_attempt_registration(
        "attempt-fixture",
        attempt_bytes[0:length].to_owned(),
      )
      is Err(_),
    )
  }
  assert_true(
    decode_authorized_attempt_registration("attempt-fixture", attempt_bytes)
    is Ok(_),
  )

  let intent_bytes = slice_a_intent(id="intent-fixture").canonical_bytes()
  assert_true(decode_authorized_effect_intent("intent-fixture", b"") is Err(_))
  assert_true(
    decode_authorized_effect_intent("intent-fixture", intent_bytes + b"x")
    is Err(_),
  )
  assert_true(
    decode_authorized_effect_intent(
      "intent-fixture",
      slice_a_replace_byte(intent_bytes, 4, b'X'),
    )
    is Err(_),
  )
  for length = 0; length < intent_bytes.length(); length = length + 1 {
    assert_true(
      decode_authorized_effect_intent(
        "intent-fixture",
        intent_bytes[0:length].to_owned(),
      )
      is Err(_),
    )
  }
  assert_true(
    decode_authorized_effect_intent("intent-fixture", intent_bytes) is Ok(_),
  )
}

///|
test "FLOW-6C attempt link validates digest" {
  let attempt = slice_a_attempt()
  let commit_ref = slice_a_ref(
    "commit-event", "attempt-commit-event-fixture", b"attempt-commit-event-fixture",
  )
  let position = ReplayPosition::new(commit_ref, 9L, 5L, commit_ref.digest()).unwrap()
  assert_true(
    AttemptLink::new(attempt.record_ref(), slice_a_wrong_digest(), position)
    is Err(_),
  )
}

///|
test "FLOW-6C attempt and intent reject blank ids" {
  assert_true(
    AuthorizedAttemptRegistration::new(
      "",
      slice_a_authorization_link(),
      slice_a_producer(),
      slice_a_governance(),
      slice_a_eligibility(),
      slice_a_planned(),
      slice_a_controls(evidence=[slice_a_evidence("evidence-fixture")]),
    )
    is Err(_),
  )
  assert_true(
    AuthorizedEffectIntent::new(
      "",
      slice_a_authorization_link(),
      slice_a_attempt_link(),
      slice_a_producer(),
      slice_a_governance(),
      slice_a_eligibility(),
      slice_a_planned(),
      slice_a_controls(evidence=[slice_a_evidence("evidence-fixture")]),
    )
    is Err(_),
  )
}

///|
test "FLOW-6C attempt and intent are canonical" {
  let attempt = slice_a_attempt()
  let same_attempt = slice_a_attempt()
  assert_true(attempt.canonical_bytes() == same_attempt.canonical_bytes())
  assert_true(attempt.record_digest() == same_attempt.record_digest())
  assert_true(attempt.record_ref() == same_attempt.record_ref())
  let intent = slice_a_intent()
  let same_intent = slice_a_intent()
  assert_true(intent.canonical_bytes() == same_intent.canonical_bytes())
  assert_true(intent.record_digest() == same_intent.record_digest())
  assert_true(intent.record_ref() == same_intent.record_ref())
}

///|
test "FLOW-6C attempt and intent round trip" {
  let attempt = slice_a_attempt()
  let decoded_attempt = decode_authorized_attempt_registration(
    "attempt-fixture",
    attempt.canonical_bytes(),
  ).unwrap()
  assert_true(decoded_attempt == attempt)
  assert_true(decoded_attempt.canonical_bytes() == attempt.canonical_bytes())
  assert_eq(decoded_attempt.authorization().committed_position().sequence(), 8L)
  assert_true(decoded_attempt.controls().capability() is Some(_))
  assert_true(decoded_attempt.controls().fencing() is Some(_))
  assert_eq(decoded_attempt.controls().evidence().length(), 1)
  let intent = slice_a_intent()
  let decoded_intent = decode_authorized_effect_intent(
    "intent-fixture",
    intent.canonical_bytes(),
  ).unwrap()
  assert_true(decoded_intent == intent)
  assert_true(decoded_intent.canonical_bytes() == intent.canonical_bytes())
  assert_eq(decoded_intent.authorization().committed_position().sequence(), 8L)
  assert_eq(decoded_intent.attempt().committed_position().sequence(), 9L)
  assert_true(decoded_intent.controls().capability() is Some(_))
  assert_true(decoded_intent.controls().fencing() is Some(_))
  assert_eq(decoded_intent.controls().evidence().length(), 1)
}

///|
test "FLOW-6C pre-dispatch authorization validation" {
  assert_true(
    PreDispatchAuthorization::new(
      "",
      slice_a_producer(),
      slice_a_governance(),
      slice_a_eligibility(),
      slice_a_planned(),
      slice_a_controls(evidence=[slice_a_evidence("evidence-fixture")]),
    )
    is Err(_),
  )
  let foreign = slice_a_ref("subject", "foreign-subject", b"foreign-subject")
  assert_true(
    PreDispatchAuthorization::new(
      "authorization-foreign-subject",
      slice_a_producer(),
      slice_a_governance(),
      slice_a_eligibility(),
      slice_a_planned(subject=foreign),
      slice_a_controls(evidence=[slice_a_evidence("evidence-fixture")]),
    )
    is Err(_),
  )
  ignore(slice_a_authorization(eligibility=slice_a_eligibility(clock=10L)))
  ignore(slice_a_authorization(eligibility=slice_a_eligibility(clock=20L)))
  assert_true(
    PreDispatchAuthorization::new(
      "authorization-before-window",
      slice_a_producer(),
      slice_a_governance(),
      slice_a_eligibility(clock=9L),
      slice_a_planned(),
      slice_a_controls(evidence=[slice_a_evidence("evidence-fixture")]),
    )
    is Err(_),
  )
  assert_true(
    PreDispatchAuthorization::new(
      "authorization-after-window",
      slice_a_producer(),
      slice_a_governance(),
      slice_a_eligibility(clock=21L),
      slice_a_planned(),
      slice_a_controls(evidence=[slice_a_evidence("evidence-fixture")]),
    )
    is Err(_),
  )
}

///|
test "FLOW-6C authorization link validates digest" {
  let link = slice_a_authorization_link()
  ignore(link)
  let authorization = slice_a_authorization()
  let commit_ref = slice_a_ref(
    "commit-event", "commit-event-mismatch", b"commit-event-mismatch",
  )
  let position = ReplayPosition::new(commit_ref, 8L, 4L, commit_ref.digest()).unwrap()
  assert_true(
    AuthorizationLink::new(
      authorization.record_ref(),
      slice_a_wrong_digest(),
      position,
    )
    is Err(_),
  )
}

///|
test "FLOW-6C authorization is canonical and round trips" {
  let first = slice_a_authorization()
  let second = slice_a_authorization()
  assert_eq(first.canonical_bytes(), second.canonical_bytes())
  assert_true(first.record_digest() == second.record_digest())
  assert_true(first.record_ref() == second.record_ref())
  let bytes = first.canonical_bytes()
  let decoded = decode_pre_dispatch_authorization(
    "authorization-fixture", bytes,
  ).unwrap()
  assert_true(decoded == first)
  assert_eq(decoded.canonical_bytes(), first.canonical_bytes())
  assert_true(decoded.controls().capability() is Some(_))
  assert_true(decoded.controls().fencing() is Some(_))
  assert_eq(decoded.controls().evidence().length(), 1)
}

///|
test "FLOW-6C Slice A tuple and eligibility validation" {
  assert_true(EligibilityBinding::new(-1L, slice_a_head()) is Err(_))
  let workflow = slice_a_ref(
    "workflow", "workflow-validation", b"workflow-validation",
  )
  let subject = slice_a_ref(
    "subject", "subject-validation", b"subject-validation",
  )
  let requested = slice_a_ref(
    "requested-work", "requested-validation", b"requested-validation",
  )
  let effect = slice_a_ref(
    "effect-request", "effect-validation", b"effect-validation",
  )
  let artifact = @contracts.sha256_digest(b"artifact-validation")
  let make = fn(a, b, c, d, ordinal, e, requested_digest, effect_digest) {
    PlannedEffectTuple::new(
      workflow, subject, a, b, c, d, ordinal, e, requested, requested_digest, effect,
      effect_digest, artifact,
    )
  }
  assert_true(
    make("", "b", "c", "d", 1L, "e", requested.digest(), effect.digest())
    is Err(_),
  )
  assert_true(
    make("a", "", "c", "d", 1L, "e", requested.digest(), effect.digest())
    is Err(_),
  )
  assert_true(
    make("a", "b", "", "d", 1L, "e", requested.digest(), effect.digest())
    is Err(_),
  )
  assert_true(
    make("a", "b", "c", "", 1L, "e", requested.digest(), effect.digest())
    is Err(_),
  )
  assert_true(
    make("a", "b", "c", "d", 1L, "", requested.digest(), effect.digest())
    is Err(_),
  )
  assert_true(
    make("a", "b", "c", "d", 0L, "e", requested.digest(), effect.digest())
    is Err(_),
  )
  assert_true(
    make("a", "b", "c", "d", -1L, "e", requested.digest(), effect.digest())
    is Err(_),
  )
  assert_true(
    make("a", "b", "c", "d", 1L, "e", slice_a_wrong_digest(), effect.digest())
    is Err(_),
  )
  assert_true(
    make(
      "a",
      "b",
      "c",
      "d",
      1L,
      "e",
      requested.digest(),
      slice_a_wrong_digest(),
    )
    is Err(_),
  )
  ignore(slice_a_planned())
}

///|
test "FLOW-6C Slice A binding and controls validation" {
  let capability = slice_a_ref(
    "capability", "capability-validation", b"capability-validation",
  )
  assert_true(
    CapabilityBinding::new(capability, slice_a_wrong_digest()) is Err(_),
  )
  let evidence = slice_a_ref(
    "evidence", "evidence-validation", b"evidence-validation",
  )
  assert_true(EvidenceBinding::new(evidence, slice_a_wrong_digest()) is Err(_))
  let fencing = slice_a_ref(
    "fencing", "fencing-validation", b"fencing-validation",
  )
  assert_true(FencingBinding::new(fencing, -1L, 1L) is Err(_))
  assert_true(FencingBinding::new(fencing, 1L, -1L) is Err(_))
  assert_true(
    AuthorizationControls::new(
      Some(slice_a_capability()),
      [],
      Some(slice_a_fencing()),
      Some(10L),
      -1L,
    )
    is Err(_),
  )
  assert_true(
    AuthorizationControls::new(
      Some(slice_a_capability()),
      [],
      Some(slice_a_fencing()),
      Some(-1L),
      20L,
    )
    is Err(_),
  )
  assert_true(
    AuthorizationControls::new(
      Some(slice_a_capability()),
      [],
      Some(slice_a_fencing()),
      Some(21L),
      20L,
    )
    is Err(_),
  )
  let duplicate = slice_a_evidence("duplicate")
  assert_true(
    AuthorizationControls::new(
      Some(slice_a_capability()),
      [duplicate, duplicate],
      Some(slice_a_fencing()),
      Some(10L),
      20L,
    )
    is Err(_),
  )
}

///|
test "FLOW-6C Slice A controls interval and evidence snapshot" {
  let caller = [slice_a_evidence("one"), slice_a_evidence("two")]
  let controls = slice_a_controls(evidence=caller)
  assert_false(controls.accepts(9L))
  assert_true(controls.accepts(10L))
  assert_true(controls.accepts(20L))
  assert_false(controls.accepts(21L))
  let saved_evidence = controls.evidence()
  let saved_digest = controls.evidence_digest()
  let first = caller[0]
  caller[0] = caller[1]
  caller[1] = first
  caller[0] = slice_a_evidence("replacement")
  assert_true(controls.evidence() == saved_evidence)
  assert_true(controls.evidence_digest() == saved_digest)
}

///|
test "FLOW-6C ReplayPosition validates coordinates and authoritative digest" {
  let event = slice_a_ref("event", "event-1", b"event-1")
  assert_true(ReplayPosition::new(event, 0L, 0L, event.digest()) is Ok(_))
  assert_true(ReplayPosition::new(event, -1L, 0L, event.digest()) is Err(_))
  assert_true(ReplayPosition::new(event, 0L, -1L, event.digest()) is Err(_))
  assert_true(
    ReplayPosition::new(event, 0L, 0L, @contracts.sha256_digest(b"not-event-1"))
    is Err(_),
  )
}

///|
test "FLOW-6C ProducerDescriptor rejects blank identity and mismatched content" {
  let producer = slice_a_ref("producer", "producer-1", b"producer-1")
  assert_true(
    ProducerDescriptor::new("", "1.0.0", producer, producer.digest()) is Err(_),
  )
  assert_true(
    ProducerDescriptor::new("producer", "", producer, producer.digest())
    is Err(_),
  )
  assert_true(
    ProducerDescriptor::new(
      "producer",
      "1.0.0",
      producer,
      @contracts.sha256_digest(b"other"),
    )
    is Err(_),
  )
}

///|
test "FLOW-6C governance interval is inclusive and content-addressed" {
  let decision = slice_a_ref("decision", "decision-1", b"decision-1")
  let policy = slice_a_ref("policy", "policy-1", b"policy-1")
  let subject = slice_a_ref("subject", "subject-1", b"subject-1")
  let binding = AuthorizationGovernanceBinding::new(
    decision,
    decision.digest(),
    policy,
    policy.digest(),
    subject,
    10L,
    20L,
  ).unwrap()
  assert_false(binding.accepts(9L))
  assert_true(binding.accepts(10L))
  assert_true(binding.accepts(20L))
  assert_false(binding.accepts(21L))
  assert_true(
    AuthorizationGovernanceBinding::new(
      decision,
      @contracts.sha256_digest(b"wrong-decision"),
      policy,
      policy.digest(),
      subject,
      10L,
      20L,
    )
    is Err(_),
  )
  assert_true(
    AuthorizationGovernanceBinding::new(
      decision,
      decision.digest(),
      policy,
      @contracts.sha256_digest(b"wrong-policy"),
      subject,
      10L,
      20L,
    )
    is Err(_),
  )
  assert_true(
    AuthorizationGovernanceBinding::new(
      decision,
      decision.digest(),
      policy,
      policy.digest(),
      subject,
      20L,
      10L,
    )
    is Err(_),
  )
}
