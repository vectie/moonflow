///|
/// Strict, fail-closed decoder for FLOW-6C V2 durable event frames.
priv struct V2EventReader {
  bytes : Bytes
  mut offset : Int
}

///|
fn V2EventReader::new(bytes : Bytes) -> V2EventReader {
  { bytes, offset: 0 }
}

///|
fn V2EventReader::remaining(self : V2EventReader) -> Int {
  self.bytes.length() - self.offset
}

///|
fn V2EventReader::byte(
  self : V2EventReader,
) -> Result[Byte, AuthorizationError] {
  guard self.remaining() >= 1 else {
    return Err(CanonicalCodecError("truncated byte"))
  }
  let value = self.bytes[self.offset]
  self.offset = self.offset + 1
  Ok(value)
}

///|
fn V2EventReader::count(
  self : V2EventReader,
) -> Result[Int, AuthorizationError] {
  guard self.remaining() >= 4 else {
    return Err(CanonicalCodecError("truncated length"))
  }
  let b0 = self.bytes[self.offset].to_int()
  let b1 = self.bytes[self.offset + 1].to_int()
  let b2 = self.bytes[self.offset + 2].to_int()
  let b3 = self.bytes[self.offset + 3].to_int()
  self.offset = self.offset + 4
  guard b0 < 128 else { return Err(CanonicalCodecError("out-of-range length")) }
  let count = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
  guard count >= 0 && count <= self.remaining() else {
    return Err(CanonicalCodecError("truncated value"))
  }
  Ok(count)
}

///|
fn V2EventReader::bytes(
  self : V2EventReader,
) -> Result[Bytes, AuthorizationError] {
  let count = match self.count() {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let result = self.bytes[self.offset:self.offset + count].to_owned()
  self.offset = self.offset + count
  Ok(result)
}

///|
fn V2EventReader::string(
  self : V2EventReader,
) -> Result[String, AuthorizationError] {
  let value = match self.bytes() {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  Ok(@utf8.decode(value)) catch {
    _ => Err(CanonicalCodecError("invalid UTF-8"))
  }
}

///|
fn V2EventReader::int64(
  self : V2EventReader,
) -> Result[Int64, AuthorizationError] {
  guard self.remaining() >= 8 else {
    return Err(CanonicalCodecError("truncated int64"))
  }
  let mut value = 0UL
  for i = 0; i < 8; i = i + 1 {
    value = (value << 8) | self.bytes[self.offset + i].to_uint64()
  }
  self.offset = self.offset + 8
  Ok(value.reinterpret_as_int64())
}

///|
fn V2EventReader::digest(
  self : V2EventReader,
) -> Result[@contracts.ContentDigest, AuthorizationError] {
  let text = match self.string() {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  Ok(@contracts.ContentDigest::parse(text)) catch {
    _ => Err(CanonicalCodecError("invalid digest"))
  }
}

///|
fn V2EventReader::record_ref(
  self : V2EventReader,
) -> Result[@contracts.RecordRef, AuthorizationError] {
  let kind = match self.string() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let id = match self.string() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let version = match self.string() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let digest = match self.string() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok(@contracts.RecordRef::new(kind, id, version, digest)) catch {
    _ => Err(CanonicalCodecError("invalid record ref"))
  }
}

///|
fn V2EventReader::end(self : V2EventReader) -> Result[Unit, AuthorizationError] {
  guard self.offset == self.bytes.length() else {
    return Err(CanonicalCodecError("trailing bytes"))
  }
  Ok(())
}

///|
fn parse_authorization_event_kind_v2(
  value : String,
) -> Result[AuthorizationEventKindV2, AuthorizationError] {
  match value {
    "PreDispatchAuthorizationCommittedV2" =>
      Ok(PreDispatchAuthorizationCommittedV2)
    "AuthorizedAttemptRegistrationCommittedV2" =>
      Ok(AuthorizedAttemptRegistrationCommittedV2)
    "AuthorizedEffectIntentCommittedV2" => Ok(AuthorizedEffectIntentCommittedV2)
    "EligibleAuthorizationProofCommittedV2" =>
      Ok(EligibleAuthorizationProofCommittedV2)
    _ => Err(CanonicalCodecError("unknown v2 event kind"))
  }
}

///|
pub fn decode_authorization_event_envelope_v2(
  bytes : Bytes,
) -> Result[AuthorizationEventEnvelopeV2, AuthorizationError] {
  let r = V2EventReader::new(bytes)
  let version = match r.byte() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  guard version == 2 else {
    return Err(CanonicalCodecError("unknown codec version"))
  }
  let event_id = match r.string() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let kind_text = match r.string() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let kind = match parse_authorization_event_kind_v2(kind_text) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let contract = match r.string() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let schema = match r.string() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let record_ref = match r.record_ref() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let record_digest = match r.digest() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let sequence = match r.int64() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let revision = match r.int64() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let causation = match r.digest() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let previous_digest = match r.digest() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let payload = match r.bytes() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  match r.end() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let envelope = match
    AuthorizationEventEnvelopeV2::new(
      event_id, kind, contract, schema, record_ref, record_digest, sequence, revision,
      causation, previous_digest, payload,
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  guard envelope.canonical_bytes() == bytes else {
    return Err(CanonicalCodecError("non-canonical v2 event frame"))
  }
  Ok(envelope)
}
