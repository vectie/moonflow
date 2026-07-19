///|
/// FLOW-6C Slice A: neutral, immutable authorization records.
pub struct ReplayPosition {
  event_ref : @contracts.RecordRef
  sequence : Int64
  revision : Int64
  event_digest : @contracts.ContentDigest
} derive(Eq)

///|
pub fn ReplayPosition::new(
  event_ref : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  event_digest : @contracts.ContentDigest,
) -> Result[ReplayPosition, AuthorizationError] {
  guard sequence >= 0L else { return Err(Negative("sequence")) }
  guard revision >= 0L else { return Err(Negative("revision")) }
  guard event_ref.digest() == event_digest else {
    return Err(ContentReferenceMismatch("event"))
  }
  Ok({ event_ref, sequence, revision, event_digest })
}

///|
pub fn ReplayPosition::event_ref(self : ReplayPosition) -> @contracts.RecordRef {
  self.event_ref
}

///|
pub fn ReplayPosition::sequence(self : ReplayPosition) -> Int64 {
  self.sequence
}

///|
pub fn ReplayPosition::revision(self : ReplayPosition) -> Int64 {
  self.revision
}

///|
pub fn ReplayPosition::event_digest(
  self : ReplayPosition,
) -> @contracts.ContentDigest {
  self.event_digest
}

///|
pub struct ProducerDescriptor {
  contract_id : String
  contract_version : String
  record_ref : @contracts.RecordRef
  record_digest : @contracts.ContentDigest
} derive(Eq)

///|
pub fn ProducerDescriptor::new(
  contract_id : String,
  contract_version : String,
  record_ref : @contracts.RecordRef,
  record_digest : @contracts.ContentDigest,
) -> Result[ProducerDescriptor, AuthorizationError] {
  guard nonblank(contract_id, "contract_id") is Ok(_) else {
    return Err(Blank("contract_id"))
  }
  guard nonblank(contract_version, "contract_version") is Ok(_) else {
    return Err(Blank("contract_version"))
  }
  guard record_ref.digest() == record_digest else {
    return Err(ContentReferenceMismatch("producer"))
  }
  Ok({ contract_id, contract_version, record_ref, record_digest })
}

///|
pub fn ProducerDescriptor::contract_id(self : ProducerDescriptor) -> String {
  self.contract_id
}

///|
pub fn ProducerDescriptor::contract_version(
  self : ProducerDescriptor,
) -> String {
  self.contract_version
}

///|
pub fn ProducerDescriptor::record_ref(
  self : ProducerDescriptor,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn ProducerDescriptor::record_digest(
  self : ProducerDescriptor,
) -> @contracts.ContentDigest {
  self.record_digest
}

///|
pub struct AuthorizationGovernanceBinding {
  decision_ref : @contracts.RecordRef
  decision_digest : @contracts.ContentDigest
  policy_ref : @contracts.RecordRef
  policy_digest : @contracts.ContentDigest
  governed_subject : @contracts.RecordRef
  valid_from_inclusive : Int64
  valid_until_inclusive : Int64
} derive(Eq)

///|
pub fn AuthorizationGovernanceBinding::new(
  decision_ref : @contracts.RecordRef,
  decision_digest : @contracts.ContentDigest,
  policy_ref : @contracts.RecordRef,
  policy_digest : @contracts.ContentDigest,
  governed_subject : @contracts.RecordRef,
  valid_from_inclusive : Int64,
  valid_until_inclusive : Int64,
) -> Result[AuthorizationGovernanceBinding, AuthorizationError] {
  guard decision_ref.digest() == decision_digest else {
    return Err(ContentReferenceMismatch("decision"))
  }
  guard policy_ref.digest() == policy_digest else {
    return Err(ContentReferenceMismatch("policy"))
  }
  guard valid_from_inclusive >= 0L else {
    return Err(Negative("valid_from_inclusive"))
  }
  guard valid_until_inclusive >= valid_from_inclusive else {
    return Err(InvalidInterval("governance"))
  }
  Ok({
    decision_ref,
    decision_digest,
    policy_ref,
    policy_digest,
    governed_subject,
    valid_from_inclusive,
    valid_until_inclusive,
  })
}

///|
pub fn AuthorizationGovernanceBinding::decision_ref(
  self : AuthorizationGovernanceBinding,
) -> @contracts.RecordRef {
  self.decision_ref
}

///|
pub fn AuthorizationGovernanceBinding::decision_digest(
  self : AuthorizationGovernanceBinding,
) -> @contracts.ContentDigest {
  self.decision_digest
}

///|
pub fn AuthorizationGovernanceBinding::policy_ref(
  self : AuthorizationGovernanceBinding,
) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn AuthorizationGovernanceBinding::policy_digest(
  self : AuthorizationGovernanceBinding,
) -> @contracts.ContentDigest {
  self.policy_digest
}

///|
pub fn AuthorizationGovernanceBinding::governed_subject(
  self : AuthorizationGovernanceBinding,
) -> @contracts.RecordRef {
  self.governed_subject
}

///|
pub fn AuthorizationGovernanceBinding::valid_from_inclusive(
  self : AuthorizationGovernanceBinding,
) -> Int64 {
  self.valid_from_inclusive
}

///|
pub fn AuthorizationGovernanceBinding::valid_until_inclusive(
  self : AuthorizationGovernanceBinding,
) -> Int64 {
  self.valid_until_inclusive
}

///|
pub fn AuthorizationGovernanceBinding::accepts(
  self : AuthorizationGovernanceBinding,
  clock : Int64,
) -> Bool {
  clock >= self.valid_from_inclusive && clock <= self.valid_until_inclusive
}

///|
pub struct EligibilityBinding {
  clock : Int64
  authoritative_head : ReplayPosition
} derive(Eq)

///|
pub fn EligibilityBinding::new(
  clock : Int64,
  authoritative_head : ReplayPosition,
) -> Result[EligibilityBinding, AuthorizationError] {
  guard clock >= 0L else { return Err(Negative("clock")) }
  Ok({ clock, authoritative_head })
}

///|
pub fn EligibilityBinding::clock(self : EligibilityBinding) -> Int64 {
  self.clock
}

///|
pub fn EligibilityBinding::authoritative_head(
  self : EligibilityBinding,
) -> ReplayPosition {
  self.authoritative_head
}

///|
pub struct PlannedEffectTuple {
  workflow : @contracts.RecordRef
  subject : @contracts.RecordRef
  logical_attempt_id : String
  logical_attempt_version : String
  logical_effect_id : String
  logical_effect_version : String
  next_ordinal : Int64
  external_idempotency : String
  requested_work_ref : @contracts.RecordRef
  requested_work_digest : @contracts.ContentDigest
  effect_request_ref : @contracts.RecordRef
  effect_request_digest : @contracts.ContentDigest
  artifact_digest : @contracts.ContentDigest
} derive(Eq)

///|
pub fn PlannedEffectTuple::new(
  workflow : @contracts.RecordRef,
  subject : @contracts.RecordRef,
  logical_attempt_id : String,
  logical_attempt_version : String,
  logical_effect_id : String,
  logical_effect_version : String,
  next_ordinal : Int64,
  external_idempotency : String,
  requested_work_ref : @contracts.RecordRef,
  requested_work_digest : @contracts.ContentDigest,
  effect_request_ref : @contracts.RecordRef,
  effect_request_digest : @contracts.ContentDigest,
  artifact_digest : @contracts.ContentDigest,
) -> Result[PlannedEffectTuple, AuthorizationError] {
  for
    pair in [
      (logical_attempt_id, "logical_attempt_id"),
      (logical_attempt_version, "logical_attempt_version"),
      (logical_effect_id, "logical_effect_id"),
      (logical_effect_version, "logical_effect_version"),
      (external_idempotency, "external_idempotency"),
    ] {
    guard nonblank(pair.0, pair.1) is Ok(_) else { return Err(Blank(pair.1)) }
  }
  guard next_ordinal > 0L else { return Err(Negative("next_ordinal")) }
  guard requested_work_ref.digest() == requested_work_digest else {
    return Err(ContentReferenceMismatch("requested_work"))
  }
  guard effect_request_ref.digest() == effect_request_digest else {
    return Err(ContentReferenceMismatch("effect_request"))
  }
  Ok({
    workflow,
    subject,
    logical_attempt_id,
    logical_attempt_version,
    logical_effect_id,
    logical_effect_version,
    next_ordinal,
    external_idempotency,
    requested_work_ref,
    requested_work_digest,
    effect_request_ref,
    effect_request_digest,
    artifact_digest,
  })
}

///|
pub fn PlannedEffectTuple::workflow(
  self : PlannedEffectTuple,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn PlannedEffectTuple::subject(
  self : PlannedEffectTuple,
) -> @contracts.RecordRef {
  self.subject
}

///|
pub fn PlannedEffectTuple::logical_attempt_id(
  self : PlannedEffectTuple,
) -> String {
  self.logical_attempt_id
}

///|
pub fn PlannedEffectTuple::logical_attempt_version(
  self : PlannedEffectTuple,
) -> String {
  self.logical_attempt_version
}

///|
pub fn PlannedEffectTuple::logical_effect_id(
  self : PlannedEffectTuple,
) -> String {
  self.logical_effect_id
}

///|
pub fn PlannedEffectTuple::logical_effect_version(
  self : PlannedEffectTuple,
) -> String {
  self.logical_effect_version
}

///|
pub fn PlannedEffectTuple::next_ordinal(self : PlannedEffectTuple) -> Int64 {
  self.next_ordinal
}

///|
pub fn PlannedEffectTuple::external_idempotency(
  self : PlannedEffectTuple,
) -> String {
  self.external_idempotency
}

///|
pub fn PlannedEffectTuple::requested_work_ref(
  self : PlannedEffectTuple,
) -> @contracts.RecordRef {
  self.requested_work_ref
}

///|
pub fn PlannedEffectTuple::requested_work_digest(
  self : PlannedEffectTuple,
) -> @contracts.ContentDigest {
  self.requested_work_digest
}

///|
pub fn PlannedEffectTuple::effect_request_ref(
  self : PlannedEffectTuple,
) -> @contracts.RecordRef {
  self.effect_request_ref
}

///|
pub fn PlannedEffectTuple::effect_request_digest(
  self : PlannedEffectTuple,
) -> @contracts.ContentDigest {
  self.effect_request_digest
}

///|
pub fn PlannedEffectTuple::artifact_digest(
  self : PlannedEffectTuple,
) -> @contracts.ContentDigest {
  self.artifact_digest
}

///|
pub struct CapabilityBinding {
  capability_ref : @contracts.RecordRef
  capability_digest : @contracts.ContentDigest
} derive(Eq)

///|
pub fn CapabilityBinding::new(
  capability_ref : @contracts.RecordRef,
  capability_digest : @contracts.ContentDigest,
) -> Result[CapabilityBinding, AuthorizationError] {
  guard capability_ref.digest() == capability_digest else {
    return Err(ContentReferenceMismatch("capability"))
  }
  Ok({ capability_ref, capability_digest })
}

///|
pub fn CapabilityBinding::capability_ref(
  self : CapabilityBinding,
) -> @contracts.RecordRef {
  self.capability_ref
}

///|
pub fn CapabilityBinding::capability_digest(
  self : CapabilityBinding,
) -> @contracts.ContentDigest {
  self.capability_digest
}

///|
pub struct FencingBinding {
  fencing_ref : @contracts.RecordRef
  lease_epoch : Int64
  fencing_token : Int64
} derive(Eq)

///|
pub fn FencingBinding::new(
  fencing_ref : @contracts.RecordRef,
  lease_epoch : Int64,
  fencing_token : Int64,
) -> Result[FencingBinding, AuthorizationError] {
  guard lease_epoch >= 0L else { return Err(Negative("lease_epoch")) }
  guard fencing_token >= 0L else { return Err(Negative("fencing_token")) }
  Ok({ fencing_ref, lease_epoch, fencing_token })
}

///|
pub fn FencingBinding::fencing_ref(
  self : FencingBinding,
) -> @contracts.RecordRef {
  self.fencing_ref
}

///|
pub fn FencingBinding::lease_epoch(self : FencingBinding) -> Int64 {
  self.lease_epoch
}

///|
pub fn FencingBinding::fencing_token(self : FencingBinding) -> Int64 {
  self.fencing_token
}

///|
pub struct EvidenceBinding {
  evidence_ref : @contracts.RecordRef
  evidence_digest : @contracts.ContentDigest
} derive(Eq)

///|
pub fn EvidenceBinding::new(
  evidence_ref : @contracts.RecordRef,
  evidence_digest : @contracts.ContentDigest,
) -> Result[EvidenceBinding, AuthorizationError] {
  guard evidence_ref.digest() == evidence_digest else {
    return Err(ContentReferenceMismatch("evidence"))
  }
  Ok({ evidence_ref, evidence_digest })
}

///|
pub fn EvidenceBinding::evidence_ref(
  self : EvidenceBinding,
) -> @contracts.RecordRef {
  self.evidence_ref
}

///|
pub fn EvidenceBinding::evidence_digest(
  self : EvidenceBinding,
) -> @contracts.ContentDigest {
  self.evidence_digest
}

///|
pub struct AuthorizationControls {
  capability : CapabilityBinding?
  evidence : ReadOnlyArray[EvidenceBinding]
  evidence_digest : @contracts.ContentDigest
  fencing : FencingBinding?
  not_before_inclusive : Int64?
  deadline_inclusive : Int64
} derive(Eq)

///|
pub fn AuthorizationControls::new(
  capability : CapabilityBinding?,
  evidence : ArrayView[EvidenceBinding],
  fencing : FencingBinding?,
  not_before_inclusive : Int64?,
  deadline_inclusive : Int64,
) -> Result[AuthorizationControls, AuthorizationError] {
  guard deadline_inclusive >= 0L else {
    return Err(Negative("deadline_inclusive"))
  }
  match not_before_inclusive {
    Some(value) => {
      guard value >= 0L else { return Err(Negative("not_before_inclusive")) }
      guard value <= deadline_inclusive else {
        return Err(InvalidInterval("dispatch"))
      }
    }
    None => ()
  }
  for i = 0; i < evidence.length(); i = i + 1 {
    for j = i + 1; j < evidence.length(); j = j + 1 {
      if evidence[i].evidence_ref == evidence[j].evidence_ref {
        return Err(DuplicateEvidence(evidence[i].evidence_ref.id()))
      }
    }
  }
  let copy : ReadOnlyArray[EvidenceBinding] = [ for item in evidence => item ]
  let writer = AuthorizationWriter::new()
  match writer.count(copy.length()) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  for item in copy {
    match writer.record_ref(item.evidence_ref) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    match writer.digest(item.evidence_digest) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  let evidence_digest = @contracts.sha256_digest(writer.finish())
  Ok({
    capability,
    evidence: copy,
    evidence_digest,
    fencing,
    not_before_inclusive,
    deadline_inclusive,
  })
}

///|
pub fn AuthorizationControls::capability(
  self : AuthorizationControls,
) -> CapabilityBinding? {
  self.capability
}

///|
pub fn AuthorizationControls::evidence(
  self : AuthorizationControls,
) -> Array[EvidenceBinding] {
  [
    for item in self.evidence => item
  ]
}

///|
pub fn AuthorizationControls::evidence_digest(
  self : AuthorizationControls,
) -> @contracts.ContentDigest {
  self.evidence_digest
}

///|
pub fn AuthorizationControls::fencing(
  self : AuthorizationControls,
) -> FencingBinding? {
  self.fencing
}

///|
pub fn AuthorizationControls::not_before_inclusive(
  self : AuthorizationControls,
) -> Int64? {
  self.not_before_inclusive
}

///|
pub fn AuthorizationControls::deadline_inclusive(
  self : AuthorizationControls,
) -> Int64 {
  self.deadline_inclusive
}

///|
pub fn AuthorizationControls::accepts(
  self : AuthorizationControls,
  clock : Int64,
) -> Bool {
  let after_start = match self.not_before_inclusive {
    Some(value) => clock >= value
    None => true
  }
  clock <= self.deadline_inclusive && after_start
}

///|
pub struct PreDispatchAuthorization {
  record_ref : @contracts.RecordRef
  record_digest : @contracts.ContentDigest
  producer : ProducerDescriptor
  governance : AuthorizationGovernanceBinding
  eligibility : EligibilityBinding
  planned : PlannedEffectTuple
  controls : AuthorizationControls
  canonical : Bytes
} derive(Eq)

///|
pub fn PreDispatchAuthorization::new(
  id : String,
  producer : ProducerDescriptor,
  governance : AuthorizationGovernanceBinding,
  eligibility : EligibilityBinding,
  planned : PlannedEffectTuple,
  controls : AuthorizationControls,
) -> Result[PreDispatchAuthorization, AuthorizationError] {
  guard nonblank(id, "id") is Ok(_) else { return Err(Blank("id")) }
  guard governance.governed_subject == planned.subject else {
    return Err(GovernanceMismatch("governed_subject"))
  }
  guard governance.accepts(eligibility.clock) else {
    return Err(OutsideGovernanceWindow)
  }
  guard controls.accepts(eligibility.clock) else {
    return Err(OutsideDispatchWindow)
  }
  let canonical : Bytes = match
    encode_authorization(producer, governance, eligibility, planned, controls) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let record_digest = @contracts.sha256_digest(canonical)
  let record_ref = @contracts.RecordRef::new(
    "pre-dispatch-authorization",
    id,
    contract_version,
    record_digest.text(),
  ) catch {
    _ => return Err(CanonicalCodecError("record_ref"))
  }
  Ok({
    record_ref,
    record_digest,
    producer,
    governance,
    eligibility,
    planned,
    controls,
    canonical,
  })
}

///|
pub fn PreDispatchAuthorization::canonical_bytes(
  self : PreDispatchAuthorization,
) -> Bytes {
  self.canonical.copy()
}

///|
pub fn PreDispatchAuthorization::record_ref(
  self : PreDispatchAuthorization,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn PreDispatchAuthorization::record_digest(
  self : PreDispatchAuthorization,
) -> @contracts.ContentDigest {
  self.record_digest
}

///|
pub fn PreDispatchAuthorization::producer(
  self : PreDispatchAuthorization,
) -> ProducerDescriptor {
  self.producer
}

///|
pub fn PreDispatchAuthorization::governance(
  self : PreDispatchAuthorization,
) -> AuthorizationGovernanceBinding {
  self.governance
}

///|
pub fn PreDispatchAuthorization::eligibility(
  self : PreDispatchAuthorization,
) -> EligibilityBinding {
  self.eligibility
}

///|
pub fn PreDispatchAuthorization::planned(
  self : PreDispatchAuthorization,
) -> PlannedEffectTuple {
  self.planned
}

///|
pub fn PreDispatchAuthorization::controls(
  self : PreDispatchAuthorization,
) -> AuthorizationControls {
  self.controls
}

///|
pub struct AuthorizationLink {
  authorization_ref : @contracts.RecordRef
  authorization_digest : @contracts.ContentDigest
  committed_position : ReplayPosition
} derive(Eq)

///|
pub fn AuthorizationLink::new(
  authorization_ref : @contracts.RecordRef,
  authorization_digest : @contracts.ContentDigest,
  committed_position : ReplayPosition,
) -> Result[AuthorizationLink, AuthorizationError] {
  guard authorization_ref.digest() == authorization_digest else {
    return Err(ContentReferenceMismatch("authorization"))
  }
  Ok({ authorization_ref, authorization_digest, committed_position })
}

///|
pub fn AuthorizationLink::authorization_ref(
  self : AuthorizationLink,
) -> @contracts.RecordRef {
  self.authorization_ref
}

///|
pub fn AuthorizationLink::authorization_digest(
  self : AuthorizationLink,
) -> @contracts.ContentDigest {
  self.authorization_digest
}

///|
pub fn AuthorizationLink::committed_position(
  self : AuthorizationLink,
) -> ReplayPosition {
  self.committed_position
}

///|
pub struct AuthorizedAttemptRegistration {
  record_ref : @contracts.RecordRef
  record_digest : @contracts.ContentDigest
  authorization : AuthorizationLink
  producer : ProducerDescriptor
  governance : AuthorizationGovernanceBinding
  eligibility : EligibilityBinding
  planned : PlannedEffectTuple
  controls : AuthorizationControls
  canonical : Bytes
} derive(Eq)

///|
pub fn AuthorizedAttemptRegistration::new(
  id : String,
  authorization : AuthorizationLink,
  producer : ProducerDescriptor,
  governance : AuthorizationGovernanceBinding,
  eligibility : EligibilityBinding,
  planned : PlannedEffectTuple,
  controls : AuthorizationControls,
) -> Result[AuthorizedAttemptRegistration, AuthorizationError] {
  guard nonblank(id, "id") is Ok(_) else { return Err(Blank("id")) }
  let canonical : Bytes = match
    encode_attempt(
      authorization, producer, governance, eligibility, planned, controls,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let record_digest = @contracts.sha256_digest(canonical)
  let record_ref = @contracts.RecordRef::new(
    "authorized-attempt-registration",
    id,
    contract_version,
    record_digest.text(),
  ) catch {
    _ => return Err(CanonicalCodecError("record_ref"))
  }
  Ok({
    record_ref,
    record_digest,
    authorization,
    producer,
    governance,
    eligibility,
    planned,
    controls,
    canonical,
  })
}

///|
pub fn AuthorizedAttemptRegistration::canonical_bytes(
  self : AuthorizedAttemptRegistration,
) -> Bytes {
  self.canonical.copy()
}

///|
pub fn AuthorizedAttemptRegistration::record_ref(
  self : AuthorizedAttemptRegistration,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn AuthorizedAttemptRegistration::record_digest(
  self : AuthorizedAttemptRegistration,
) -> @contracts.ContentDigest {
  self.record_digest
}

///|
pub fn AuthorizedAttemptRegistration::authorization(
  self : AuthorizedAttemptRegistration,
) -> AuthorizationLink {
  self.authorization
}

///|
pub fn AuthorizedAttemptRegistration::producer(
  self : AuthorizedAttemptRegistration,
) -> ProducerDescriptor {
  self.producer
}

///|
pub fn AuthorizedAttemptRegistration::governance(
  self : AuthorizedAttemptRegistration,
) -> AuthorizationGovernanceBinding {
  self.governance
}

///|
pub fn AuthorizedAttemptRegistration::eligibility(
  self : AuthorizedAttemptRegistration,
) -> EligibilityBinding {
  self.eligibility
}

///|
pub fn AuthorizedAttemptRegistration::planned(
  self : AuthorizedAttemptRegistration,
) -> PlannedEffectTuple {
  self.planned
}

///|
pub fn AuthorizedAttemptRegistration::controls(
  self : AuthorizedAttemptRegistration,
) -> AuthorizationControls {
  self.controls
}

///|
pub struct AttemptLink {
  attempt_ref : @contracts.RecordRef
  attempt_digest : @contracts.ContentDigest
  committed_position : ReplayPosition
} derive(Eq)

///|
pub fn AttemptLink::new(
  attempt_ref : @contracts.RecordRef,
  attempt_digest : @contracts.ContentDigest,
  committed_position : ReplayPosition,
) -> Result[AttemptLink, AuthorizationError] {
  guard attempt_ref.digest() == attempt_digest else {
    return Err(ContentReferenceMismatch("attempt"))
  }
  Ok({ attempt_ref, attempt_digest, committed_position })
}

///|
pub fn AttemptLink::attempt_ref(self : AttemptLink) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
pub fn AttemptLink::attempt_digest(
  self : AttemptLink,
) -> @contracts.ContentDigest {
  self.attempt_digest
}

///|
pub fn AttemptLink::committed_position(self : AttemptLink) -> ReplayPosition {
  self.committed_position
}

///|
pub struct AuthorizedEffectIntent {
  record_ref : @contracts.RecordRef
  record_digest : @contracts.ContentDigest
  authorization : AuthorizationLink
  attempt : AttemptLink
  producer : ProducerDescriptor
  governance : AuthorizationGovernanceBinding
  eligibility : EligibilityBinding
  planned : PlannedEffectTuple
  controls : AuthorizationControls
  canonical : Bytes
} derive(Eq)

///|
pub fn AuthorizedEffectIntent::new(
  id : String,
  authorization : AuthorizationLink,
  attempt : AttemptLink,
  producer : ProducerDescriptor,
  governance : AuthorizationGovernanceBinding,
  eligibility : EligibilityBinding,
  planned : PlannedEffectTuple,
  controls : AuthorizationControls,
) -> Result[AuthorizedEffectIntent, AuthorizationError] {
  guard nonblank(id, "id") is Ok(_) else { return Err(Blank("id")) }
  let canonical : Bytes = match
    encode_intent(
      authorization, attempt, producer, governance, eligibility, planned, controls,
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let record_digest = @contracts.sha256_digest(canonical)
  let record_ref = @contracts.RecordRef::new(
    "authorized-effect-intent",
    id,
    contract_version,
    record_digest.text(),
  ) catch {
    _ => return Err(CanonicalCodecError("record_ref"))
  }
  Ok({
    record_ref,
    record_digest,
    authorization,
    attempt,
    producer,
    governance,
    eligibility,
    planned,
    controls,
    canonical,
  })
}

///|
pub fn AuthorizedEffectIntent::canonical_bytes(
  self : AuthorizedEffectIntent,
) -> Bytes {
  self.canonical.copy()
}

///|
pub fn AuthorizedEffectIntent::record_ref(
  self : AuthorizedEffectIntent,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn AuthorizedEffectIntent::record_digest(
  self : AuthorizedEffectIntent,
) -> @contracts.ContentDigest {
  self.record_digest
}

///|
pub fn AuthorizedEffectIntent::authorization(
  self : AuthorizedEffectIntent,
) -> AuthorizationLink {
  self.authorization
}

///|
pub fn AuthorizedEffectIntent::attempt(
  self : AuthorizedEffectIntent,
) -> AttemptLink {
  self.attempt
}

///|
pub fn AuthorizedEffectIntent::producer(
  self : AuthorizedEffectIntent,
) -> ProducerDescriptor {
  self.producer
}

///|
pub fn AuthorizedEffectIntent::governance(
  self : AuthorizedEffectIntent,
) -> AuthorizationGovernanceBinding {
  self.governance
}

///|
pub fn AuthorizedEffectIntent::eligibility(
  self : AuthorizedEffectIntent,
) -> EligibilityBinding {
  self.eligibility
}

///|
pub fn AuthorizedEffectIntent::planned(
  self : AuthorizedEffectIntent,
) -> PlannedEffectTuple {
  self.planned
}

///|
pub fn AuthorizedEffectIntent::controls(
  self : AuthorizedEffectIntent,
) -> AuthorizationControls {
  self.controls
}

///|
pub struct AuthorizationProof {
  authorization : AuthorizationLink
  attempt : AttemptLink
  intent_ref : @contracts.RecordRef
  intent_digest : @contracts.ContentDigest
} derive(Eq)

///|
pub fn AuthorizationProof::new(
  authorization : AuthorizationLink,
  attempt : AttemptLink,
  intent_ref : @contracts.RecordRef,
  intent_digest : @contracts.ContentDigest,
) -> Result[AuthorizationProof, AuthorizationError] {
  guard intent_ref.digest() == intent_digest else {
    return Err(ContentReferenceMismatch("intent"))
  }
  Ok({ authorization, attempt, intent_ref, intent_digest })
}

///|
pub fn AuthorizationProof::authorization(
  self : AuthorizationProof,
) -> AuthorizationLink {
  self.authorization
}

///|
pub fn AuthorizationProof::attempt(self : AuthorizationProof) -> AttemptLink {
  self.attempt
}

///|
pub fn AuthorizationProof::intent_ref(
  self : AuthorizationProof,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn AuthorizationProof::intent_digest(
  self : AuthorizationProof,
) -> @contracts.ContentDigest {
  self.intent_digest
}

///|
pub struct EligibleAuthorizedIntent {
  intent : AuthorizedEffectIntent
  proof : AuthorizationProof
} derive(Eq)

///|
pub fn EligibleAuthorizedIntent::new(
  intent : AuthorizedEffectIntent,
  proof : AuthorizationProof,
) -> Result[EligibleAuthorizedIntent, AuthorizationError] {
  guard intent.record_ref == proof.intent_ref &&
    intent.record_digest == proof.intent_digest else {
    return Err(ProofMismatch("intent"))
  }
  guard intent.authorization == proof.authorization else {
    return Err(ProofMismatch("authorization"))
  }
  guard intent.attempt == proof.attempt else {
    return Err(ProofMismatch("attempt"))
  }
  Ok({ intent, proof })
}

///|
pub fn EligibleAuthorizedIntent::intent(
  self : EligibleAuthorizedIntent,
) -> AuthorizedEffectIntent {
  self.intent
}

///|
pub fn EligibleAuthorizedIntent::proof(
  self : EligibleAuthorizedIntent,
) -> AuthorizationProof {
  self.proof
}

///|
pub struct AuthorizationManifest {
  authorization_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
} derive(Eq)

///|
pub fn AuthorizationManifest::new(
  authorization_ref : @contracts.RecordRef,
  attempt_ref : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef,
) -> AuthorizationManifest {
  { authorization_ref, attempt_ref, intent_ref }
}

///|
pub fn AuthorizationManifest::authorization_ref(
  self : AuthorizationManifest,
) -> @contracts.RecordRef {
  self.authorization_ref
}

///|
pub fn AuthorizationManifest::attempt_ref(
  self : AuthorizationManifest,
) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
pub fn AuthorizationManifest::intent_ref(
  self : AuthorizationManifest,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub struct AuthorizedDispatchEnvelope {
  eligible : EligibleAuthorizedIntent
  manifest : AuthorizationManifest
} derive(Eq)

///|
pub fn AuthorizedDispatchEnvelope::new(
  eligible : EligibleAuthorizedIntent,
  manifest : AuthorizationManifest,
) -> Result[AuthorizedDispatchEnvelope, AuthorizationError] {
  guard eligible.intent.record_ref == manifest.intent_ref else {
    return Err(ProofMismatch("manifest.intent"))
  }
  guard eligible.intent.authorization.authorization_ref ==
    manifest.authorization_ref else {
    return Err(ProofMismatch("manifest.authorization"))
  }
  guard eligible.intent.attempt.attempt_ref == manifest.attempt_ref else {
    return Err(ProofMismatch("manifest.attempt"))
  }
  Ok({ eligible, manifest })
}

///|
pub fn AuthorizedDispatchEnvelope::eligible(
  self : AuthorizedDispatchEnvelope,
) -> EligibleAuthorizedIntent {
  self.eligible
}

///|
pub fn AuthorizedDispatchEnvelope::manifest(
  self : AuthorizedDispatchEnvelope,
) -> AuthorizationManifest {
  self.manifest
}
