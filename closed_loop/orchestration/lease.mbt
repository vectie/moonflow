///|
pub struct LeaseClaim {
  record_version : @contracts.Version
  claim_ref : @contracts.RecordRef
  schedule_ref : @contracts.RecordRef
  schedule_digest : @contracts.ContentDigest
  workflow : @contracts.RecordRef
  owner_ref : @contracts.RecordRef
  clock : ClockInput
  ttl : Int64
  lease_epoch : Int64
  fencing_token : Int64
  claimed_at : Int64
  expires_at : Int64
  idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
pub fn LeaseClaim::new(
  claim_id : String,
  claim_version : String,
  due : DueProof,
  schedule : ScheduleIntent,
  owner_ref : @contracts.RecordRef,
  clock : ClockInput,
  ttl : Int64,
  lease_epoch : Int64,
  fencing_token : Int64,
  idempotency_key : String,
  evidence : Array[@contracts.EvidenceRef],
  causation_ref : @contracts.RecordRef,
  previous_digest : @contracts.ContentDigest,
) -> LeaseClaim raise OrchestrationError {
  require_version(claim_version, "lease_claim")
  require_text(claim_id, "claim_id")
  require_text(idempotency_key, "claim_idempotency_key")
  if due.schedule_ref != schedule.schedule_ref() ||
    due.schedule_digest != schedule.binding_digest() ||
    due.workflow != schedule.workflow() ||
    clock.workflow() != schedule.workflow() {
    raise IdentityMismatch(field="claim_due_proof")
  }
  if ttl <= 0L {
    raise TtlViolation(field="positive_ttl_required")
  }
  if lease_epoch <= 0L {
    raise LeaseEpochViolation(expected_greater_than=0L, actual=lease_epoch)
  }
  if fencing_token <= due.fencing_floor {
    raise FencingViolation(
      expected_greater_than=due.fencing_floor,
      actual=fencing_token,
    )
  }
  if clock.logical_instant() < schedule.not_before() {
    raise ScheduleStateViolation(field="claim_before_due")
  }
  match schedule.deadline() {
    Some(deadline) if clock.logical_instant() > deadline =>
      raise ScheduleStateViolation(field="claim_after_deadline")
    _ => ()
  }
  let expires_at = checked_add_non_negative(
    clock.logical_instant(),
    ttl,
    "claim_ttl",
  )
  let snapshot = evidence.copy()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7ACLAIM1")
  writer.string(claim_version)
  writer.string(claim_id)
  write_ref(writer, schedule.schedule_ref())
  writer.string(schedule.binding_digest().text())
  write_ref(writer, schedule.workflow())
  write_ref(writer, owner_ref)
  writer.bytes(clock.canonical_bytes())
  writer.int64(ttl)
  writer.int64(lease_epoch)
  writer.int64(fencing_token)
  writer.int64(clock.logical_instant())
  writer.int64(expires_at)
  writer.string(idempotency_key)
  write_evidence(writer, snapshot)
  write_ref(writer, causation_ref)
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_version: orchestration_version(),
    claim_ref: self_ref("orchestration-lease-claim", claim_id, digest),
    schedule_ref: schedule.schedule_ref(),
    schedule_digest: schedule.binding_digest(),
    workflow: schedule.workflow(),
    owner_ref,
    clock,
    ttl,
    lease_epoch,
    fencing_token,
    claimed_at: clock.logical_instant(),
    expires_at,
    idempotency_key,
    evidence: ReadOnlyArray::from_array(snapshot),
    causation_ref,
    previous_digest,
    canonical,
  }
}

///|
pub fn LeaseClaim::claim_ref(self : LeaseClaim) -> @contracts.RecordRef {
  self.claim_ref
}

///|
pub fn LeaseClaim::schedule_ref(self : LeaseClaim) -> @contracts.RecordRef {
  self.schedule_ref
}

///|
pub fn LeaseClaim::owner_ref(self : LeaseClaim) -> @contracts.RecordRef {
  self.owner_ref
}

///|
pub fn LeaseClaim::clock(self : LeaseClaim) -> ClockInput {
  self.clock
}

///|
pub fn LeaseClaim::ttl(self : LeaseClaim) -> Int64 {
  self.ttl
}

///|
pub fn LeaseClaim::lease_epoch(self : LeaseClaim) -> Int64 {
  self.lease_epoch
}

///|
pub fn LeaseClaim::fencing_token(self : LeaseClaim) -> Int64 {
  self.fencing_token
}

///|
pub fn LeaseClaim::claimed_at(self : LeaseClaim) -> Int64 {
  self.claimed_at
}

///|
pub fn LeaseClaim::expires_at(self : LeaseClaim) -> Int64 {
  self.expires_at
}

///|
pub fn LeaseClaim::idempotency_key(self : LeaseClaim) -> String {
  self.idempotency_key
}

///|
pub fn LeaseClaim::evidence(
  self : LeaseClaim,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn LeaseClaim::canonical_bytes(self : LeaseClaim) -> Bytes {
  self.canonical
}

///|
pub fn LeaseClaim::binding_digest(
  self : LeaseClaim,
) -> @contracts.ContentDigest {
  self.claim_ref.digest()
}

///|
pub impl Eq for LeaseClaim with fn equal(left, right) {
  left.canonical_bytes() == right.canonical_bytes()
}

///|
pub struct LeaseRenewal {
  record_version : @contracts.Version
  renewal_ref : @contracts.RecordRef
  claim_ref : @contracts.RecordRef
  schedule_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  owner_ref : @contracts.RecordRef
  clock : ClockInput
  ttl : Int64
  prior_expires_at : Int64
  expires_at : Int64
  lease_epoch : Int64
  fencing_token : Int64
  idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
pub fn LeaseRenewal::new(
  renewal_id : String,
  renewal_version : String,
  claim : LeaseClaim,
  active : ClaimedProof,
  clock : ClockInput,
  ttl : Int64,
  lease_epoch : Int64,
  fencing_token : Int64,
  idempotency_key : String,
  evidence : Array[@contracts.EvidenceRef],
  causation_ref : @contracts.RecordRef,
  previous_digest : @contracts.ContentDigest,
) -> LeaseRenewal raise OrchestrationError {
  require_version(renewal_version, "lease_renewal")
  require_text(renewal_id, "renewal_id")
  require_text(idempotency_key, "renewal_idempotency_key")
  if clock.workflow() != claim.workflow ||
    active.claim_ref != claim.claim_ref ||
    active.owner_ref != claim.owner_ref {
    raise WorkflowMismatch(field="renewal_clock_workflow")
  }
  if ttl <= 0L {
    raise TtlViolation(field="positive_ttl_required")
  }
  if clock.logical_instant() >= active.expires_at {
    raise ScheduleStateViolation(field="renewal_after_expiry")
  }
  if lease_epoch <= active.lease_epoch {
    raise LeaseEpochViolation(
      expected_greater_than=active.lease_epoch,
      actual=lease_epoch,
    )
  }
  if fencing_token <= active.fencing_token {
    raise FencingViolation(
      expected_greater_than=active.fencing_token,
      actual=fencing_token,
    )
  }
  let expires_at = checked_add_non_negative(
    clock.logical_instant(),
    ttl,
    "renewal_ttl",
  )
  if expires_at < active.expires_at {
    raise TtlViolation(field="renewal_reduces_expiry")
  }
  let snapshot = evidence.copy()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7ARENEW1")
  writer.string(renewal_version)
  writer.string(renewal_id)
  write_ref(writer, claim.claim_ref)
  write_ref(writer, claim.schedule_ref)
  write_ref(writer, claim.workflow)
  write_ref(writer, claim.owner_ref)
  writer.bytes(clock.canonical_bytes())
  writer.int64(ttl)
  writer.int64(active.expires_at)
  writer.int64(expires_at)
  writer.int64(lease_epoch)
  writer.int64(fencing_token)
  writer.string(idempotency_key)
  write_evidence(writer, snapshot)
  write_ref(writer, causation_ref)
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_version: orchestration_version(),
    renewal_ref: self_ref("orchestration-lease-renewal", renewal_id, digest),
    claim_ref: claim.claim_ref,
    schedule_ref: claim.schedule_ref,
    workflow: claim.workflow,
    owner_ref: claim.owner_ref,
    clock,
    ttl,
    prior_expires_at: active.expires_at,
    expires_at,
    lease_epoch,
    fencing_token,
    idempotency_key,
    evidence: ReadOnlyArray::from_array(snapshot),
    causation_ref,
    previous_digest,
    canonical,
  }
}

///|
pub fn LeaseRenewal::renewal_ref(self : LeaseRenewal) -> @contracts.RecordRef {
  self.renewal_ref
}

///|
pub fn LeaseRenewal::claim_ref(self : LeaseRenewal) -> @contracts.RecordRef {
  self.claim_ref
}

///|
pub fn LeaseRenewal::expires_at(self : LeaseRenewal) -> Int64 {
  self.expires_at
}

///|
pub fn LeaseRenewal::lease_epoch(self : LeaseRenewal) -> Int64 {
  self.lease_epoch
}

///|
pub fn LeaseRenewal::fencing_token(self : LeaseRenewal) -> Int64 {
  self.fencing_token
}

///|
pub fn LeaseRenewal::canonical_bytes(self : LeaseRenewal) -> Bytes {
  self.canonical
}

///|
pub fn LeaseRenewal::binding_digest(
  self : LeaseRenewal,
) -> @contracts.ContentDigest {
  self.renewal_ref.digest()
}

///|
pub struct LeaseRelease {
  record_version : @contracts.Version
  release_ref : @contracts.RecordRef
  claim_ref : @contracts.RecordRef
  schedule_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  owner_ref : @contracts.RecordRef
  clock : ClockInput
  lease_epoch : Int64
  fencing_token : Int64
  released_at : Int64
  idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
pub fn LeaseRelease::new(
  release_id : String,
  release_version : String,
  claim : LeaseClaim,
  active : ClaimedProof,
  clock : ClockInput,
  idempotency_key : String,
  evidence : Array[@contracts.EvidenceRef],
  causation_ref : @contracts.RecordRef,
  previous_digest : @contracts.ContentDigest,
) -> LeaseRelease raise OrchestrationError {
  require_version(release_version, "lease_release")
  require_text(release_id, "release_id")
  require_text(idempotency_key, "release_idempotency_key")
  if clock.workflow() != claim.workflow ||
    active.claim_ref != claim.claim_ref ||
    active.owner_ref != claim.owner_ref {
    raise WorkflowMismatch(field="release_clock_workflow")
  }
  if clock.logical_instant() >= active.expires_at {
    raise ScheduleStateViolation(field="release_after_expiry")
  }
  let snapshot = evidence.copy()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7ARELEASE1")
  writer.string(release_version)
  writer.string(release_id)
  write_ref(writer, claim.claim_ref)
  write_ref(writer, claim.schedule_ref)
  write_ref(writer, claim.workflow)
  write_ref(writer, claim.owner_ref)
  writer.bytes(clock.canonical_bytes())
  writer.int64(active.lease_epoch)
  writer.int64(active.fencing_token)
  writer.int64(clock.logical_instant())
  writer.string(idempotency_key)
  write_evidence(writer, snapshot)
  write_ref(writer, causation_ref)
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_version: orchestration_version(),
    release_ref: self_ref("orchestration-lease-release", release_id, digest),
    claim_ref: claim.claim_ref,
    schedule_ref: claim.schedule_ref,
    workflow: claim.workflow,
    owner_ref: claim.owner_ref,
    clock,
    lease_epoch: active.lease_epoch,
    fencing_token: active.fencing_token,
    released_at: clock.logical_instant(),
    idempotency_key,
    evidence: ReadOnlyArray::from_array(snapshot),
    causation_ref,
    previous_digest,
    canonical,
  }
}

///|
pub fn LeaseRelease::release_ref(self : LeaseRelease) -> @contracts.RecordRef {
  self.release_ref
}

///|
pub fn LeaseRelease::claim_ref(self : LeaseRelease) -> @contracts.RecordRef {
  self.claim_ref
}

///|
pub fn LeaseRelease::released_at(self : LeaseRelease) -> Int64 {
  self.released_at
}

///|
pub fn LeaseRelease::canonical_bytes(self : LeaseRelease) -> Bytes {
  self.canonical
}

///|
pub fn LeaseRelease::binding_digest(
  self : LeaseRelease,
) -> @contracts.ContentDigest {
  self.release_ref.digest()
}

///|
pub struct LeaseExpiry {
  record_version : @contracts.Version
  expiry_ref : @contracts.RecordRef
  claim_ref : @contracts.RecordRef
  schedule_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  owner_ref : @contracts.RecordRef
  clock : ClockInput
  lease_epoch : Int64
  fencing_token : Int64
  expires_at : Int64
  expired_at : Int64
  idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
pub fn LeaseExpiry::new(
  expiry_id : String,
  expiry_version : String,
  claim : LeaseClaim,
  active : ClaimedProof,
  clock : ClockInput,
  idempotency_key : String,
  evidence : Array[@contracts.EvidenceRef],
  causation_ref : @contracts.RecordRef,
  previous_digest : @contracts.ContentDigest,
) -> LeaseExpiry raise OrchestrationError {
  require_version(expiry_version, "lease_expiry")
  require_text(expiry_id, "expiry_id")
  require_text(idempotency_key, "expiry_idempotency_key")
  if clock.workflow() != claim.workflow ||
    active.claim_ref != claim.claim_ref ||
    active.owner_ref != claim.owner_ref {
    raise WorkflowMismatch(field="expiry_clock_workflow")
  }
  if clock.logical_instant() < active.expires_at {
    raise ScheduleStateViolation(field="expiry_before_expiration")
  }
  let snapshot = evidence.copy()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7AEXPIRY1")
  writer.string(expiry_version)
  writer.string(expiry_id)
  write_ref(writer, claim.claim_ref)
  write_ref(writer, claim.schedule_ref)
  write_ref(writer, claim.workflow)
  write_ref(writer, claim.owner_ref)
  writer.bytes(clock.canonical_bytes())
  writer.int64(active.lease_epoch)
  writer.int64(active.fencing_token)
  writer.int64(active.expires_at)
  writer.int64(clock.logical_instant())
  writer.string(idempotency_key)
  write_evidence(writer, snapshot)
  write_ref(writer, causation_ref)
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_version: orchestration_version(),
    expiry_ref: self_ref("orchestration-lease-expiry", expiry_id, digest),
    claim_ref: claim.claim_ref,
    schedule_ref: claim.schedule_ref,
    workflow: claim.workflow,
    owner_ref: claim.owner_ref,
    clock,
    lease_epoch: active.lease_epoch,
    fencing_token: active.fencing_token,
    expires_at: active.expires_at,
    expired_at: clock.logical_instant(),
    idempotency_key,
    evidence: ReadOnlyArray::from_array(snapshot),
    causation_ref,
    previous_digest,
    canonical,
  }
}

///|
pub fn LeaseExpiry::expiry_ref(self : LeaseExpiry) -> @contracts.RecordRef {
  self.expiry_ref
}

///|
pub fn LeaseExpiry::claim_ref(self : LeaseExpiry) -> @contracts.RecordRef {
  self.claim_ref
}

///|
pub fn LeaseExpiry::expired_at(self : LeaseExpiry) -> Int64 {
  self.expired_at
}

///|
pub fn LeaseExpiry::canonical_bytes(self : LeaseExpiry) -> Bytes {
  self.canonical
}

///|
pub fn LeaseExpiry::binding_digest(
  self : LeaseExpiry,
) -> @contracts.ContentDigest {
  self.expiry_ref.digest()
}

///|
pub struct ClaimedProof {
  record_version : @contracts.Version
  schedule_ref : @contracts.RecordRef
  claim_ref : @contracts.RecordRef
  owner_ref : @contracts.RecordRef
  lease_epoch : Int64
  fencing_token : Int64
  expires_at : Int64
  replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn claimed_proof(
  claim : LeaseClaim,
  lease_epoch : Int64,
  fencing_token : Int64,
  expires_at : Int64,
  replay_digest : @contracts.ContentDigest,
) -> ClaimedProof {
  let writer = OrchestrationWriter::new()
  try! writer.bytes(b"MF7ACLAIMP1")
  try! write_ref(writer, claim.schedule_ref)
  try! write_ref(writer, claim.claim_ref)
  try! write_ref(writer, claim.owner_ref)
  writer.int64(lease_epoch)
  writer.int64(fencing_token)
  writer.int64(expires_at)
  try! writer.string(replay_digest.text())
  let canonical = writer.finish()
  {
    record_version: orchestration_version(),
    schedule_ref: claim.schedule_ref,
    claim_ref: claim.claim_ref,
    owner_ref: claim.owner_ref,
    lease_epoch,
    fencing_token,
    expires_at,
    replay_digest,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn ClaimedProof::claim_ref(self : ClaimedProof) -> @contracts.RecordRef {
  self.claim_ref
}

///|
pub fn ClaimedProof::owner_ref(self : ClaimedProof) -> @contracts.RecordRef {
  self.owner_ref
}

///|
pub fn ClaimedProof::lease_epoch(self : ClaimedProof) -> Int64 {
  self.lease_epoch
}

///|
pub fn ClaimedProof::fencing_token(self : ClaimedProof) -> Int64 {
  self.fencing_token
}

///|
pub fn ClaimedProof::expires_at(self : ClaimedProof) -> Int64 {
  self.expires_at
}

///|
pub fn ClaimedProof::canonical_bytes(self : ClaimedProof) -> Bytes {
  self.canonical
}

///|
pub fn ClaimedProof::binding_digest(
  self : ClaimedProof,
) -> @contracts.ContentDigest {
  self.digest
}
