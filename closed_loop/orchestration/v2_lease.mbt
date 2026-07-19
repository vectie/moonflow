///|
/// A canonical FLOW-7 V2 lease claim.
pub struct LeaseClaimV2 {
  state_ref : @contracts.RecordRef
  schedule_ref : @contracts.RecordRef
  schedule_digest : @contracts.ContentDigest
  admission_ref : @contracts.RecordRef
  admission_digest : @contracts.ContentDigest
  intent_ref : @contracts.RecordRef
  intent_digest : @contracts.ContentDigest
  workflow : @contracts.RecordRef
  owner : @contracts.RecordRef
  observed_at : Int64
  expires_at : Int64
  epoch : Int64
  fencing_token : Int64
  idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn require_lease_evidence_v2(
  evidence : Array[@contracts.EvidenceRef],
  controls_evidence : Array[@effects_authorization.EvidenceBinding],
) -> Array[@contracts.EvidenceRef] raise OrchestrationError {
  let frozen = evidence.copy()
  if frozen.is_empty() {
    raise EvidenceMismatch(field="lease_evidence_empty")
  }
  for index, item in frozen {
    if frozen[:index].any(prior => prior == item) {
      raise EvidenceMismatch(field="lease_evidence_duplicate")
    }
  }
  if frozen.length() != controls_evidence.length() {
    raise EvidenceMismatch(field="lease_evidence_controls")
  }
  for index, item in frozen {
    let control = controls_evidence[index]
    if item.record() != control.evidence_ref() ||
      item.observed_digest() != control.evidence_digest() {
      raise EvidenceMismatch(field="lease_evidence_controls")
    }
  }
  frozen
}

///|
fn lease_deadline_v2(
  schedule : ScheduleIntentV2,
  admission : AdmissionV2,
) -> Int64 {
  let mut deadline = admission.governance().valid_until_inclusive()
  let controls_deadline = admission.controls().deadline_inclusive()
  if controls_deadline < deadline {
    deadline = controls_deadline
  }
  match schedule.deadline() {
    Some(schedule_deadline) =>
      if schedule_deadline < deadline {
        schedule_deadline
      } else {
        deadline
      }
    None => deadline
  }
}

///|
pub fn LeaseClaimV2::new(
  claim_id : String,
  schedule : ScheduleIntentV2,
  admission : AdmissionV2,
  workflow : @contracts.RecordRef,
  owner : @contracts.RecordRef,
  ttl : Int64,
  prior_epoch_floor : Int64,
  prior_fencing_floor : Int64,
  next_epoch : Int64,
  next_fencing_token : Int64,
  idempotency_key : String,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
) -> LeaseClaimV2 raise OrchestrationError {
  require_text(claim_id, "lease_claim_v2_id")
  require_text(idempotency_key, "lease_claim_v2_idempotency_key")
  if schedule.workflow() != workflow {
    raise IdentityMismatch(field="lease_claim_v2_workflow")
  }
  let scheduled_admission = schedule.admission()
  if scheduled_admission.proof_ref() != admission.proof_ref() ||
    scheduled_admission.proof_digest() != admission.proof_digest() ||
    scheduled_admission.intent_ref() != admission.intent_ref() ||
    scheduled_admission.intent_digest() != admission.intent_digest() {
    raise IdentityMismatch(field="lease_claim_v2_admission")
  }
  let observed_at = admission.eligibility().clock()
  if !admission.governance().accepts(observed_at) ||
    !admission.controls().accepts(observed_at) {
    raise AuthorityExpired(
      expires_at=admission.controls().deadline_inclusive(),
      observed_at~,
    )
  }
  if observed_at < schedule.not_before() {
    raise ScheduleStateViolation(field="lease_claim_v2_before_due")
  }
  if ttl <= 0L {
    raise TtlViolation(field="lease_claim_v2_ttl")
  }
  if observed_at > 9223372036854775807L - ttl {
    raise ArithmeticOverflow(field="lease_claim_v2_expiry")
  }
  let expires_at = observed_at + ttl
  let controls = admission.controls()
  let controls_fencing = match controls.fencing() {
    Some(fencing) => fencing
    None => raise EffectProofMismatch(field="lease_claim_v2_controls_fencing")
  }
  if prior_epoch_floor >= controls_fencing.lease_epoch() {
    raise LeaseEpochViolation(
      expected_greater_than=prior_epoch_floor,
      actual=controls_fencing.lease_epoch(),
    )
  }
  if prior_fencing_floor >= controls_fencing.fencing_token() {
    raise FencingViolation(
      expected_greater_than=prior_fencing_floor,
      actual=controls_fencing.fencing_token(),
    )
  }
  if next_epoch != controls_fencing.lease_epoch() {
    raise EffectProofMismatch(field="lease_claim_v2_controls_epoch")
  }
  if next_fencing_token != controls_fencing.fencing_token() {
    raise EffectProofMismatch(field="lease_claim_v2_controls_fencing_token")
  }
  let deadline = lease_deadline_v2(schedule, admission)
  if observed_at > deadline || expires_at > deadline {
    raise AuthorityExpired(expires_at=deadline, observed_at=expires_at)
  }
  let frozen_evidence = require_lease_evidence_v2(evidence, controls.evidence())
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-CLAIM-V2/2.1.0")
  writer.string(claim_id)
  write_ref(writer, schedule.schedule_ref())
  writer.string(schedule.digest().text())
  write_ref(writer, admission.proof_ref())
  writer.string(admission.proof_digest().text())
  write_ref(writer, admission.intent_ref())
  writer.string(admission.intent_digest().text())
  writer.string(controls.evidence_digest().text())
  write_ref(writer, controls_fencing.fencing_ref())
  writer.int64(controls_fencing.lease_epoch())
  writer.int64(controls_fencing.fencing_token())
  writer.optional_int64(controls.not_before_inclusive())
  writer.int64(controls.deadline_inclusive())
  write_ref(writer, workflow)
  write_ref(writer, owner)
  writer.int64(observed_at)
  writer.int64(expires_at)
  writer.int64(next_epoch)
  writer.int64(next_fencing_token)
  writer.string(idempotency_key)
  write_evidence(writer, frozen_evidence)
  write_ref(writer, causation)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    state_ref: self_ref_v2("orchestration-lease-claim-v2", claim_id, digest),
    schedule_ref: schedule.schedule_ref(),
    schedule_digest: schedule.digest(),
    admission_ref: admission.proof_ref(),
    admission_digest: admission.proof_digest(),
    intent_ref: admission.intent_ref(),
    intent_digest: admission.intent_digest(),
    workflow,
    owner,
    observed_at,
    expires_at,
    epoch: next_epoch,
    fencing_token: next_fencing_token,
    idempotency_key,
    evidence: ReadOnlyArray::from_array(frozen_evidence),
    causation,
    canonical,
    digest,
  }
}

///|
pub fn LeaseClaimV2::decode(
  expected_claim_id : String,
  schedule : ScheduleIntentV2,
  prior_epoch_floor : Int64,
  prior_fencing_floor : Int64,
  bytes : Bytes,
) -> LeaseClaimV2 raise OrchestrationError {
  require_text(expected_claim_id, "lease_claim_v2_id")
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/LEASE-CLAIM-V2/2.1.0" {
    raise MalformedInput(field="lease_claim_v2_tag")
  }
  let claim_id = reader.read_string()
  if claim_id != expected_claim_id {
    raise IdentityMismatch(field="lease_claim_v2_id")
  }
  let serialized_schedule_ref = reader.read_ref()
  let serialized_schedule_digest = reader.read_digest()
  let serialized_admission_ref = reader.read_ref()
  let serialized_admission_digest = reader.read_digest()
  let serialized_intent_ref = reader.read_ref()
  let serialized_intent_digest = reader.read_digest()
  let serialized_evidence_digest = reader.read_digest()
  let serialized_fencing_ref = reader.read_ref()
  let serialized_control_epoch = reader.read_int64()
  let serialized_control_token = reader.read_int64()
  let serialized_not_before = reader.read_optional_int64()
  let serialized_deadline = reader.read_int64()
  let workflow = reader.read_ref()
  let owner = reader.read_ref()
  let observed_at = reader.read_int64()
  let expires_at = reader.read_int64()
  let next_epoch = reader.read_int64()
  let next_fencing_token = reader.read_int64()
  let idempotency_key = reader.read_string()
  let evidence = reader.read_evidence()
  let causation = reader.read_ref()
  reader.require_end()
  if serialized_schedule_ref != schedule.schedule_ref() ||
    serialized_schedule_digest != schedule.digest() {
    raise IdentityMismatch(field="lease_claim_v2_schedule")
  }
  let admission = schedule.admission()
  if serialized_admission_ref != admission.proof_ref() ||
    serialized_admission_digest != admission.proof_digest() ||
    serialized_intent_ref != admission.intent_ref() ||
    serialized_intent_digest != admission.intent_digest() {
    raise IdentityMismatch(field="lease_claim_v2_admission")
  }
  let controls = admission.controls()
  if serialized_evidence_digest != controls.evidence_digest() ||
    serialized_not_before != controls.not_before_inclusive() ||
    serialized_deadline != controls.deadline_inclusive() {
    raise EffectProofMismatch(field="lease_claim_v2_controls")
  }
  let controls_fencing = match controls.fencing() {
    Some(value) => value
    None => raise EffectProofMismatch(field="lease_claim_v2_controls_fencing")
  }
  if serialized_fencing_ref != controls_fencing.fencing_ref() ||
    serialized_control_epoch != controls_fencing.lease_epoch() ||
    serialized_control_token != controls_fencing.fencing_token() {
    raise EffectProofMismatch(field="lease_claim_v2_controls_fencing")
  }
  if workflow != schedule.workflow() {
    raise IdentityMismatch(field="lease_claim_v2_workflow")
  }
  if observed_at < 0L || expires_at <= observed_at {
    raise TtlViolation(field="lease_claim_v2_expiry")
  }
  // Replay-derived floors are checked before constructor/control equality so
  // stale epoch and fencing bytes fail with their exact authority errors.
  if next_epoch <= prior_epoch_floor {
    raise LeaseEpochViolation(
      expected_greater_than=prior_epoch_floor,
      actual=next_epoch,
    )
  }
  if next_fencing_token <= prior_fencing_floor {
    raise FencingViolation(
      expected_greater_than=prior_fencing_floor,
      actual=next_fencing_token,
    )
  }
  let decoded = LeaseClaimV2::new(
    claim_id,
    schedule,
    admission,
    workflow,
    owner,
    expires_at - observed_at,
    prior_epoch_floor,
    prior_fencing_floor,
    next_epoch,
    next_fencing_token,
    idempotency_key,
    evidence,
    causation,
  )
  if decoded.expires_at() != expires_at || decoded.canonical_bytes() != bytes {
    raise DigestMismatch(field="lease_claim_v2_canonical")
  }
  decoded
}

///|
pub fn LeaseClaimV2::state_ref(self : LeaseClaimV2) -> @contracts.RecordRef {
  self.state_ref
}

///|
pub fn LeaseClaimV2::schedule_ref(self : LeaseClaimV2) -> @contracts.RecordRef {
  self.schedule_ref
}

///|
pub fn LeaseClaimV2::schedule_digest(
  self : LeaseClaimV2,
) -> @contracts.ContentDigest {
  self.schedule_digest
}

///|
pub fn LeaseClaimV2::admission_ref(self : LeaseClaimV2) -> @contracts.RecordRef {
  self.admission_ref
}

///|
pub fn LeaseClaimV2::admission_digest(
  self : LeaseClaimV2,
) -> @contracts.ContentDigest {
  self.admission_digest
}

///|
pub fn LeaseClaimV2::intent_ref(self : LeaseClaimV2) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn LeaseClaimV2::intent_digest(
  self : LeaseClaimV2,
) -> @contracts.ContentDigest {
  self.intent_digest
}

///|
pub fn LeaseClaimV2::workflow(self : LeaseClaimV2) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn LeaseClaimV2::owner(self : LeaseClaimV2) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn LeaseClaimV2::observed_at(self : LeaseClaimV2) -> Int64 {
  self.observed_at
}

///|
pub fn LeaseClaimV2::expires_at(self : LeaseClaimV2) -> Int64 {
  self.expires_at
}

///|
pub fn LeaseClaimV2::epoch(self : LeaseClaimV2) -> Int64 {
  self.epoch
}

///|
pub fn LeaseClaimV2::fencing_token(self : LeaseClaimV2) -> Int64 {
  self.fencing_token
}

///|
pub fn LeaseClaimV2::idempotency_key(self : LeaseClaimV2) -> String {
  self.idempotency_key
}

///|
pub fn LeaseClaimV2::evidence(
  self : LeaseClaimV2,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn LeaseClaimV2::causation(self : LeaseClaimV2) -> @contracts.RecordRef {
  self.causation
}

///|
pub fn LeaseClaimV2::canonical_bytes(self : LeaseClaimV2) -> Bytes {
  self.canonical
}

///|
pub fn LeaseClaimV2::digest(self : LeaseClaimV2) -> @contracts.ContentDigest {
  self.digest
}
