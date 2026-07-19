///|
/// Immutable FLOW-7 V2 admission, derived exclusively from a decoded V2 proof.
pub struct AdmissionV2 {
  proof : @effects_authorization.EligibleAuthorizationProofV2
  proof_bytes : Bytes
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn AdmissionV2::decode(
  expected_id : String,
  bytes : Bytes,
) -> AdmissionV2 raise OrchestrationError {
  let proof = match
    @effects_authorization.decode_eligible_authorization_proof_v2(
      expected_id, bytes,
    ) {
    Ok(value) => value
    Err(_) => raise MalformedInput(field="eligible_authorization_proof_v2")
  }
  let frozen = proof.canonical_bytes()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/ADMISSION-V2/2.0.0")
  writer.bytes(frozen)
  let canonical = writer.finish()
  {
    proof,
    proof_bytes: frozen,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn AdmissionV2::proof(
  self : AdmissionV2,
) -> @effects_authorization.EligibleAuthorizationProofV2 {
  self.proof
}

///|
pub fn AdmissionV2::proof_bytes(self : AdmissionV2) -> Bytes {
  self.proof_bytes
}

///|
pub fn AdmissionV2::proof_ref(self : AdmissionV2) -> @contracts.RecordRef {
  self.proof.record_ref()
}

///|
pub fn AdmissionV2::proof_digest(
  self : AdmissionV2,
) -> @contracts.ContentDigest {
  self.proof.digest()
}

///|
pub fn AdmissionV2::authorization(
  self : AdmissionV2,
) -> @effects_authorization.AuthorizationLink {
  self.proof.authorization()
}

///|
pub fn AdmissionV2::attempt(
  self : AdmissionV2,
) -> @effects_authorization.AttemptLink {
  self.proof.attempt()
}

///|
pub fn AdmissionV2::intent_ref(self : AdmissionV2) -> @contracts.RecordRef {
  self.proof.intent_ref()
}

///|
pub fn AdmissionV2::intent_digest(
  self : AdmissionV2,
) -> @contracts.ContentDigest {
  self.proof.intent_digest()
}

///|
pub fn AdmissionV2::intent_position(
  self : AdmissionV2,
) -> @effects_authorization.ReplayPosition {
  self.proof.intent_position()
}

///|
pub fn AdmissionV2::producer(
  self : AdmissionV2,
) -> @effects_authorization.ProducerDescriptor {
  self.proof.producer()
}

///|
pub fn AdmissionV2::governance(
  self : AdmissionV2,
) -> @effects_authorization.AuthorizationGovernanceBinding {
  self.proof.governance()
}

///|
pub fn AdmissionV2::eligibility(
  self : AdmissionV2,
) -> @effects_authorization.EligibilityBinding {
  self.proof.eligibility()
}

///|
pub fn AdmissionV2::planned(
  self : AdmissionV2,
) -> @effects_authorization.PlannedEffectTuple {
  self.proof.planned()
}

///|
pub fn AdmissionV2::controls(
  self : AdmissionV2,
) -> @effects_authorization.AuthorizationControls {
  self.proof.controls()
}

///|
pub fn AdmissionV2::canonical_bytes(self : AdmissionV2) -> Bytes {
  self.canonical
}

///|
pub fn AdmissionV2::digest(self : AdmissionV2) -> @contracts.ContentDigest {
  self.digest
}
