///|
fn v2_payload(n : Int) -> Bytes {
  Bytes::from_array([0x46, 0x36, 0x43, n.to_byte()])
}

///|
fn v2_mutate(bytes : Bytes, index : Int, value : Byte) -> Bytes {
  let result : Array[Byte] = []
  for byte in bytes {
    result.push(byte)
  }
  result[index] = value
  Bytes::from_array(result)
}

///|
fn v2_event(
  id : String,
  kind : AuthorizationEventKindV2,
  position : Int,
  previous : @contracts.ContentDigest,
  sequence? : Int64 = position.to_int64(),
  revision? : Int64 = position.to_int64(),
  causation? : @contracts.ContentDigest = previous,
  payload? : Bytes = v2_payload(position),
) -> AuthorizationEventEnvelopeV2 {
  let record = try! @contracts.RecordRef::new(
    "authorization-record",
    "record-" + id,
    "2.0.0",
    @contracts.sha256_digest(payload).text(),
  )
  AuthorizationEventEnvelopeV2::new(
    id,
    kind,
    contract_version,
    "FLOW-6C.authorization-event-envelope.v2",
    record,
    record.digest(),
    sequence,
    revision,
    causation,
    previous,
    payload,
  ).unwrap()
}

///|
fn v2_chain() -> Array[AuthorizationEventEnvelopeV2] {
  let e0 = v2_event(
    "event-0",
    PreDispatchAuthorizationCommittedV2,
    0,
    authorization_event_genesis_digest_v2,
    causation=authorization_event_genesis_digest_v2,
  )
  let e1 = v2_event(
    "event-1",
    AuthorizedAttemptRegistrationCommittedV2,
    1,
    e0.event_digest(),
  )
  let e2 = v2_event(
    "event-2",
    AuthorizedEffectIntentCommittedV2,
    2,
    e1.event_digest(),
  )
  let e3 = v2_event(
    "event-3",
    EligibleAuthorizationProofCommittedV2,
    3,
    e2.event_digest(),
  )
  [e0, e1, e2, e3]
}

///|
test "v2 public kind factories preserve exact kinds and text" {
  let cases = [
    (
      AuthorizationEventKindV2::pre_dispatch_authorization_committed(),
      PreDispatchAuthorizationCommittedV2,
      "PreDispatchAuthorizationCommittedV2",
    ),
    (
      AuthorizationEventKindV2::authorized_attempt_registration_committed(),
      AuthorizedAttemptRegistrationCommittedV2,
      "AuthorizedAttemptRegistrationCommittedV2",
    ),
    (
      AuthorizationEventKindV2::authorized_effect_intent_committed(),
      AuthorizedEffectIntentCommittedV2,
      "AuthorizedEffectIntentCommittedV2",
    ),
    (
      AuthorizationEventKindV2::eligible_authorization_proof_committed(),
      EligibleAuthorizationProofCommittedV2,
      "EligibleAuthorizationProofCommittedV2",
    ),
  ]
  for item in cases {
    let (actual, expected, text) = item
    assert_true(actual == expected)
    assert_eq(actual.text(), text)
  }
}

///|
test "v2 factory kind remains subject to append ordering" {
  let store = AuthorizationEventStoreV2::new()
  let out_of_order = v2_event(
    "factory-out-of-order",
    AuthorizationEventKindV2::authorized_attempt_registration_committed(),
    0,
    authorization_event_genesis_digest_v2,
    causation=authorization_event_genesis_digest_v2,
  )
  assert_true(store.append(out_of_order) is Err(_))
}

///|
test "v2 four kinds strict roundtrip and self-addressing" {
  for event in v2_chain() {
    let decoded = decode_authorization_event_envelope_v2(
      event.canonical_bytes(),
    ).unwrap()
    assert_true(decoded == event)
    assert_true(decoded.event_ref().digest() == decoded.event_digest())
    assert_true(decoded.canonical_bytes() == event.canonical_bytes())
  }
}

///|
test "v2 decoder rejects empty version kind schema payload digest trailing and every prefix" {
  let event = v2_chain()[0]
  let frame = event.canonical_bytes()
  assert_true(decode_authorization_event_envelope_v2(b"") is Err(_))
  assert_true(
    decode_authorization_event_envelope_v2(v2_mutate(frame, 0, 3)) is Err(_),
  )
  let id_len = @utf8.encode(event.event_ref().id()).length()
  let kind_offset = 1 + 4 + id_len + 4
  assert_true(
    decode_authorization_event_envelope_v2(v2_mutate(frame, kind_offset, 0xff))
    is Err(_),
  )
  let schema_offset = 1 +
    4 +
    id_len +
    4 +
    @utf8.encode(event.kind().text()).length() +
    4 +
    @utf8.encode(event.contract()).length() +
    4
  assert_true(
    decode_authorization_event_envelope_v2(
      v2_mutate(frame, schema_offset, 0xff),
    )
    is Err(_),
  )
  assert_true(
    decode_authorization_event_envelope_v2(
      v2_mutate(frame, frame.length() - 1, 0xff),
    )
    is Err(_),
  )
  let digest_offset = frame.length() - event.payload().length() - 4 - 32 - 1
  assert_true(
    decode_authorization_event_envelope_v2(
      v2_mutate(frame, digest_offset, 0xff),
    )
    is Err(_),
  )
  let trailing : Array[Byte] = []
  for byte in frame {
    trailing.push(byte)
  }
  trailing.push(0)
  assert_true(
    decode_authorization_event_envelope_v2(Bytes::from_array(trailing))
    is Err(_),
  )
  for length = 0; length < frame.length(); length = length + 1 {
    assert_true(
      decode_authorization_event_envelope_v2(frame[0:length].to_owned())
      is Err(_),
    )
  }
}

///|
test "v2 chain and exact tail duplicate" {
  let store = AuthorizationEventStoreV2::new()
  let chain = v2_chain()
  for event in chain {
    assert_true(store.append(event) == Ok(true))
  }
  assert_true(store.append(chain[3]) == Ok(false))
}

///|
test "v2 same id different content and non-tail identity rejected" {
  let store = AuthorizationEventStoreV2::new()
  let chain = v2_chain()
  for event in chain {
    assert_true(store.append(event) == Ok(true))
  }
  let conflict = v2_event(
    "event-3",
    EligibleAuthorizationProofCommittedV2,
    4,
    chain[3].event_digest(),
    payload=v2_payload(99),
  )
  assert_true(store.append(conflict) is Err(_))
  assert_true(store.append(chain[1]) is Err(_))
}

///|
test "v2 sequence revision previous causation kind and fifth event rules" {
  let chain = v2_chain()
  let store = AuthorizationEventStoreV2::new()
  for event in chain {
    assert_true(store.append(event) == Ok(true))
  }
  assert_true(
    store.append(
      v2_event(
        "skip-seq",
        PreDispatchAuthorizationCommittedV2,
        4,
        chain[3].event_digest(),
        sequence=5L,
      ),
    )
    is Err(_),
  )
  assert_true(
    store.append(
      v2_event(
        "skip-rev",
        PreDispatchAuthorizationCommittedV2,
        4,
        chain[3].event_digest(),
        revision=5L,
      ),
    )
    is Err(_),
  )
  assert_true(
    store.append(
      v2_event(
        "wrong-prev",
        PreDispatchAuthorizationCommittedV2,
        4,
        authorization_event_genesis_digest_v2,
      ),
    )
    is Err(_),
  )
  assert_true(
    store.append(
      v2_event(
        "wrong-cause",
        PreDispatchAuthorizationCommittedV2,
        4,
        chain[3].event_digest(),
        causation=authorization_event_genesis_digest_v2,
      ),
    )
    is Err(_),
  )
  assert_true(
    store.append(
      v2_event(
        "wrong-kind",
        AuthorizedAttemptRegistrationCommittedV2,
        4,
        chain[3].event_digest(),
      ),
    )
    is Err(_),
  )
  assert_true(
    store.append(
      v2_event(
        "fifth",
        PreDispatchAuthorizationCommittedV2,
        4,
        chain[3].event_digest(),
      ),
    )
    is Err(_),
  )
}

///|
test "v2 exact recovery and corrupt every final prefix reordered missing rejection" {
  let chain = v2_chain()
  let frames = chain.map(fn(event) { event.canonical_bytes() })
  let recovered = recover_v2_store(frames).unwrap()
  assert_true(recovered.events() == chain)
  let corrupt = frames.copy()
  corrupt[3] = v2_mutate(corrupt[3], corrupt[3].length() - 1, 0xff)
  assert_true(recover_v2_store(corrupt) is Err(_))
  for length = 0; length < frames[3].length(); length = length + 1 {
    let prefixes = frames.copy()
    prefixes[3] = frames[3][0:length].to_owned()
    assert_true(recover_v2_store(prefixes) is Err(_))
  }
  assert_true(
    recover_v2_store([frames[0], frames[2], frames[1], frames[3]]) is Err(_),
  )
  assert_true(recover_v2_store([frames[0], frames[2], frames[3]]) is Err(_))
}
