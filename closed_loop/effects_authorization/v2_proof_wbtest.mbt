///|
/// Deterministic FLOW-6C V2 Slice B white-box fixtures.
fn proof_v2_ref(
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
fn proof_v2_position() -> ReplayPosition {
  let event = proof_v2_ref("event", "proof-v2-head", b"proof-v2-head")
  ReplayPosition::new(event, 7L, 3L, event.digest()).unwrap()
}

///|
fn proof_v2_producer() -> ProducerDescriptor {
  let record = proof_v2_ref(
    "producer", "proof-v2-producer", b"proof-v2-producer",
  )
  ProducerDescriptor::new("fixture.producer", "1.0.0", record, record.digest()).unwrap()
}

///|
fn proof_v2_governance() -> AuthorizationGovernanceBinding {
  let decision = proof_v2_ref(
    "decision", "proof-v2-decision", b"proof-v2-decision",
  )
  let policy = proof_v2_ref("policy", "proof-v2-policy", b"proof-v2-policy")
  let subject = proof_v2_ref("subject", "proof-v2-subject", b"proof-v2-subject")
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
fn proof_v2_planned() -> PlannedEffectTuple {
  let subject = proof_v2_ref("subject", "proof-v2-subject", b"proof-v2-subject")
  let workflow = proof_v2_ref(
    "workflow", "proof-v2-workflow", b"proof-v2-workflow",
  )
  let requested = proof_v2_ref(
    "requested-work", "proof-v2-requested", b"proof-v2-requested",
  )
  let effect = proof_v2_ref(
    "effect-request", "proof-v2-effect", b"proof-v2-effect",
  )
  PlannedEffectTuple::new(
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
fn proof_v2_controls() -> AuthorizationControls {
  let evidence_ref = proof_v2_ref(
    "evidence", "proof-v2-evidence", b"proof-v2-evidence",
  )
  let evidence = EvidenceBinding::new(evidence_ref, evidence_ref.digest()).unwrap()
  let capability_ref = proof_v2_ref(
    "capability", "proof-v2-capability", b"proof-v2-capability",
  )
  let capability = CapabilityBinding::new(
    capability_ref,
    capability_ref.digest(),
  ).unwrap()
  let fencing_ref = proof_v2_ref(
    "fencing", "proof-v2-fencing", b"proof-v2-fencing",
  )
  let fencing = FencingBinding::new(fencing_ref, 1L, 1L).unwrap()
  AuthorizationControls::new(
    Some(capability),
    [evidence],
    Some(fencing),
    Some(10L),
    20L,
  ).unwrap()
}

///|
fn proof_v2_authorization(
  clock : Int64,
) -> Result[PreDispatchAuthorization, AuthorizationError] {
  PreDispatchAuthorization::new(
    "proof-v2-authorization",
    proof_v2_producer(),
    proof_v2_governance(),
    EligibilityBinding::new(clock, proof_v2_position()).unwrap(),
    proof_v2_planned(),
    proof_v2_controls(),
  )
}

///|
fn proof_v2_replace_byte(
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
fn proof_v2_proper_prefix(bytes : Bytes, length : Int) -> Bytes {
  let copied : Array[Byte] = []
  for index = 0; index < length; index = index + 1 {
    copied.push(bytes[index])
  }
  Bytes::from_array(copied)
}

///|
/// A complete canonical three-record history used by proof tests.
fn proof_v2_envelope(
  id : String,
  kind : AuthorizationEventKindV2,
  record_ref : @contracts.RecordRef,
  payload : Bytes,
  position : Int,
  previous : @contracts.ContentDigest,
) -> AuthorizationEventEnvelopeV2 {
  AuthorizationEventEnvelopeV2::new(
    id,
    kind,
    contract_version,
    "FLOW-6C.authorization-event-envelope.v2",
    record_ref,
    record_ref.digest(),
    position.to_int64(),
    position.to_int64(),
    previous,
    previous,
    payload,
  ).unwrap()
}

///|
struct ProofV2Fixture {
  store : AuthorizationEventStoreV2
  authorization : PreDispatchAuthorization
  attempt : AuthorizedAttemptRegistration
  intent : AuthorizedEffectIntent
}

///|
fn proof_v2_mismatch_store(
  producer : ProducerDescriptor,
  governance : AuthorizationGovernanceBinding,
  eligibility : EligibilityBinding,
  planned : PlannedEffectTuple,
  controls : AuthorizationControls,
  wrong_authorization_position? : Bool = false,
) -> AuthorizationEventStoreV2 {
  let auth = proof_v2_authorization(10L).unwrap()
  let e0 = proof_v2_envelope(
    "proof-v2-event-0",
    PreDispatchAuthorizationCommittedV2,
    auth.record_ref(),
    auth.canonical_bytes(),
    0,
    authorization_event_genesis_digest_v2,
  )
  let p0 = ReplayPosition::new(
    e0.event_ref(),
    0L,
    if wrong_authorization_position {
      9L
    } else {
      0L
    },
    e0.event_digest(),
  ).unwrap()
  let auth_link = AuthorizationLink::new(
    auth.record_ref(),
    auth.record_digest(),
    p0,
  ).unwrap()
  let attempt = AuthorizedAttemptRegistration::new(
    "proof-v2-attempt", auth_link, producer, governance, eligibility, planned, controls,
  ).unwrap()
  let e1 = proof_v2_envelope(
    "proof-v2-event-1",
    AuthorizedAttemptRegistrationCommittedV2,
    attempt.record_ref(),
    attempt.canonical_bytes(),
    1,
    e0.event_digest(),
  )
  let p1 = ReplayPosition::new(e1.event_ref(), 1L, 1L, e1.event_digest()).unwrap()
  let attempt_link = AttemptLink::new(
    attempt.record_ref(),
    attempt.record_digest(),
    p1,
  ).unwrap()
  let intent = AuthorizedEffectIntent::new(
    "proof-v2-intent", auth_link, attempt_link, producer, governance, eligibility,
    planned, controls,
  ).unwrap()
  let e2 = proof_v2_envelope(
    "proof-v2-event-2",
    AuthorizedEffectIntentCommittedV2,
    intent.record_ref(),
    intent.canonical_bytes(),
    2,
    e1.event_digest(),
  )
  let store = AuthorizationEventStoreV2::new()
  let _ = store.append(e0).unwrap()
  let _ = store.append(e1).unwrap()
  let _ = store.append(e2).unwrap()
  store
}

///|
fn proof_v2_fixture(clock : Int64) -> ProofV2Fixture {
  let auth = proof_v2_authorization(clock).unwrap()
  let e0 = proof_v2_envelope(
    "proof-v2-event-0",
    PreDispatchAuthorizationCommittedV2,
    auth.record_ref(),
    auth.canonical_bytes(),
    0,
    authorization_event_genesis_digest_v2,
  )
  let p0 = ReplayPosition::new(e0.event_ref(), 0L, 0L, e0.event_digest()).unwrap()
  let auth_link = AuthorizationLink::new(
    auth.record_ref(),
    auth.record_digest(),
    p0,
  ).unwrap()
  let attempt = AuthorizedAttemptRegistration::new(
    "proof-v2-attempt",
    auth_link,
    auth.producer(),
    auth.governance(),
    auth.eligibility(),
    auth.planned(),
    auth.controls(),
  ).unwrap()
  let e1 = proof_v2_envelope(
    "proof-v2-event-1",
    AuthorizedAttemptRegistrationCommittedV2,
    attempt.record_ref(),
    attempt.canonical_bytes(),
    1,
    e0.event_digest(),
  )
  let p1 = ReplayPosition::new(e1.event_ref(), 1L, 1L, e1.event_digest()).unwrap()
  let attempt_link = AttemptLink::new(
    attempt.record_ref(),
    attempt.record_digest(),
    p1,
  ).unwrap()
  let intent = AuthorizedEffectIntent::new(
    "proof-v2-intent",
    auth_link,
    attempt_link,
    auth.producer(),
    auth.governance(),
    auth.eligibility(),
    auth.planned(),
    auth.controls(),
  ).unwrap()
  let e2 = proof_v2_envelope(
    "proof-v2-event-2",
    AuthorizedEffectIntentCommittedV2,
    intent.record_ref(),
    intent.canonical_bytes(),
    2,
    e1.event_digest(),
  )
  let store = AuthorizationEventStoreV2::new()
  let _ = store.append(e0).unwrap()
  let _ = store.append(e1).unwrap()
  let _ = store.append(e2).unwrap()
  { store, authorization: auth, attempt, intent }
}

///|
test "proof v2 valid chain derives and appends exact proof event" {
  let fixture = proof_v2_fixture(10L)
  let before = fixture.store.events()
  let commit = derive_eligible_authorization_proof_commit_v2(
    fixture.store,
    "proof-v2-proof",
    "proof-v2-event-3",
  ).unwrap()
  let proof = commit.proof()
  let event = commit.event()
  assert_true(proof.intent_ref() == fixture.intent.record_ref())
  assert_true(proof.intent_digest() == fixture.intent.record_digest())
  assert_true(proof.producer() == fixture.authorization.producer())
  assert_true(proof.governance() == fixture.authorization.governance())
  assert_true(proof.eligibility() == fixture.authorization.eligibility())
  assert_true(proof.planned() == fixture.authorization.planned())
  assert_true(proof.controls() == fixture.authorization.controls())
  assert_true(proof.record_ref().digest() == proof.digest())
  assert_true(
    @contracts.sha256_digest(proof.canonical_bytes()) == proof.digest(),
  )
  assert_true(event.kind() == EligibleAuthorizationProofCommittedV2)
  assert_true(event.sequence() == 3L)
  assert_true(event.revision() == 3L)
  assert_true(event.previous_digest() == before[2].event_digest())
  assert_true(event.causation() == before[2].event_digest())
  assert_true(event.record_ref() == proof.record_ref())
  assert_true(event.record_digest() == proof.digest())
  assert_true(event.payload() == proof.canonical_bytes())
  assert_true(fixture.store.append(event) is Ok(true))
  assert_true(fixture.store.events().length() == 4)
}

///|
test "proof v2 derivation rejects producer mismatch" {
  let producer_ref = proof_v2_ref(
    "producer", "proof-v2-producer-other", b"proof-v2-producer-other",
  )
  let alternate_producer = ProducerDescriptor::new(
    "fixture.producer",
    "1.0.0",
    producer_ref,
    producer_ref.digest(),
  ).unwrap()
  let store = proof_v2_mismatch_store(
    alternate_producer,
    proof_v2_governance(),
    EligibilityBinding::new(10L, proof_v2_position()).unwrap(),
    proof_v2_planned(),
    proof_v2_controls(),
  )
  let result = derive_eligible_authorization_proof_commit_v2(
    store, "proof-v2-producer-mismatch-proof", "proof-v2-producer-mismatch-event",
  )
  assert_true(result is Err(ProducerMismatch(_)))
}

///|
test "proof v2 derivation rejects governance mismatch" {
  let decision = proof_v2_ref(
    "decision", "proof-v2-decision-other", b"proof-v2-decision-other",
  )
  let policy = proof_v2_ref("policy", "proof-v2-policy", b"proof-v2-policy")
  let subject = proof_v2_ref("subject", "proof-v2-subject", b"proof-v2-subject")
  let governance = AuthorizationGovernanceBinding::new(
    decision,
    decision.digest(),
    policy,
    policy.digest(),
    subject,
    10L,
    20L,
  ).unwrap()
  let store = proof_v2_mismatch_store(
    proof_v2_producer(),
    governance,
    EligibilityBinding::new(10L, proof_v2_position()).unwrap(),
    proof_v2_planned(),
    proof_v2_controls(),
  )
  let result = derive_eligible_authorization_proof_commit_v2(
    store, "proof-v2-governance-mismatch", "proof-v2-governance-mismatch-event",
  )
  assert_true(result is Err(GovernanceMismatch(_)))
}

///|
test "proof v2 derivation rejects eligibility mismatch" {
  let head = proof_v2_ref(
    "event", "proof-v2-head-other", b"proof-v2-head-other",
  )
  let position = ReplayPosition::new(head, 7L, 3L, head.digest()).unwrap()
  let store = proof_v2_mismatch_store(
    proof_v2_producer(),
    proof_v2_governance(),
    EligibilityBinding::new(10L, position).unwrap(),
    proof_v2_planned(),
    proof_v2_controls(),
  )
  let result = derive_eligible_authorization_proof_commit_v2(
    store, "proof-v2-eligibility-mismatch", "proof-v2-eligibility-mismatch-event",
  )
  assert_true(result is Err(EligibilityMismatch(_)))
}

///|
test "proof v2 derivation rejects planned tuple mismatch" {
  let subject = proof_v2_ref("subject", "proof-v2-subject", b"proof-v2-subject")
  let workflow = proof_v2_ref(
    "workflow", "proof-v2-workflow", b"proof-v2-workflow",
  )
  let requested = proof_v2_ref(
    "requested-work", "proof-v2-requested", b"proof-v2-requested",
  )
  let effect = proof_v2_ref(
    "effect-request", "proof-v2-effect", b"proof-v2-effect",
  )
  let planned = PlannedEffectTuple::new(
    workflow,
    subject,
    "attempt",
    "1",
    "effect",
    "1",
    1L,
    "proof-v2-idempotency-other",
    requested,
    requested.digest(),
    effect,
    effect.digest(),
    @contracts.sha256_digest(b"proof-v2-artifact"),
  ).unwrap()
  let store = proof_v2_mismatch_store(
    proof_v2_producer(),
    proof_v2_governance(),
    EligibilityBinding::new(10L, proof_v2_position()).unwrap(),
    planned,
    proof_v2_controls(),
  )
  let result = derive_eligible_authorization_proof_commit_v2(
    store, "proof-v2-tuple-mismatch", "proof-v2-tuple-mismatch-event",
  )
  assert_true(result is Err(TupleMismatch(_)))
}

///|
test "proof v2 derivation rejects controls evidence mismatch" {
  let evidence_ref = proof_v2_ref(
    "evidence", "proof-v2-evidence-other", b"proof-v2-evidence-other",
  )
  let evidence = EvidenceBinding::new(evidence_ref, evidence_ref.digest()).unwrap()
  let capability_ref = proof_v2_ref(
    "capability", "proof-v2-capability", b"proof-v2-capability",
  )
  let capability = CapabilityBinding::new(
    capability_ref,
    capability_ref.digest(),
  ).unwrap()
  let fencing_ref = proof_v2_ref(
    "fencing", "proof-v2-fencing", b"proof-v2-fencing",
  )
  let fencing = FencingBinding::new(fencing_ref, 1L, 1L).unwrap()
  let controls = AuthorizationControls::new(
    Some(capability),
    [evidence],
    Some(fencing),
    Some(10L),
    20L,
  ).unwrap()
  let store = proof_v2_mismatch_store(
    proof_v2_producer(),
    proof_v2_governance(),
    EligibilityBinding::new(10L, proof_v2_position()).unwrap(),
    proof_v2_planned(),
    controls,
  )
  let result = derive_eligible_authorization_proof_commit_v2(
    store, "proof-v2-controls-mismatch", "proof-v2-controls-mismatch-event",
  )
  assert_true(result is Err(ControlMismatch(_)))
}

///|
test "proof v2 derivation rejects wrong authorization position" {
  let store = proof_v2_mismatch_store(
    proof_v2_producer(),
    proof_v2_governance(),
    EligibilityBinding::new(10L, proof_v2_position()).unwrap(),
    proof_v2_planned(),
    proof_v2_controls(),
    wrong_authorization_position=true,
  )
  let result = derive_eligible_authorization_proof_commit_v2(
    store, "proof-v2-causal-mismatch", "proof-v2-causal-mismatch-event",
  )
  assert_true(result is Err(CausalMismatch(_)))
}

///|
test "proof v2 derivation rejects excess history" {
  let fixture = proof_v2_fixture(10L)
  let commit = derive_eligible_authorization_proof_commit_v2(
    fixture.store,
    "proof-v2-excess-history-proof",
    "proof-v2-excess-history-event",
  ).unwrap()
  let _ = fixture.store.append(commit.event()).unwrap()
  let result = derive_eligible_authorization_proof_commit_v2(
    fixture.store,
    "proof-v2-excess-history-proof-second",
    "proof-v2-excess-history-event-second",
  )
  assert_true(result is Err(CausalMismatch(_)))
}

///|
test "proof v2 derivation fails closed for incomplete histories" {
  let fixture = proof_v2_fixture(15L)
  let events = fixture.store.events()
  let proof_id = "proof-v2-authorization"
  let event_id = "proof-v2-attempt"
  let empty = AuthorizationEventStoreV2::new()
  let result = derive_eligible_authorization_proof_commit_v2(
    empty, proof_id, event_id,
  )
  assert_true(result is Err(_))
  let event0_only = AuthorizationEventStoreV2::new()
  let _ = event0_only.append(events[0]).unwrap()
  let result = derive_eligible_authorization_proof_commit_v2(
    event0_only, proof_id, event_id,
  )
  assert_true(result is Err(_))
  let event0_event1 = AuthorizationEventStoreV2::new()
  let _ = event0_event1.append(events[0]).unwrap()
  let _ = event0_event1.append(events[1]).unwrap()
  let result = derive_eligible_authorization_proof_commit_v2(
    event0_event1, proof_id, event_id,
  )
  assert_true(result is Err(_))
}

///|
test "proof v2 Slice A authorization accepts inclusive clock bounds" {
  assert_true(proof_v2_authorization(10L) is Ok(_))
  assert_true(proof_v2_authorization(20L) is Ok(_))
  assert_true(proof_v2_authorization(9L) is Err(_))
  assert_true(proof_v2_authorization(21L) is Err(_))
}

///|
test "proof v2 derivation is deterministic and canonical roundtrips" {
  let fixture1 = proof_v2_fixture(10L)
  let fixture2 = proof_v2_fixture(10L)
  let commit1 = derive_eligible_authorization_proof_commit_v2(
    fixture1.store,
    "proof-v2-deterministic-proof",
    "proof-v2-deterministic-event",
  ).unwrap()
  let commit2 = derive_eligible_authorization_proof_commit_v2(
    fixture2.store,
    "proof-v2-deterministic-proof",
    "proof-v2-deterministic-event",
  ).unwrap()
  let proof1 = commit1.proof()
  let event1 = commit1.event()
  let proof2 = commit2.proof()
  let event2 = commit2.event()
  assert_true(commit1 == commit2)
  assert_true(proof1.canonical_bytes() == proof2.canonical_bytes())
  assert_true(event1.canonical_bytes() == event2.canonical_bytes())
  let decoded_proof = decode_eligible_authorization_proof_v2(
    proof1.record_ref().id(),
    proof1.canonical_bytes(),
  ).unwrap()
  let decoded_event = decode_authorization_event_envelope_v2(
    event1.canonical_bytes(),
  ).unwrap()
  assert_true(decoded_proof == proof1)
  assert_true(decoded_event == event1)
}

///|
test "proof v2 strict decoder rejects corruption" {
  let fixture = proof_v2_fixture(10L)
  let commit = derive_eligible_authorization_proof_commit_v2(
    fixture.store,
    "proof-v2-corruption-proof",
    "proof-v2-corruption-event",
  ).unwrap()
  let proof = commit.proof()
  let bytes = proof.canonical_bytes()
  let id = proof.record_ref().id()
  assert_true(
    decode_eligible_authorization_proof_v2("different-proof-id", bytes)
    is Err(_),
  )
  let encoded_id_first_byte_offset = 4 +
    "flow6c/eligible-authorization-proof-v2/2.0.0".length() +
    4
  assert_true(
    decode_eligible_authorization_proof_v2(
      id,
      proof_v2_replace_byte(bytes, encoded_id_first_byte_offset, 0xff),
    )
    is Err(_),
  )
  assert_true(decode_eligible_authorization_proof_v2(id, b"") is Err(_))
  assert_true(
    decode_eligible_authorization_proof_v2(
      id,
      proof_v2_replace_byte(bytes, 4, 0xff),
    )
    is Err(_),
  )
  assert_true(
    decode_eligible_authorization_proof_v2(
      id,
      proof_v2_replace_byte(bytes, bytes.length() - 1, 0x00),
    )
    is Err(_),
  )
  let trailing : Array[Byte] = []
  for byte in bytes {
    trailing.push(byte)
  }
  trailing.push(0)
  assert_true(
    decode_eligible_authorization_proof_v2(id, Bytes::from_array(trailing))
    is Err(_),
  )
  for length = 0; length < bytes.length(); length = length + 1 {
    assert_true(
      decode_eligible_authorization_proof_v2(
        id,
        proof_v2_proper_prefix(bytes, length),
      )
      is Err(_),
    )
  }
}
