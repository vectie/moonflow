///|
/// FLOW-6C V2 eligible authorization proof.
pub struct EligibleAuthorizationProofV2 {
  record_ref : @contracts.RecordRef
  digest : @contracts.ContentDigest
  authorization : AuthorizationLink
  attempt : AttemptLink
  intent_ref : @contracts.RecordRef
  intent_digest : @contracts.ContentDigest
  intent_position : ReplayPosition
  producer : ProducerDescriptor
  governance : AuthorizationGovernanceBinding
  eligibility : EligibilityBinding
  planned : PlannedEffectTuple
  controls : AuthorizationControls
  canonical_bytes : Bytes
} derive(Eq)

///|
/// FLOW-6C V2 proof and its committed event envelope.
pub struct EligibleAuthorizationProofCommitV2 {
  proof : EligibleAuthorizationProofV2
  event : AuthorizationEventEnvelopeV2
} derive(Eq)

///|
/// Canonically encode a FLOW-6C V2 eligible authorization proof.
fn encode_eligible_authorization_proof_v2(
  id : String,
  authorization : AuthorizationLink,
  attempt : AttemptLink,
  intent_ref : @contracts.RecordRef,
  intent_digest : @contracts.ContentDigest,
  intent_position : ReplayPosition,
  producer : ProducerDescriptor,
  governance : AuthorizationGovernanceBinding,
  eligibility : EligibilityBinding,
  planned : PlannedEffectTuple,
  controls : AuthorizationControls,
) -> Result[Bytes, AuthorizationError] {
  let writer = AuthorizationWriter::new()
  match writer.string("flow6c/eligible-authorization-proof-v2/2.0.0") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.string(id) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.authorization_link(authorization) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.attempt_link(attempt) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.record_ref(intent_ref) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.digest(intent_digest) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.position(intent_position) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.producer(producer) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.governance(governance) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.eligibility(eligibility) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.planned(planned) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match writer.controls(controls) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(writer.finish())
}

///|
fn new_eligible_authorization_proof_v2(
  id : String,
  authorization : AuthorizationLink,
  attempt : AttemptLink,
  intent_ref : @contracts.RecordRef,
  intent_digest : @contracts.ContentDigest,
  intent_position : ReplayPosition,
  producer : ProducerDescriptor,
  governance : AuthorizationGovernanceBinding,
  eligibility : EligibilityBinding,
  planned : PlannedEffectTuple,
  controls : AuthorizationControls,
) -> Result[EligibleAuthorizationProofV2, AuthorizationError] {
  if id.trim().is_empty() {
    return Err(
      CanonicalCodecError("eligible authorization proof id must not be blank"),
    )
  }
  if intent_ref.digest() != intent_digest {
    return Err(CanonicalCodecError("intent reference digest mismatch"))
  }
  if governance.governed_subject() != planned.subject() {
    return Err(
      CanonicalCodecError("governed subject does not match planned subject"),
    )
  }
  if !governance.accepts(eligibility.clock()) {
    return Err(
      CanonicalCodecError("eligibility clock is outside governance validity"),
    )
  }
  if !controls.accepts(eligibility.clock()) {
    return Err(
      CanonicalCodecError("eligibility clock is outside authorization controls"),
    )
  }
  let canonical_bytes = match
    encode_eligible_authorization_proof_v2(
      id, authorization, attempt, intent_ref, intent_digest, intent_position, producer,
      governance, eligibility, planned, controls,
    ) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let digest = @contracts.sha256_digest(canonical_bytes)
  let record_ref = @contracts.RecordRef::new(
    "eligible-authorization-proof-v2",
    id,
    contract_version,
    digest.text(),
  ) catch {
    _ =>
      return Err(
        CanonicalCodecError(
          "invalid eligible authorization proof record reference",
        ),
      )
  }
  Ok({
    record_ref,
    digest,
    authorization,
    attempt,
    intent_ref,
    intent_digest,
    intent_position,
    producer,
    governance,
    eligibility,
    planned,
    controls,
    canonical_bytes,
  })
}

///|
/// Strictly decode a canonical FLOW-6C V2 eligible authorization proof.
pub fn decode_eligible_authorization_proof_v2(
  id : String,
  bytes : Bytes,
) -> Result[EligibleAuthorizationProofV2, AuthorizationError] {
  let reader = AuthorizationReader::new(bytes)
  let tag = match reader.string() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  if tag != "flow6c/eligible-authorization-proof-v2/2.0.0" {
    return Err(CanonicalCodecError("noncanonical eligible authorization proof"))
  }
  let encoded_id = match reader.string() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  if encoded_id.trim().is_empty() {
    return Err(
      CanonicalCodecError("eligible authorization proof id must not be blank"),
    )
  }
  if encoded_id != id {
    return Err(
      CanonicalCodecError("eligible authorization proof identity mismatch"),
    )
  }
  let authorization = match reader.authorization_link() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let attempt = match reader.attempt_link() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let intent_ref = match reader.record_ref() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let intent_digest = match reader.digest() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let intent_position = match reader.position() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let producer = match reader.producer() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let governance = match reader.governance() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let eligibility = match reader.eligibility() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let planned = match reader.planned() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let controls = match reader.controls() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  match reader.end() {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let reconstructed = match
    new_eligible_authorization_proof_v2(
      id, authorization, attempt, intent_ref, intent_digest, intent_position, producer,
      governance, eligibility, planned, controls,
    ) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  if reconstructed.canonical_bytes() != bytes {
    return Err(CanonicalCodecError("noncanonical eligible authorization proof"))
  }
  Ok(reconstructed)
}

///|
pub fn EligibleAuthorizationProofV2::record_ref(
  self : EligibleAuthorizationProofV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn EligibleAuthorizationProofV2::digest(
  self : EligibleAuthorizationProofV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn EligibleAuthorizationProofV2::authorization(
  self : EligibleAuthorizationProofV2,
) -> AuthorizationLink {
  self.authorization
}

///|
pub fn EligibleAuthorizationProofV2::attempt(
  self : EligibleAuthorizationProofV2,
) -> AttemptLink {
  self.attempt
}

///|
pub fn EligibleAuthorizationProofV2::intent_ref(
  self : EligibleAuthorizationProofV2,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn EligibleAuthorizationProofV2::intent_digest(
  self : EligibleAuthorizationProofV2,
) -> @contracts.ContentDigest {
  self.intent_digest
}

///|
pub fn EligibleAuthorizationProofV2::intent_position(
  self : EligibleAuthorizationProofV2,
) -> ReplayPosition {
  self.intent_position
}

///|
pub fn EligibleAuthorizationProofV2::producer(
  self : EligibleAuthorizationProofV2,
) -> ProducerDescriptor {
  self.producer
}

///|
pub fn EligibleAuthorizationProofV2::governance(
  self : EligibleAuthorizationProofV2,
) -> AuthorizationGovernanceBinding {
  self.governance
}

///|
pub fn EligibleAuthorizationProofV2::eligibility(
  self : EligibleAuthorizationProofV2,
) -> EligibilityBinding {
  self.eligibility
}

///|
pub fn EligibleAuthorizationProofV2::planned(
  self : EligibleAuthorizationProofV2,
) -> PlannedEffectTuple {
  self.planned
}

///|
pub fn EligibleAuthorizationProofV2::controls(
  self : EligibleAuthorizationProofV2,
) -> AuthorizationControls {
  self.controls
}

///|
pub fn EligibleAuthorizationProofV2::canonical_bytes(
  self : EligibleAuthorizationProofV2,
) -> Bytes {
  self.canonical_bytes
}

///|
pub fn EligibleAuthorizationProofCommitV2::proof(
  self : EligibleAuthorizationProofCommitV2,
) -> EligibleAuthorizationProofV2 {
  self.proof
}

///|
pub fn EligibleAuthorizationProofCommitV2::event(
  self : EligibleAuthorizationProofCommitV2,
) -> AuthorizationEventEnvelopeV2 {
  self.event
}

///|
/// Whether this commit contains the given proof.
pub fn EligibleAuthorizationProofCommitV2::contains(
  self : EligibleAuthorizationProofCommitV2,
  proof : EligibleAuthorizationProofV2,
) -> Bool {
  self.proof == proof
}

///|
/// Derive the FLOW-6C proof commit from the complete three-event authorization chain.
pub fn derive_eligible_authorization_proof_commit_v2(
  store : AuthorizationEventStoreV2,
  proof_id : String,
  event_id : String,
) -> Result[EligibleAuthorizationProofCommitV2, AuthorizationError] {
  let events = store.events()
  if events.length() != 3 {
    return Err(CausalMismatch("event sequence"))
  }
  let authorization_event = events[0]
  let attempt_event = events[1]
  let intent_event = events[2]
  if authorization_event.kind() != PreDispatchAuthorizationCommittedV2 ||
    attempt_event.kind() != AuthorizedAttemptRegistrationCommittedV2 ||
    intent_event.kind() != AuthorizedEffectIntentCommittedV2 {
    return Err(CausalMismatch("event sequence"))
  }
  let authorization = match
    decode_pre_dispatch_authorization(
      authorization_event.record_ref().id(),
      authorization_event.payload(),
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let attempt = match
    decode_authorized_attempt_registration(
      attempt_event.record_ref().id(),
      attempt_event.payload(),
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let intent = match
    decode_authorized_effect_intent(
      intent_event.record_ref().id(),
      intent_event.payload(),
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  if authorization.record_ref() != authorization_event.record_ref() ||
    authorization.record_digest() != authorization_event.record_digest() ||
    authorization.canonical_bytes() != authorization_event.payload() ||
    attempt.record_ref() != attempt_event.record_ref() ||
    attempt.record_digest() != attempt_event.record_digest() ||
    attempt.canonical_bytes() != attempt_event.payload() ||
    intent.record_ref() != intent_event.record_ref() ||
    intent.record_digest() != intent_event.record_digest() ||
    intent.canonical_bytes() != intent_event.payload() {
    return Err(
      CanonicalCodecError("event envelope does not match decoded record"),
    )
  }
  let position0 = match
    ReplayPosition::new(
      authorization_event.event_ref(),
      authorization_event.sequence(),
      authorization_event.revision(),
      authorization_event.event_digest(),
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let position1 = match
    ReplayPosition::new(
      attempt_event.event_ref(),
      attempt_event.sequence(),
      attempt_event.revision(),
      attempt_event.event_digest(),
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let position2 = match
    ReplayPosition::new(
      intent_event.event_ref(),
      intent_event.sequence(),
      intent_event.revision(),
      intent_event.event_digest(),
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let expected_authorization = match
    AuthorizationLink::new(
      authorization.record_ref(),
      authorization.record_digest(),
      position0,
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let expected_attempt = match
    AttemptLink::new(attempt.record_ref(), attempt.record_digest(), position1) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  if attempt.authorization() != expected_authorization ||
    intent.authorization() != expected_authorization ||
    intent.attempt() != expected_attempt {
    return Err(CausalMismatch("event sequence"))
  }
  if authorization.producer() != attempt.producer() ||
    authorization.producer() != intent.producer() {
    return Err(ProducerMismatch("producer"))
  }
  if authorization.governance() != attempt.governance() ||
    authorization.governance() != intent.governance() {
    return Err(GovernanceMismatch("governance"))
  }
  if authorization.eligibility() != attempt.eligibility() ||
    authorization.eligibility() != intent.eligibility() {
    return Err(EligibilityMismatch("eligibility"))
  }
  if authorization.planned() != attempt.planned() ||
    authorization.planned() != intent.planned() {
    return Err(TupleMismatch("planned"))
  }
  if authorization.controls() != attempt.controls() ||
    authorization.controls() != intent.controls() ||
    authorization.controls().evidence_digest() !=
    attempt.controls().evidence_digest() ||
    authorization.controls().evidence_digest() !=
    intent.controls().evidence_digest() {
    return Err(ControlMismatch("controls"))
  }
  let governance = authorization.governance()
  let eligibility = authorization.eligibility()
  let planned = authorization.planned()
  let controls = authorization.controls()
  if governance.governed_subject() != planned.subject() {
    return Err(GovernanceMismatch("governed_subject"))
  }
  if !governance.accepts(eligibility.clock()) ||
    !controls.accepts(eligibility.clock()) {
    return Err(DispatchIneligible("clock"))
  }
  let proof = match
    new_eligible_authorization_proof_v2(
      proof_id,
      expected_authorization,
      expected_attempt,
      intent.record_ref(),
      intent.record_digest(),
      position2,
      authorization.producer(),
      governance,
      eligibility,
      planned,
      controls,
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let event = match
    AuthorizationEventEnvelopeV2::new(
      event_id,
      EligibleAuthorizationProofCommittedV2,
      contract_version,
      "FLOW-6C.authorization-event-envelope.v2",
      proof.record_ref(),
      proof.digest(),
      3L,
      3L,
      intent_event.event_digest(),
      intent_event.event_digest(),
      proof.canonical_bytes(),
    ) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  Ok({ proof, event })
}
