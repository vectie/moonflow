///|
/// Strict version-tagged canonical codec shared by Slice A records.
priv struct AuthorizationWriter {
  buffer : @buffer.Buffer
}

///|
fn AuthorizationWriter::new() -> AuthorizationWriter {
  { buffer: Buffer() }
}

///|
fn AuthorizationWriter::byte(self : AuthorizationWriter, value : Byte) -> Unit {
  self.buffer.write_byte(value)
}

///|
fn AuthorizationWriter::count(
  self : AuthorizationWriter,
  value : Int,
) -> Result[Unit, AuthorizationError] {
  if value < 0 {
    return Err(CanonicalCodecError("negative length"))
  }
  self.buffer.write_uint_be(value.reinterpret_as_uint())
  Ok(())
}

///|
fn AuthorizationWriter::bytes(
  self : AuthorizationWriter,
  value : Bytes,
) -> Result[Unit, AuthorizationError] {
  match self.count(value.length()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.buffer.write_bytes(value)
  Ok(())
}

///|
fn AuthorizationWriter::string(
  self : AuthorizationWriter,
  value : String,
) -> Result[Unit, AuthorizationError] {
  self.bytes(@utf8.encode(value))
}

///|
fn AuthorizationWriter::int64(
  self : AuthorizationWriter,
  value : Int64,
) -> Unit {
  self.buffer.write_int64_be(value)
}

///|
fn AuthorizationWriter::digest(
  self : AuthorizationWriter,
  value : @contracts.ContentDigest,
) -> Result[Unit, AuthorizationError] {
  self.string(value.text())
}

///|
fn AuthorizationWriter::record_ref(
  self : AuthorizationWriter,
  value : @contracts.RecordRef,
) -> Result[Unit, AuthorizationError] {
  match self.string(value.kind()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.string(value.id()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.string(value.version().text()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.digest(value.digest())
}

///|
fn AuthorizationWriter::position(
  self : AuthorizationWriter,
  value : ReplayPosition,
) -> Result[Unit, AuthorizationError] {
  match self.record_ref(value.event_ref()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.int64(value.sequence())
  self.int64(value.revision())
  self.digest(value.event_digest())
}

///|
fn AuthorizationWriter::producer(
  self : AuthorizationWriter,
  value : ProducerDescriptor,
) -> Result[Unit, AuthorizationError] {
  match self.string(value.contract_id()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.string(value.contract_version()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.record_ref(value.record_ref()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.digest(value.record_digest())
}

///|
fn AuthorizationWriter::governance(
  self : AuthorizationWriter,
  value : AuthorizationGovernanceBinding,
) -> Result[Unit, AuthorizationError] {
  match self.record_ref(value.decision_ref()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.digest(value.decision_digest()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.record_ref(value.policy_ref()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.digest(value.policy_digest()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.record_ref(value.governed_subject()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.int64(value.valid_from_inclusive())
  self.int64(value.valid_until_inclusive())
  Ok(())
}

///|
fn AuthorizationWriter::eligibility(
  self : AuthorizationWriter,
  value : EligibilityBinding,
) -> Result[Unit, AuthorizationError] {
  self.int64(value.clock())
  self.position(value.authoritative_head())
}

///|
fn AuthorizationWriter::planned(
  self : AuthorizationWriter,
  value : PlannedEffectTuple,
) -> Result[Unit, AuthorizationError] {
  match self.record_ref(value.workflow()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.record_ref(value.subject()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.string(value.logical_attempt_id()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.string(value.logical_attempt_version()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.string(value.logical_effect_id()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.string(value.logical_effect_version()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.int64(value.next_ordinal())
  match self.string(value.external_idempotency()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.record_ref(value.requested_work_ref()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.digest(value.requested_work_digest()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.record_ref(value.effect_request_ref()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.digest(value.effect_request_digest()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.digest(value.artifact_digest())
}

///|
fn AuthorizationWriter::controls(
  self : AuthorizationWriter,
  value : AuthorizationControls,
) -> Result[Unit, AuthorizationError] {
  match value.capability() {
    None => self.byte(0)
    Some(v) => {
      self.byte(1)
      match self.record_ref(v.capability_ref()) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      match self.digest(v.capability_digest()) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    }
  }
  let evidence = value.evidence()
  match self.count(evidence.length()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  for item in evidence {
    match self.record_ref(item.evidence_ref()) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match self.digest(item.evidence_digest()) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  match self.digest(value.evidence_digest()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match value.fencing() {
    None => self.byte(0)
    Some(v) => {
      self.byte(1)
      match self.record_ref(v.fencing_ref()) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      self.int64(v.lease_epoch())
      self.int64(v.fencing_token())
    }
  }
  match value.not_before_inclusive() {
    None => self.byte(0)
    Some(v) => {
      self.byte(1)
      self.int64(v)
    }
  }
  self.int64(value.deadline_inclusive())
  Ok(())
}

///|
fn AuthorizationWriter::authorization_link(
  self : AuthorizationWriter,
  value : AuthorizationLink,
) -> Result[Unit, AuthorizationError] {
  match self.record_ref(value.authorization_ref()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.digest(value.authorization_digest()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.position(value.committed_position())
}

///|
fn AuthorizationWriter::attempt_link(
  self : AuthorizationWriter,
  value : AttemptLink,
) -> Result[Unit, AuthorizationError] {
  match self.record_ref(value.attempt_ref()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.digest(value.attempt_digest()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.position(value.committed_position())
}

///|
fn AuthorizationWriter::finish(self : AuthorizationWriter) -> Bytes {
  self.buffer.to_bytes()
}

///|
fn encode_authorization(
  producer : ProducerDescriptor,
  governance : AuthorizationGovernanceBinding,
  eligibility : EligibilityBinding,
  planned : PlannedEffectTuple,
  controls : AuthorizationControls,
) -> Result[Bytes, AuthorizationError] {
  let w = AuthorizationWriter::new()
  match w.string("flow6c/pre-dispatch-authorization/2.0.0") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.producer(producer) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.governance(governance) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.eligibility(eligibility) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.planned(planned) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.controls(controls) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(w.finish())
}

///|
fn encode_attempt(
  authorization : AuthorizationLink,
  producer : ProducerDescriptor,
  governance : AuthorizationGovernanceBinding,
  eligibility : EligibilityBinding,
  planned : PlannedEffectTuple,
  controls : AuthorizationControls,
) -> Result[Bytes, AuthorizationError] {
  let w = AuthorizationWriter::new()
  match w.string("flow6c/authorized-attempt-registration/2.0.0") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.authorization_link(authorization) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.producer(producer) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.governance(governance) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.eligibility(eligibility) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.planned(planned) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.controls(controls) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(w.finish())
}

///|
fn encode_intent(
  authorization : AuthorizationLink,
  attempt : AttemptLink,
  producer : ProducerDescriptor,
  governance : AuthorizationGovernanceBinding,
  eligibility : EligibilityBinding,
  planned : PlannedEffectTuple,
  controls : AuthorizationControls,
) -> Result[Bytes, AuthorizationError] {
  let w = AuthorizationWriter::new()
  match w.string("flow6c/authorized-effect-intent/2.0.0") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.authorization_link(authorization) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.attempt_link(attempt) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.producer(producer) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.governance(governance) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.eligibility(eligibility) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.planned(planned) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match w.controls(controls) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(w.finish())
}

///|
priv struct AuthorizationReader {
  data : Bytes
  mut offset : Int
}

///|
fn AuthorizationReader::new(data : Bytes) -> AuthorizationReader {
  { data, offset: 0 }
}

///|
fn AuthorizationReader::byte(
  self : AuthorizationReader,
) -> Result[Byte, AuthorizationError] {
  if self.offset >= self.data.length() {
    return Err(CanonicalCodecError("unexpected end"))
  }
  let value = self.data[self.offset]
  self.offset += 1
  Ok(value)
}

///|
fn AuthorizationReader::count(
  self : AuthorizationReader,
) -> Result[Int, AuthorizationError] {
  if self.data.length() - self.offset < 4 {
    return Err(CanonicalCodecError("truncated length"))
  }
  let a = match self.byte() {
    Ok(value) => value.to_int()
    Err(error) => return Err(error)
  }
  let b = match self.byte() {
    Ok(value) => value.to_int()
    Err(error) => return Err(error)
  }
  let c = match self.byte() {
    Ok(value) => value.to_int()
    Err(error) => return Err(error)
  }
  let d = match self.byte() {
    Ok(value) => value.to_int()
    Err(error) => return Err(error)
  }
  if a >= 128 {
    return Err(CanonicalCodecError("length out of range"))
  }
  Ok(a * 16777216 + b * 65536 + c * 256 + d)
}

///|
fn AuthorizationReader::bytes(
  self : AuthorizationReader,
) -> Result[Bytes, AuthorizationError] {
  let n = match self.count() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if n > self.data.length() - self.offset {
    return Err(CanonicalCodecError("truncated bytes"))
  }
  let start = self.offset
  self.offset += n
  Ok(self.data[start:self.offset].to_owned())
}

///|
fn AuthorizationReader::string(
  self : AuthorizationReader,
) -> Result[String, AuthorizationError] {
  let input = match self.bytes() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(@utf8.decode(input)) catch {
    _ => Err(CanonicalCodecError("invalid utf8"))
  }
}

///|
fn AuthorizationReader::int64(
  self : AuthorizationReader,
) -> Result[Int64, AuthorizationError] {
  if self.data.length() - self.offset < 8 {
    return Err(CanonicalCodecError("truncated int64"))
  }
  let a = self.data[self.offset].to_int64()
  let b = self.data[self.offset + 1].to_int64()
  let c = self.data[self.offset + 2].to_int64()
  let d = self.data[self.offset + 3].to_int64()
  let e = self.data[self.offset + 4].to_int64()
  let f = self.data[self.offset + 5].to_int64()
  let g = self.data[self.offset + 6].to_int64()
  let h = self.data[self.offset + 7].to_int64()
  self.offset += 8
  Ok(
    (a << 56) |
    (b << 48) |
    (c << 40) |
    (d << 32) |
    (e << 24) |
    (f << 16) |
    (g << 8) |
    h,
  )
}

///|
fn AuthorizationReader::digest(
  self : AuthorizationReader,
) -> Result[@contracts.ContentDigest, AuthorizationError] {
  let input = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(@contracts.ContentDigest::parse(input)) catch {
    _ => Err(CanonicalCodecError("digest"))
  }
}

///|
fn AuthorizationReader::record_ref(
  self : AuthorizationReader,
) -> Result[@contracts.RecordRef, AuthorizationError] {
  let kind = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let id = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let version = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let digest = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(@contracts.RecordRef::new(kind, id, version, digest)) catch {
    _ => Err(CanonicalCodecError("record ref"))
  }
}

///|
fn AuthorizationReader::position(
  self : AuthorizationReader,
) -> Result[ReplayPosition, AuthorizationError] {
  let event_ref : @contracts.RecordRef = match self.record_ref() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let sequence : Int64 = match self.int64() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let revision : Int64 = match self.int64() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let event_digest : @contracts.ContentDigest = match self.digest() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  ReplayPosition::new(event_ref, sequence, revision, event_digest)
}

///|
fn AuthorizationReader::producer(
  self : AuthorizationReader,
) -> Result[ProducerDescriptor, AuthorizationError] {
  let contract_id : String = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let contract_version : String = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let record_ref : @contracts.RecordRef = match self.record_ref() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let record_digest : @contracts.ContentDigest = match self.digest() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  ProducerDescriptor::new(
    contract_id, contract_version, record_ref, record_digest,
  )
}

///|
fn AuthorizationReader::governance(
  self : AuthorizationReader,
) -> Result[AuthorizationGovernanceBinding, AuthorizationError] {
  let decision_ref : @contracts.RecordRef = match self.record_ref() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let decision_digest : @contracts.ContentDigest = match self.digest() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let policy_ref : @contracts.RecordRef = match self.record_ref() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let policy_digest : @contracts.ContentDigest = match self.digest() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let governed_subject : @contracts.RecordRef = match self.record_ref() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let valid_from_inclusive : Int64 = match self.int64() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let valid_until_inclusive : Int64 = match self.int64() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  AuthorizationGovernanceBinding::new(
    decision_ref, decision_digest, policy_ref, policy_digest, governed_subject, valid_from_inclusive,
    valid_until_inclusive,
  )
}

///|
fn AuthorizationReader::eligibility(
  self : AuthorizationReader,
) -> Result[EligibilityBinding, AuthorizationError] {
  let clock : Int64 = match self.int64() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let authoritative_head : ReplayPosition = match self.position() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  EligibilityBinding::new(clock, authoritative_head)
}

///|
fn AuthorizationReader::planned(
  self : AuthorizationReader,
) -> Result[PlannedEffectTuple, AuthorizationError] {
  let workflow : @contracts.RecordRef = match self.record_ref() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let subject : @contracts.RecordRef = match self.record_ref() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let logical_attempt_id : String = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let logical_attempt_version : String = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let logical_effect_id : String = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let logical_effect_version : String = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let next_ordinal : Int64 = match self.int64() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let external_idempotency : String = match self.string() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let requested_work_ref : @contracts.RecordRef = match self.record_ref() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let requested_work_digest : @contracts.ContentDigest = match self.digest() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let effect_request_ref : @contracts.RecordRef = match self.record_ref() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let effect_request_digest : @contracts.ContentDigest = match self.digest() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let artifact_digest : @contracts.ContentDigest = match self.digest() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  PlannedEffectTuple::new(
    workflow, subject, logical_attempt_id, logical_attempt_version, logical_effect_id,
    logical_effect_version, next_ordinal, external_idempotency, requested_work_ref,
    requested_work_digest, effect_request_ref, effect_request_digest, artifact_digest,
  )
}

///|
fn AuthorizationReader::controls(
  self : AuthorizationReader,
) -> Result[AuthorizationControls, AuthorizationError] {
  let capability_marker = match self.byte() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let capability = match capability_marker {
    0 => None
    1 => {
      let record_ref = match self.record_ref() {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let digest = match self.digest() {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      match CapabilityBinding::new(record_ref, digest) {
        Err(error) => return Err(error)
        Ok(value) => Some(value)
      }
    }
    _ => return Err(CanonicalCodecError("capability marker"))
  }
  let count = match self.count() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let evidence : Array[EvidenceBinding] = []
  for _ in 0..<count {
    let record_ref = match self.record_ref() {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    let digest = match self.digest() {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    let binding = match EvidenceBinding::new(record_ref, digest) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    evidence.push(binding)
  }
  let claimed : @contracts.ContentDigest = match self.digest() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let fencing_marker = match self.byte() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let fencing = match fencing_marker {
    0 => None
    1 => {
      let record_ref = match self.record_ref() {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let first = match self.int64() {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let second = match self.int64() {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      match FencingBinding::new(record_ref, first, second) {
        Err(error) => return Err(error)
        Ok(value) => Some(value)
      }
    }
    _ => return Err(CanonicalCodecError("fencing marker"))
  }
  let not_before_marker = match self.byte() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let not_before = match not_before_marker {
    0 => None
    1 =>
      match self.int64() {
        Err(error) => return Err(error)
        Ok(value) => Some(value)
      }
    _ => return Err(CanonicalCodecError("timing marker"))
  }
  let deadline = match self.int64() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let controls = match
    AuthorizationControls::new(
      capability, evidence, fencing, not_before, deadline,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if controls.evidence_digest() != claimed {
    return Err(ContentReferenceMismatch("evidence digest"))
  }
  Ok(controls)
}

///|
fn AuthorizationReader::authorization_link(
  self : AuthorizationReader,
) -> Result[AuthorizationLink, AuthorizationError] {
  let record_ref = match self.record_ref() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let digest = match self.digest() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let position = match self.position() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  AuthorizationLink::new(record_ref, digest, position)
}

///|
fn AuthorizationReader::attempt_link(
  self : AuthorizationReader,
) -> Result[AttemptLink, AuthorizationError] {
  let record_ref = match self.record_ref() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let digest = match self.digest() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let position = match self.position() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  AttemptLink::new(record_ref, digest, position)
}

///|
fn AuthorizationReader::end(
  self : AuthorizationReader,
) -> Result[Unit, AuthorizationError] {
  if self.offset != self.data.length() {
    Err(CanonicalCodecError("trailing data"))
  } else {
    Ok(())
  }
}

///|
pub fn decode_pre_dispatch_authorization(
  id : String,
  bytes : Bytes,
) -> Result[PreDispatchAuthorization, AuthorizationError] {
  let r = AuthorizationReader::new(bytes)
  let tag = match r.string() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if tag != "flow6c/pre-dispatch-authorization/2.0.0" {
    return Err(CanonicalCodecError("version tag"))
  }
  let producer = match r.producer() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let governance = match r.governance() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let eligibility = match r.eligibility() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let planned = match r.planned() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let controls = match r.controls() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let value = match
    PreDispatchAuthorization::new(
      id, producer, governance, eligibility, planned, controls,
    ) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match r.end() {
    Err(e) => Err(e)
    Ok(_) => Ok(value)
  }
}

///|
pub fn decode_authorized_attempt_registration(
  id : String,
  bytes : Bytes,
) -> Result[AuthorizedAttemptRegistration, AuthorizationError] {
  let r = AuthorizationReader::new(bytes)
  let tag = match r.string() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if tag != "flow6c/authorized-attempt-registration/2.0.0" {
    return Err(CanonicalCodecError("version tag"))
  }
  let authorization = match r.authorization_link() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let producer = match r.producer() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let governance = match r.governance() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let eligibility = match r.eligibility() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let planned = match r.planned() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let controls = match r.controls() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let value = match
    AuthorizedAttemptRegistration::new(
      id, authorization, producer, governance, eligibility, planned, controls,
    ) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match r.end() {
    Err(e) => Err(e)
    Ok(_) => Ok(value)
  }
}

///|
pub fn decode_authorized_effect_intent(
  id : String,
  bytes : Bytes,
) -> Result[AuthorizedEffectIntent, AuthorizationError] {
  let r = AuthorizationReader::new(bytes)
  let tag = match r.string() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if tag != "flow6c/authorized-effect-intent/2.0.0" {
    return Err(CanonicalCodecError("version tag"))
  }
  let authorization = match r.authorization_link() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let attempt = match r.attempt_link() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let producer = match r.producer() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let governance = match r.governance() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let eligibility = match r.eligibility() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let planned = match r.planned() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let controls = match r.controls() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let value = match
    AuthorizedEffectIntent::new(
      id, authorization, attempt, producer, governance, eligibility, planned, controls,
    ) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match r.end() {
    Err(e) => Err(e)
    Ok(_) => Ok(value)
  }
}
