///|
/// FLOW-6C V2 Slice B closed event catalog. Unknown values are never representable.
pub enum AuthorizationEventKindV2 {
  PreDispatchAuthorizationCommittedV2
  AuthorizedAttemptRegistrationCommittedV2
  AuthorizedEffectIntentCommittedV2
  EligibleAuthorizationProofCommittedV2
} derive(Eq, Debug)

///|
pub fn AuthorizationEventKindV2::pre_dispatch_authorization_committed() -> AuthorizationEventKindV2 {
  PreDispatchAuthorizationCommittedV2
}

///|
pub fn AuthorizationEventKindV2::authorized_attempt_registration_committed() -> AuthorizationEventKindV2 {
  AuthorizedAttemptRegistrationCommittedV2
}

///|
pub fn AuthorizationEventKindV2::authorized_effect_intent_committed() -> AuthorizationEventKindV2 {
  AuthorizedEffectIntentCommittedV2
}

///|
pub fn AuthorizationEventKindV2::eligible_authorization_proof_committed() -> AuthorizationEventKindV2 {
  EligibleAuthorizationProofCommittedV2
}

///|
pub fn AuthorizationEventKindV2::text(
  self : AuthorizationEventKindV2,
) -> String {
  match self {
    PreDispatchAuthorizationCommittedV2 => "PreDispatchAuthorizationCommittedV2"
    AuthorizedAttemptRegistrationCommittedV2 =>
      "AuthorizedAttemptRegistrationCommittedV2"
    AuthorizedEffectIntentCommittedV2 => "AuthorizedEffectIntentCommittedV2"
    EligibleAuthorizationProofCommittedV2 =>
      "EligibleAuthorizationProofCommittedV2"
  }
}

///|
/// The digest before the first event. It is deliberately domain-separated and fixed.
pub let authorization_event_genesis_digest_v2 : @contracts.ContentDigest = @contracts.sha256_digest(
  @utf8.encode("FLOW-6C.authorization-event-envelope.v2/genesis"),
)

///|
pub struct AuthorizationEventEnvelopeV2 {
  kind : AuthorizationEventKindV2
  contract : String
  schema : String
  event_ref : @contracts.RecordRef
  event_digest : @contracts.ContentDigest
  record_ref : @contracts.RecordRef
  record_digest : @contracts.ContentDigest
  sequence : Int64
  revision : Int64
  causation : @contracts.ContentDigest
  previous_digest : @contracts.ContentDigest
  payload : Bytes
  canonical : Bytes
} derive(Eq)

///|
pub fn AuthorizationEventEnvelopeV2::new(
  event_id : String,
  kind : AuthorizationEventKindV2,
  contract : String,
  schema : String,
  record_ref : @contracts.RecordRef,
  record_digest : @contracts.ContentDigest,
  sequence : Int64,
  revision : Int64,
  causation : @contracts.ContentDigest,
  previous_digest : @contracts.ContentDigest,
  payload : Bytes,
) -> Result[AuthorizationEventEnvelopeV2, AuthorizationError] {
  guard event_id.trim().length() > 0 else {
    return Err(CanonicalCodecError("blank event id"))
  }
  guard contract == contract_version else {
    return Err(CanonicalCodecError("unknown contract version"))
  }
  guard schema == "FLOW-6C.authorization-event-envelope.v2" else {
    return Err(CanonicalCodecError("unknown schema"))
  }
  guard record_ref.digest() == record_digest else {
    return Err(ContentReferenceMismatch("v2 envelope record"))
  }
  guard @contracts.sha256_digest(payload) == record_digest else {
    return Err(ContentReferenceMismatch("v2 envelope payload"))
  }
  guard sequence >= 0L else { return Err(Negative("sequence")) }
  guard revision >= 0L else { return Err(Negative("revision")) }
  if sequence == 0L && revision == 0L {
    guard previous_digest == authorization_event_genesis_digest_v2 &&
      causation == authorization_event_genesis_digest_v2 else {
      return Err(CanonicalCodecError("invalid genesis chain"))
    }
  }
  let w = AuthorizationWriter::new()
  w.byte(2)
  match w.string(event_id) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.string(kind.text()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.string(contract) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.string(schema) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.record_ref(record_ref) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.digest(record_digest) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  w.int64(sequence)
  w.int64(revision)
  match w.digest(causation) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.digest(previous_digest) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.bytes(payload) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let canonical = w.buffer.contents()
  let event_digest = @contracts.sha256_digest(canonical)
  let event_ref = @contracts.RecordRef::new(
    "authorization-event-envelope-v2",
    event_id,
    "2.0.0",
    event_digest.text(),
  ) catch {
    _ => return Err(CanonicalCodecError("invalid event reference"))
  }
  Ok({
    kind,
    contract,
    schema,
    event_ref,
    event_digest,
    record_ref,
    record_digest,
    sequence,
    revision,
    causation,
    previous_digest,
    payload,
    canonical,
  })
}

///|
pub fn AuthorizationEventEnvelopeV2::kind(
  self : AuthorizationEventEnvelopeV2,
) -> AuthorizationEventKindV2 {
  self.kind
}

///|
pub fn AuthorizationEventEnvelopeV2::contract(
  self : AuthorizationEventEnvelopeV2,
) -> String {
  self.contract
}

///|
pub fn AuthorizationEventEnvelopeV2::schema(
  self : AuthorizationEventEnvelopeV2,
) -> String {
  self.schema
}

///|
pub fn AuthorizationEventEnvelopeV2::event_ref(
  self : AuthorizationEventEnvelopeV2,
) -> @contracts.RecordRef {
  self.event_ref
}

///|
pub fn AuthorizationEventEnvelopeV2::event_digest(
  self : AuthorizationEventEnvelopeV2,
) -> @contracts.ContentDigest {
  self.event_digest
}

///|
pub fn AuthorizationEventEnvelopeV2::sequence(
  self : AuthorizationEventEnvelopeV2,
) -> Int64 {
  self.sequence
}

///|
pub fn AuthorizationEventEnvelopeV2::revision(
  self : AuthorizationEventEnvelopeV2,
) -> Int64 {
  self.revision
}

///|
pub fn AuthorizationEventEnvelopeV2::record_ref(
  self : AuthorizationEventEnvelopeV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn AuthorizationEventEnvelopeV2::record_digest(
  self : AuthorizationEventEnvelopeV2,
) -> @contracts.ContentDigest {
  self.record_digest
}

///|
pub fn AuthorizationEventEnvelopeV2::causation(
  self : AuthorizationEventEnvelopeV2,
) -> @contracts.ContentDigest {
  self.causation
}

///|
pub fn AuthorizationEventEnvelopeV2::previous_digest(
  self : AuthorizationEventEnvelopeV2,
) -> @contracts.ContentDigest {
  self.previous_digest
}

///|
pub fn AuthorizationEventEnvelopeV2::payload(
  self : AuthorizationEventEnvelopeV2,
) -> Bytes {
  self.payload
}

///|
pub fn AuthorizationEventEnvelopeV2::canonical_bytes(
  self : AuthorizationEventEnvelopeV2,
) -> Bytes {
  self.canonical
}

///|
pub struct AuthorizationEventStoreV2 {
  events_ : Array[AuthorizationEventEnvelopeV2]
  frames_ : Array[Bytes]
}

///|
pub fn AuthorizationEventStoreV2::new() -> AuthorizationEventStoreV2 {
  { events_: [], frames_: [] }
}

///|
fn expected_kind_v2(position : Int) -> AuthorizationEventKindV2 {
  match position {
    0 => PreDispatchAuthorizationCommittedV2
    1 => AuthorizedAttemptRegistrationCommittedV2
    2 => AuthorizedEffectIntentCommittedV2
    _ => EligibleAuthorizationProofCommittedV2
  }
}

///|
pub fn AuthorizationEventStoreV2::append(
  self : AuthorizationEventStoreV2,
  event : AuthorizationEventEnvelopeV2,
) -> Result[Bool, AuthorizationError] {
  let n = self.events_.length()
  if n > 0 {
    let tail = self.events_[n - 1]
    if event.event_ref().id() == tail.event_ref().id() {
      if event.canonical_bytes() == tail.canonical_bytes() {
        return Ok(false)
      }
      return Err(ReplayConflict("conflicting tail identity"))
    }
  }
  for old in self.events_ {
    if old.event_ref().id() == event.event_ref().id() {
      return Err(ReplayConflict("repeated non-tail identity"))
    }
  }
  guard n < 4 && event.kind() == expected_kind_v2(n) else {
    return Err(ReplayConflict("invalid event kind order"))
  }
  guard event.sequence() == n.to_int64() && event.revision() == n.to_int64() else {
    return Err(ReplayConflict("noncontiguous position"))
  }
  let prior = if n == 0 {
    authorization_event_genesis_digest_v2
  } else {
    self.events_[n - 1].event_digest()
  }
  guard event.previous_digest() == prior && event.causation() == prior else {
    return Err(ReplayConflict("invalid event chain"))
  }
  self.events_.push(event)
  self.frames_.push(event.canonical_bytes())
  Ok(true)
}

///|
pub fn AuthorizationEventStoreV2::events(
  self : AuthorizationEventStoreV2,
) -> Array[AuthorizationEventEnvelopeV2] {
  self.events_.copy()
}

///|
pub fn AuthorizationEventStoreV2::frames(
  self : AuthorizationEventStoreV2,
) -> Array[Bytes] {
  self.frames_.copy()
}

///|
/// Recovery remains fail-closed until the strict raw-frame reader is linked in.
pub fn recover_v2_store(
  durable_frames : Array[Bytes],
) -> Result[AuthorizationEventStoreV2, AuthorizationError] {
  let store = AuthorizationEventStoreV2::new()
  for i, frame in durable_frames {
    let event = match decode_authorization_event_envelope_v2(frame) {
      Ok(event) => event
      Err(err) => return Err(err)
    }
    match store.append(event) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    guard store.frames()[i] == frame else {
      return Err(CanonicalCodecError("durable frame mismatch"))
    }
  }
  Ok(store)
}
