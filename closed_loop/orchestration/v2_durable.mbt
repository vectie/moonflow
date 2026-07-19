///|
/// A durable V2 registration whose full schedule can be reconstructed from bytes.
pub struct ScheduleRegisteredV2 {
  record_ref : @contracts.RecordRef
  schedule : ScheduleIntentV2
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn ScheduleRegisteredV2::new(
  registration_id : String,
  schedule : ScheduleIntentV2,
) -> ScheduleRegisteredV2 raise OrchestrationError {
  require_text(registration_id, "schedule_registered_v2_id")
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/SCHEDULE-REGISTERED-V2/2.0.0")
  writer.string(orchestration_record_version_v2)
  writer.string(registration_id)
  writer.string(schedule.schedule_ref().id())
  writer.bytes(schedule.canonical_bytes())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v2(
      "orchestration-schedule-registered-v2", registration_id, digest,
    ),
    schedule,
    canonical,
    digest,
  }
}

///|
pub fn ScheduleRegisteredV2::decode(
  expected_registration_id : String,
  bytes : Bytes,
) -> ScheduleRegisteredV2 raise OrchestrationError {
  require_text(expected_registration_id, "schedule_registered_v2_id")
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/SCHEDULE-REGISTERED-V2/2.0.0" {
    raise MalformedInput(field="schedule_registered_v2_tag")
  }
  let version = reader.read_string()
  require_version_v2(version, "schedule_registered_v2")
  let registration_id = reader.read_string()
  if registration_id != expected_registration_id {
    raise IdentityMismatch(field="schedule_registered_v2_id")
  }
  let schedule_id = reader.read_string()
  let schedule_bytes = reader.read_bytes()
  reader.require_end()
  let schedule = ScheduleIntentV2::decode(schedule_id, schedule_bytes)
  let decoded = ScheduleRegisteredV2::new(registration_id, schedule)
  if decoded.canonical_bytes() != bytes {
    raise DigestMismatch(field="schedule_registered_v2_canonical")
  }
  decoded
}

///|
pub fn ScheduleRegisteredV2::record_ref(
  self : ScheduleRegisteredV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn ScheduleRegisteredV2::schedule(
  self : ScheduleRegisteredV2,
) -> ScheduleIntentV2 {
  self.schedule
}

///|
pub fn ScheduleRegisteredV2::schedule_ref(
  self : ScheduleRegisteredV2,
) -> @contracts.RecordRef {
  self.schedule.schedule_ref()
}

///|
pub fn ScheduleRegisteredV2::workflow(
  self : ScheduleRegisteredV2,
) -> @contracts.RecordRef {
  self.schedule.workflow()
}

///|
pub fn ScheduleRegisteredV2::canonical_bytes(
  self : ScheduleRegisteredV2,
) -> Bytes {
  self.canonical
}

///|
pub fn ScheduleRegisteredV2::digest(
  self : ScheduleRegisteredV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// A durable V2 claim bound to one exact committed schedule registration.
pub struct LeaseClaimedV2 {
  record_ref : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  claim : LeaseClaimV2
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn LeaseClaimedV2::new(
  claimed_id : String,
  schedule_registration : ScheduleRegisteredV2,
  claim : LeaseClaimV2,
) -> LeaseClaimedV2 raise OrchestrationError {
  require_text(claimed_id, "lease_claimed_v2_id")
  if claim.schedule_ref() != schedule_registration.schedule_ref() ||
    claim.schedule_digest() != schedule_registration.schedule().digest() ||
    claim.workflow() != schedule_registration.workflow() {
    raise ReplayBindingViolation(field="lease_claimed_v2_schedule")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-CLAIMED-V2/2.0.0")
  writer.string(orchestration_record_version_v2)
  writer.string(claimed_id)
  write_ref(writer, schedule_registration.record_ref())
  writer.string(claim.state_ref().id())
  writer.bytes(claim.canonical_bytes())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v2(
      "orchestration-lease-claimed-v2", claimed_id, digest,
    ),
    schedule_registration_ref: schedule_registration.record_ref(),
    claim,
    canonical,
    digest,
  }
}

///|
pub fn LeaseClaimedV2::decode(
  expected_claimed_id : String,
  schedule_registration : ScheduleRegisteredV2,
  prior_epoch_floor : Int64,
  prior_fencing_floor : Int64,
  bytes : Bytes,
) -> LeaseClaimedV2 raise OrchestrationError {
  require_text(expected_claimed_id, "lease_claimed_v2_id")
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/LEASE-CLAIMED-V2/2.0.0" {
    raise MalformedInput(field="lease_claimed_v2_tag")
  }
  let version = reader.read_string()
  require_version_v2(version, "lease_claimed_v2")
  let claimed_id = reader.read_string()
  if claimed_id != expected_claimed_id {
    raise IdentityMismatch(field="lease_claimed_v2_id")
  }
  let registration_ref = reader.read_ref()
  if registration_ref != schedule_registration.record_ref() {
    raise ReplayBindingViolation(field="lease_claimed_v2_registration")
  }
  let claim_id = reader.read_string()
  let claim_bytes = reader.read_bytes()
  reader.require_end()
  let claim = LeaseClaimV2::decode(
    claim_id,
    schedule_registration.schedule(),
    prior_epoch_floor,
    prior_fencing_floor,
    claim_bytes,
  )
  let decoded = LeaseClaimedV2::new(claimed_id, schedule_registration, claim)
  if decoded.canonical_bytes() != bytes {
    raise DigestMismatch(field="lease_claimed_v2_canonical")
  }
  decoded
}

///|
pub fn LeaseClaimedV2::record_ref(
  self : LeaseClaimedV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn LeaseClaimedV2::schedule_registration_ref(
  self : LeaseClaimedV2,
) -> @contracts.RecordRef {
  self.schedule_registration_ref
}

///|
pub fn LeaseClaimedV2::lease_ref(self : LeaseClaimedV2) -> @contracts.RecordRef {
  self.claim.state_ref()
}

///|
pub fn LeaseClaimedV2::workflow(self : LeaseClaimedV2) -> @contracts.RecordRef {
  self.claim.workflow()
}

///|
pub fn LeaseClaimedV2::owner(self : LeaseClaimedV2) -> @contracts.RecordRef {
  self.claim.owner()
}

///|
pub fn LeaseClaimedV2::epoch(self : LeaseClaimedV2) -> Int64 {
  self.claim.epoch()
}

///|
pub fn LeaseClaimedV2::fencing_token(self : LeaseClaimedV2) -> Int64 {
  self.claim.fencing_token()
}

///|
pub fn LeaseClaimedV2::canonical_bytes(self : LeaseClaimedV2) -> Bytes {
  self.canonical
}

///|
pub fn LeaseClaimedV2::digest(
  self : LeaseClaimedV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum ActiveLeaseV2 {
  Claimed(LeaseClaimedV2, @contracts.RecordRef)
  Renewed(LeaseRenewalV2, @contracts.RecordRef)
  Reclaimed(LeaseReclaimV2, @contracts.RecordRef)
}

///|
fn ActiveLeaseV2::schedule_registration_ref(
  self : ActiveLeaseV2,
) -> @contracts.RecordRef {
  match self {
    Claimed(value, _) => value.schedule_registration_ref()
    Renewed(value, _) => value.schedule_registration_ref
    Reclaimed(value, _) => value.schedule_registration_ref
  }
}

///|
fn ActiveLeaseV2::authority_ref(self : ActiveLeaseV2) -> @contracts.RecordRef {
  match self {
    Claimed(value, _) => value.record_ref()
    Renewed(value, _) => value.record_ref()
    Reclaimed(value, _) => value.record_ref()
  }
}

///|
fn ActiveLeaseV2::authority_digest(
  self : ActiveLeaseV2,
) -> @contracts.ContentDigest {
  match self {
    Claimed(value, _) => value.digest()
    Renewed(value, _) => value.digest()
    Reclaimed(value, _) => value.digest()
  }
}

///|
fn ActiveLeaseV2::state_ref(self : ActiveLeaseV2) -> @contracts.RecordRef {
  match self {
    Claimed(value, _) => value.claim.state_ref()
    Renewed(value, _) => value.record_ref()
    Reclaimed(value, _) => value.record_ref()
  }
}

///|
fn ActiveLeaseV2::state_digest(
  self : ActiveLeaseV2,
) -> @contracts.ContentDigest {
  match self {
    Claimed(value, _) => value.claim.digest()
    Renewed(value, _) => value.digest()
    Reclaimed(value, _) => value.digest()
  }
}

///|
fn ActiveLeaseV2::owner(self : ActiveLeaseV2) -> @contracts.RecordRef {
  match self {
    Claimed(value, _) => value.owner()
    Renewed(value, _) => value.owner()
    Reclaimed(value, _) => value.owner()
  }
}

///|
fn ActiveLeaseV2::observed_at(self : ActiveLeaseV2) -> Int64 {
  match self {
    Claimed(value, _) => value.claim.observed_at()
    Renewed(value, _) => value.observed_at()
    Reclaimed(value, _) => value.observed_at()
  }
}

///|
fn ActiveLeaseV2::expires_at(self : ActiveLeaseV2) -> Int64 {
  match self {
    Claimed(value, _) => value.claim.expires_at()
    Renewed(value, _) => value.expires_at()
    Reclaimed(value, _) => value.expires_at()
  }
}

///|
fn ActiveLeaseV2::epoch(self : ActiveLeaseV2) -> Int64 {
  match self {
    Claimed(value, _) => value.epoch()
    Renewed(value, _) => value.epoch()
    Reclaimed(value, _) => value.epoch()
  }
}

///|
fn ActiveLeaseV2::fencing_token(self : ActiveLeaseV2) -> Int64 {
  match self {
    Claimed(value, _) => value.fencing_token()
    Renewed(value, _) => value.fencing_token()
    Reclaimed(value, _) => value.fencing_token()
  }
}

///|
fn ActiveLeaseV2::committed_event_ref(
  self : ActiveLeaseV2,
) -> @contracts.RecordRef {
  match self {
    Claimed(_, value) | Renewed(_, value) | Reclaimed(_, value) => value
  }
}

///|
pub(all) enum TerminalLeaseV2 {
  ReleasedTerminal(LeaseReleaseV2, @contracts.RecordRef)
  ExpiredTerminal(LeaseExpiryV2, @contracts.RecordRef)
}

///|
let schedule_registered_event_kind_v2 = "schedule.registered.v2"

///|
let lease_claimed_event_kind_v2 = "lease.claimed.v2"

///|
let lease_renewed_event_kind_v2 = "lease.renewed.v2"

///|
let lease_released_event_kind_v2 = "lease.released.v2"

///|
let lease_expired_event_kind_v2 = "lease.expired.v2"

///|
let lease_reclaimed_event_kind_v2 = "lease.reclaimed.v2"

///|
fn same_record_identity_v2(
  left : @contracts.RecordRef,
  right : @contracts.RecordRef,
) -> Bool {
  left.kind() == right.kind() &&
  left.id() == right.id() &&
  left.version() == right.version()
}

///|
fn same_evidence_set_v2(
  left : ArrayView[@contracts.EvidenceRef],
  right : ArrayView[@contracts.EvidenceRef],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index, value in left {
    if value != right[index] {
      return false
    }
  }
  true
}

///|
fn lease_claimed_registration_ref_v2(
  expected_claimed_id : String,
  bytes : Bytes,
) -> @contracts.RecordRef raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/LEASE-CLAIMED-V2/2.0.0" {
    raise MalformedInput(field="lease_claimed_v2_tag")
  }
  let version = reader.read_string()
  require_version_v2(version, "lease_claimed_v2")
  if reader.read_string() != expected_claimed_id {
    raise IdentityMismatch(field="lease_claimed_v2_id")
  }
  let registration_ref = reader.read_ref()
  ignore(reader.read_string())
  ignore(reader.read_bytes())
  reader.require_end()
  registration_ref
}

///|
/// Semantic V2 orchestration state rebuilt only from committed lifecycle bytes.
/// Transport sequence/revision/head and claim-event references are observable
/// but excluded from this semantic digest. Derived authority receipts are never
/// stored in or hashed into the projection, avoiding digest recursion.
pub struct OrchestrationProjectionV2 {
  workflow : @contracts.RecordRef
  sequence : Int64
  revision : Int64
  last_event_digest : @contracts.ContentDigest?
  schedules : ReadOnlyArray[ScheduleRegisteredV2]
  claims : ReadOnlyArray[LeaseClaimedV2]
  claim_event_refs : ReadOnlyArray[@contracts.RecordRef]
  renewals : ReadOnlyArray[LeaseRenewalV2]
  releases : ReadOnlyArray[LeaseReleaseV2]
  expiries : ReadOnlyArray[LeaseExpiryV2]
  reclaims : ReadOnlyArray[LeaseReclaimV2]
  active_lease : ActiveLeaseV2?
  terminal_lease : TerminalLeaseV2?
  epoch_floor : Int64
  fencing_floor : Int64
  root_binding_verified : Bool
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn build_projection_v2(
  workflow : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  last_event_digest : @contracts.ContentDigest?,
  schedules : Array[ScheduleRegisteredV2],
  claims : Array[LeaseClaimedV2],
  claim_event_refs : Array[@contracts.RecordRef],
  renewals : Array[LeaseRenewalV2],
  releases : Array[LeaseReleaseV2],
  expiries : Array[LeaseExpiryV2],
  reclaims : Array[LeaseReclaimV2],
  active_lease : ActiveLeaseV2?,
  terminal_lease : TerminalLeaseV2?,
  epoch_floor : Int64,
  fencing_floor : Int64,
  root_binding_verified? : Bool = false,
) -> OrchestrationProjectionV2 raise OrchestrationError {
  if claim_event_refs.length() != claims.length() {
    raise RecoveryViolation(field="orchestration_v2_claim_event_cardinality")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/ORCHESTRATION-PROJECTION-V2/2.0.0")
  writer.string(orchestration_record_version_v2)
  write_ref(writer, workflow)
  writer.count(schedules.length())
  for value in schedules {
    write_ref(writer, value.record_ref())
    writer.bytes(value.canonical_bytes())
  }
  writer.count(claims.length())
  for value in claims {
    write_ref(writer, value.record_ref())
    writer.bytes(value.canonical_bytes())
  }
  writer.count(renewals.length())
  for value in renewals {
    write_ref(writer, value.record_ref())
    writer.bytes(value.canonical_bytes())
  }
  writer.count(releases.length())
  for value in releases {
    write_ref(writer, value.record_ref())
    writer.bytes(value.canonical_bytes())
  }
  writer.count(expiries.length())
  for value in expiries {
    write_ref(writer, value.record_ref())
    writer.bytes(value.canonical_bytes())
  }
  writer.count(reclaims.length())
  for value in reclaims {
    write_ref(writer, value.record_ref())
    writer.bytes(value.canonical_bytes())
  }
  writer.int64(epoch_floor)
  writer.int64(fencing_floor)
  let canonical = writer.finish()
  {
    workflow,
    sequence,
    revision,
    last_event_digest,
    schedules: ReadOnlyArray::from_array(schedules.copy()),
    claims: ReadOnlyArray::from_array(claims.copy()),
    claim_event_refs: ReadOnlyArray::from_array(claim_event_refs.copy()),
    renewals: ReadOnlyArray::from_array(renewals.copy()),
    releases: ReadOnlyArray::from_array(releases.copy()),
    expiries: ReadOnlyArray::from_array(expiries.copy()),
    reclaims: ReadOnlyArray::from_array(reclaims.copy()),
    active_lease,
    terminal_lease,
    epoch_floor,
    fencing_floor,
    root_binding_verified,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn OrchestrationProjectionV2::workflow(
  self : OrchestrationProjectionV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn OrchestrationProjectionV2::sequence(
  self : OrchestrationProjectionV2,
) -> Int64 {
  self.sequence
}

///|
pub fn OrchestrationProjectionV2::revision(
  self : OrchestrationProjectionV2,
) -> Int64 {
  self.revision
}

///|
pub fn OrchestrationProjectionV2::last_event_digest(
  self : OrchestrationProjectionV2,
) -> @contracts.ContentDigest? {
  self.last_event_digest
}

///|
pub fn OrchestrationProjectionV2::schedule_count(
  self : OrchestrationProjectionV2,
) -> Int {
  self.schedules.length()
}

///|
pub fn OrchestrationProjectionV2::latest_schedule_deadline(
  self : OrchestrationProjectionV2,
) -> Int64? {
  match self.schedules.last() {
    None => None
    Some(value) => value.schedule().deadline()
  }
}

///|
pub fn OrchestrationProjectionV2::lease_count(
  self : OrchestrationProjectionV2,
) -> Int {
  self.claims.length() + self.reclaims.length()
}

///|
pub fn OrchestrationProjectionV2::schedule_registration_refs(
  self : OrchestrationProjectionV2,
) -> ReadOnlyArray[@contracts.RecordRef] {
  ReadOnlyArray::from_array(
    [
      for value in self.schedules => value.record_ref()
    ],
  )
}

///|
pub fn OrchestrationProjectionV2::lease_refs(
  self : OrchestrationProjectionV2,
) -> ReadOnlyArray[@contracts.RecordRef] {
  let refs : Array[@contracts.RecordRef] = []
  for value in self.claims {
    refs.push(value.lease_ref())
  }
  for value in self.reclaims {
    refs.push(value.record_ref())
  }
  ReadOnlyArray::from_array(refs)
}

///|
pub fn OrchestrationProjectionV2::lease_owner(
  self : OrchestrationProjectionV2,
) -> @contracts.RecordRef? {
  match self.active_lease {
    Some(value) => Some(value.owner())
    None => None
  }
}

///|
pub fn OrchestrationProjectionV2::has_active_lease(
  self : OrchestrationProjectionV2,
) -> Bool {
  self.active_lease is Some(_)
}

///|
pub fn OrchestrationProjectionV2::has_terminal_lease(
  self : OrchestrationProjectionV2,
) -> Bool {
  self.terminal_lease is Some(_)
}

///|
pub fn OrchestrationProjectionV2::epoch_floor(
  self : OrchestrationProjectionV2,
) -> Int64 {
  self.epoch_floor
}

///|
pub fn OrchestrationProjectionV2::fencing_floor(
  self : OrchestrationProjectionV2,
) -> Int64 {
  self.fencing_floor
}

///|
pub fn OrchestrationProjectionV2::canonical_bytes(
  self : OrchestrationProjectionV2,
) -> Bytes {
  self.canonical
}

///|
pub fn OrchestrationProjectionV2::state_digest(
  self : OrchestrationProjectionV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
fn require_v2_transport_binding(
  event : @storage.WorkflowEvent,
  expected_kind : String,
  expected_subject : @contracts.RecordRef,
  expected_evidence : ArrayView[@contracts.EvidenceRef],
  expected_causation : @contracts.RecordRef,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.record_version() != orchestration_version() ||
    event.schema_version() != orchestration_version() {
    raise UnsupportedVersion(
      field="orchestration_v2_transport",
      version=event.record_version().text(),
    )
  }
  if envelope.contract_id() != orchestration_contract_id ||
    envelope.contract_version() != orchestration_version() ||
    envelope.schema() != orchestration_schema(expected_kind) ||
    envelope.producer_id() != orchestration_producer_id ||
    envelope.producer_version() != orchestration_version() ||
    envelope.envelope_kind() != expected_kind {
    raise ReplayBindingViolation(field="orchestration_v2_transport_contract")
  }
  if envelope.envelope_id() != event.event_ref().id() ||
    envelope.subject() != expected_subject {
    raise IdentityMismatch(field="orchestration_v2_transport_subject")
  }
  if envelope.run_ref() != Some(event.workflow()) ||
    envelope.correlation_ref() != Some(event.workflow().id()) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) {
    raise WorkflowMismatch(field="orchestration_v2_transport_workflow")
  }
  if envelope.idempotency_ref() != Some(event.idempotency_key()) {
    raise IdempotencyConflict(key=event.idempotency_key())
  }
  if envelope.causation_ref() != Some(expected_causation.id()) {
    raise IdentityMismatch(field="orchestration_v2_transport_causation")
  }
  if envelope.previous_digest() != event.previous_event_digest() {
    raise DigestMismatch(field="orchestration_v2_transport_previous_digest")
  }
  if !same_evidence(event.evidence(), envelope.evidence()) ||
    !same_evidence_set_v2(envelope.evidence(), expected_evidence) {
    raise EvidenceMismatch(field="orchestration_v2_transport_evidence")
  }
  if !envelope.artifacts().is_empty() || !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="orchestration_v2_transport_extras")
  }
}

///|
fn require_v2_payload_idempotency(
  event : @storage.WorkflowEvent,
  payload_idempotency_key : String,
) -> Unit raise OrchestrationError {
  // Event keys deduplicate one lifecycle append. Command keys deduplicate the
  // surrounding CAS command in a separate storage namespace.
  if event.idempotency_key() != payload_idempotency_key {
    raise IdempotencyConflict(key=event.idempotency_key())
  }
}

///|
fn lifecycle_registration_ref_v2(
  expected_tag : Bytes,
  expected_id : String,
  bytes : Bytes,
) -> @contracts.RecordRef raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != expected_tag {
    raise MalformedInput(field="lease_lifecycle_v2_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v2 && version != "2.1.0" {
    raise UnsupportedVersion(field="lease_lifecycle_v2", version~)
  }
  if reader.read_string() != expected_id {
    raise IdentityMismatch(field="lease_lifecycle_v2_id")
  }
  reader.read_ref()
}

///|
pub fn orchestration_genesis_position_v2(
  workflow : @contracts.RecordRef,
) -> @effects_authorization.ReplayPosition raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/ORCHESTRATION-GENESIS-V2/2.1.0")
  write_ref(writer, workflow)
  let digest = @contracts.sha256_digest(writer.finish())
  let event_ref = self_ref_v2("orchestration-genesis-v2", workflow.id(), digest)
  @effects_authorization.ReplayPosition::new(event_ref, 0L, 0L, digest).unwrap()
}

///|
fn require_schedule_admission_head_v2(
  workflow : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  head_digest : @contracts.ContentDigest?,
  registration : ScheduleRegisteredV2,
) -> Unit raise OrchestrationError {
  if !@replay.is_genesis_position(sequence, revision, head_digest is Some(_)) {
    raise ReplayBindingViolation(field="schedule_registered_v2_non_genesis")
  }
  let admission = registration.schedule().admission()
  let expected = orchestration_genesis_position_v2(workflow)
  let actual = admission.eligibility().authoritative_head()
  if admission.planned().workflow() != workflow ||
    actual.event_ref() != expected.event_ref() ||
    actual.event_digest() != expected.event_digest() ||
    actual.sequence() != expected.sequence() ||
    actual.revision() != expected.revision() {
    raise ReplayBindingViolation(
      field="schedule_registered_v2_authoritative_head",
    )
  }
  if admission.controls().capability() is None {
    raise EffectProofMismatch(field="schedule_registered_v2_capability")
  }
  if admission.controls().evidence().is_empty() {
    raise EvidenceMismatch(field="schedule_registered_v2_evidence_empty")
  }
  let clock = admission.eligibility().clock()
  if !admission.governance().accepts(clock) ||
    !admission.controls().accepts(clock) {
    raise AuthorityExpired(
      expires_at=admission.controls().deadline_inclusive(),
      observed_at=clock,
    )
  }
}

///|
fn verified_mixed_schedule_prefix_kind_v2(kind : String) -> Bool {
  @replay.is_verified_mixed_schedule_prefix_kind_v2(kind)
}

///|
fn require_mixed_schedule_admission_head_v2(
  workflow : @contracts.RecordRef,
  events : ArrayView[@storage.WorkflowEvent],
  schedule_index : Int,
  registration : ScheduleRegisteredV2,
) -> Unit raise OrchestrationError {
  if schedule_index == 0 {
    raise ReplayBindingViolation(
      field="schedule_registered_v2_mixed_empty_prefix",
    )
  }
  for event in events[:schedule_index] {
    if !verified_mixed_schedule_prefix_kind_v2(event.payload().envelope_kind()) {
      raise ReplayBindingViolation(
        field="schedule_registered_v2_mixed_prefix_kind",
      )
    }
  }
  let predecessor = events[schedule_index - 1]
  let admission = registration.schedule().admission()
  let actual = admission.eligibility().authoritative_head()
  if admission.planned().workflow() != workflow ||
    predecessor.workflow() != workflow ||
    actual.event_ref() != predecessor.event_ref() ||
    actual.event_digest() != predecessor.event_ref().digest() ||
    actual.sequence() != predecessor.sequence() ||
    actual.revision() != predecessor.revision() {
    raise ReplayBindingViolation(
      field="schedule_registered_v2_mixed_authoritative_head",
    )
  }
  if admission.controls().capability() is None {
    raise EffectProofMismatch(field="schedule_registered_v2_capability")
  }
  if admission.controls().evidence().is_empty() {
    raise EvidenceMismatch(field="schedule_registered_v2_evidence_empty")
  }
  let clock = admission.eligibility().clock()
  if !admission.governance().accepts(clock) ||
    !admission.controls().accepts(clock) {
    raise AuthorityExpired(
      expires_at=admission.controls().deadline_inclusive(),
      observed_at=clock,
    )
  }
}

///|
fn require_retry_schedule_admission_head_v2(
  workflow : @contracts.RecordRef,
  plan : @retry_authority.RetryPlanProposalV2,
  registration : ScheduleRegisteredV2,
) -> Unit raise OrchestrationError {
  let admission = registration.schedule().admission()
  let actual = admission.eligibility().authoritative_head()
  if admission.planned().workflow() != workflow ||
    actual.event_ref() != plan.prefix_head_ref() ||
    actual.event_digest() != plan.prefix_head_digest() ||
    actual.sequence() != plan.prefix_sequence() ||
    actual.revision() != plan.prefix_revision() {
    raise ReplayBindingViolation(field="retry_schedule_authoritative_head")
  }
  if admission.controls().capability() is None {
    raise EffectProofMismatch(field="retry_schedule_capability")
  }
  if admission.controls().evidence().is_empty() {
    raise EvidenceMismatch(field="retry_schedule_evidence_empty")
  }
  let clock = admission.eligibility().clock()
  if clock != plan.due_at() ||
    !admission.governance().accepts(clock) ||
    !admission.controls().accepts(clock) {
    raise AuthorityExpired(
      expires_at=admission.controls().deadline_inclusive(),
      observed_at=clock,
    )
  }
}

///|
fn prefix_projection_v2(
  workflow : @contracts.RecordRef,
  event : @storage.WorkflowEvent,
  schedules : Array[ScheduleRegisteredV2],
  claims : Array[LeaseClaimedV2],
  claim_event_refs : Array[@contracts.RecordRef],
  renewals : Array[LeaseRenewalV2],
  releases : Array[LeaseReleaseV2],
  expiries : Array[LeaseExpiryV2],
  reclaims : Array[LeaseReclaimV2],
  active_lease : ActiveLeaseV2?,
  terminal_lease : TerminalLeaseV2?,
  epoch_floor : Int64,
  fencing_floor : Int64,
  root_binding_verified : Bool,
) -> OrchestrationProjectionV2 raise OrchestrationError {
  build_projection_v2(
    workflow,
    event.sequence() - 1L,
    event.revision() - 1L,
    event.previous_event_digest(),
    schedules,
    claims,
    claim_event_refs,
    renewals,
    releases,
    expiries,
    reclaims,
    active_lease,
    terminal_lease,
    epoch_floor,
    fencing_floor,
    root_binding_verified~,
  )
}

///|
fn fold_orchestration_v2_internal(
  replay : @storage.ReplayResult,
  allow_verified_effect_events : Bool,
  allow_verified_root_binding_events : Bool,
) -> OrchestrationProjectionV2 raise OrchestrationError {
  let workflow = replay.workflow()
  let head = replay.head()
  if head.workflow() != workflow {
    raise WorkflowMismatch(field="orchestration_v2_replay_head")
  }
  if !allow_verified_effect_events && !replay.intents().is_empty() {
    raise ReplayBindingViolation(field="orchestration_v2_unexpected_intents")
  }
  let schedules : Array[ScheduleRegisteredV2] = []
  let claims : Array[LeaseClaimedV2] = []
  let claim_event_refs : Array[@contracts.RecordRef] = []
  let renewals : Array[LeaseRenewalV2] = []
  let releases : Array[LeaseReleaseV2] = []
  let expiries : Array[LeaseExpiryV2] = []
  let reclaims : Array[LeaseReclaimV2] = []
  let mut active_lease : ActiveLeaseV2? = None
  let mut terminal_lease : TerminalLeaseV2? = None
  let mut epoch_floor = 0L
  let mut fencing_floor = 0L
  let replay_events = replay.events()
  for index, event in replay_events {
    if event.workflow() != workflow {
      raise WorkflowMismatch(field="orchestration_v2_event_workflow")
    }
    let envelope = event.payload()
    match envelope.envelope_kind() {
      "schedule.registered.v2" => {
        if envelope.subject().kind() != "orchestration-schedule-registered-v2" ||
          envelope.subject().version().text() != orchestration_record_version_v2 {
          raise IdentityMismatch(field="schedule_registered_v2_subject")
        }
        let decoded = ScheduleRegisteredV2::decode(
          envelope.subject().id(),
          envelope.payload(),
        )
        if decoded.record_ref() != envelope.subject() ||
          decoded.workflow() != workflow {
          raise ReplayBindingViolation(field="schedule_registered_v2_binding")
        }
        require_v2_transport_binding(
          event,
          schedule_registered_event_kind_v2,
          decoded.record_ref(),
          decoded.schedule().evidence(),
          decoded.schedule().causation_ref(),
        )
        require_v2_payload_idempotency(
          event,
          decoded.schedule().idempotency_key(),
        )
        if decoded.schedule().previous_digest() != event.previous_event_digest() {
          raise DigestMismatch(field="schedule_registered_v2_previous_digest")
        }
        match decoded.schedule().retry_plan() {
          None =>
            if allow_verified_root_binding_events && index > 0 {
              // A verified Phase 1A root already owns the only non-retry
              // schedule admission. Later schedules must carry a committed
              // retry plan; they cannot reuse genesis admission authority.
              raise ReplayBindingViolation(
                field="schedule_registered_v2_non_genesis",
              )
            } else if allow_verified_effect_events && index > 0 {
              require_mixed_schedule_admission_head_v2(
                workflow, replay_events, index, decoded,
              )
            } else {
              require_schedule_admission_head_v2(
                workflow,
                event.sequence() - 1L,
                event.revision() - 1L,
                event.previous_event_digest(),
                decoded,
              )
            }
          Some(plan) =>
            require_retry_schedule_admission_head_v2(workflow, plan, decoded)
        }
        match
          schedules.search_by(existing => {
            same_record_identity_v2(existing.record_ref(), decoded.record_ref())
          }) {
          Some(index) => {
            let existing = schedules[index]
            if existing.record_ref() != decoded.record_ref() ||
              existing.canonical_bytes() != decoded.canonical_bytes() {
              raise ReplayBindingViolation(
                field="schedule_registered_v2_identity_conflict",
              )
            }
            // A physically committed second event cannot be an exact retry:
            // its event-chain predecessor differs. Exact retries are removed
            // by StoragePort command idempotency before append.
            raise ScheduleStateViolation(
              field="schedule_registered_v2_second_event",
            )
          }
          None => {
            if schedules.is_empty() {
              if decoded.schedule().retry_plan() is Some(_) {
                raise ScheduleStateViolation(
                  field="schedule_registered_v2_retry_without_initial",
                )
              }
            } else {
              match decoded.schedule().retry_plan() {
                None =>
                  raise ScheduleStateViolation(
                    field="schedule_registered_v2_multiple_initial",
                  )
                Some(plan) => {
                  let prior_deadline = schedules
                    .last()
                    .unwrap()
                    .schedule()
                    .deadline()
                  if plan.source_schedule_deadline() != prior_deadline {
                    raise ScheduleStateViolation(
                      field="retry_source_schedule_deadline",
                    )
                  }
                }
              }
              if active_lease is Some(_) {
                raise ScheduleStateViolation(
                  field="schedule_registered_v2_active_lease",
                )
              }
              if terminal_lease is None {
                raise ScheduleStateViolation(
                  field="schedule_registered_v2_prior_not_terminal",
                )
              }
              terminal_lease = None
            }
            schedules.push(decoded)
          }
        }
      }
      "lease.claimed.v2" => {
        if envelope.subject().kind() != "orchestration-lease-claimed-v2" ||
          envelope.subject().version().text() != orchestration_record_version_v2 {
          raise IdentityMismatch(field="lease_claimed_v2_subject")
        }
        match
          claims.search_by(existing => {
            same_record_identity_v2(existing.record_ref(), envelope.subject())
          }) {
          Some(index) => {
            let existing = claims[index]
            if existing.record_ref() != envelope.subject() ||
              existing.canonical_bytes() != envelope.payload() {
              raise ReplayBindingViolation(
                field="lease_claimed_v2_identity_conflict",
              )
            }
            require_v2_transport_binding(
              event,
              lease_claimed_event_kind_v2,
              existing.record_ref(),
              existing.claim.evidence(),
              existing.claim.causation(),
            )
            require_v2_payload_idempotency(
              event,
              existing.claim.idempotency_key(),
            )
          }
          None => {
            let registration_ref = lease_claimed_registration_ref_v2(
              envelope.subject().id(),
              envelope.payload(),
            )
            guard schedules.search_by(value => {
                value.record_ref() == registration_ref
              })
              is Some(schedule_index) else {
              raise ReplayBindingViolation(
                field="lease_claimed_v2_registration_missing",
              )
            }
            let registration = schedules[schedule_index]
            let decoded = LeaseClaimedV2::decode(
              envelope.subject().id(),
              registration,
              epoch_floor,
              fencing_floor,
              envelope.payload(),
            )
            if decoded.record_ref() != envelope.subject() ||
              decoded.workflow() != workflow {
              raise ReplayBindingViolation(field="lease_claimed_v2_binding")
            }
            if active_lease is Some(_) {
              raise ScheduleStateViolation(field="lease_claimed_v2_concurrent")
            }
            if schedule_index != schedules.length() - 1 {
              raise ScheduleStateViolation(
                field="lease_claimed_v2_stale_schedule",
              )
            }
            if claims.any(prior => {
                prior.schedule_registration_ref() == registration.record_ref()
              }) {
              raise ScheduleStateViolation(field="lease_claimed_v2_duplicate")
            }
            require_v2_transport_binding(
              event,
              lease_claimed_event_kind_v2,
              decoded.record_ref(),
              decoded.claim.evidence(),
              decoded.claim.causation(),
            )
            require_v2_payload_idempotency(
              event,
              decoded.claim.idempotency_key(),
            )
            claims.push(decoded)
            claim_event_refs.push(event.event_ref())
            active_lease = Some(Claimed(decoded, event.event_ref()))
            epoch_floor = decoded.epoch()
            fencing_floor = decoded.fencing_token()
          }
        }
      }
      "lease.renewed.v2" => {
        if envelope.subject().kind() != "orchestration-lease-renewal-v2" ||
          envelope.subject().version().text() != orchestration_record_version_v2 {
          raise IdentityMismatch(field="lease_renewal_v2_subject")
        }
        if renewals.any(value => {
            same_record_identity_v2(value.record_ref(), envelope.subject())
          }) {
          raise ReplayBindingViolation(
            field="lease_renewal_v2_identity_conflict",
          )
        }
        let registration_ref = lifecycle_registration_ref_v2(
          b"FLOW7/LEASE-RENEWAL-V2/2.1.0",
          envelope.subject().id(),
          envelope.payload(),
        )
        guard schedules.search_by(value => {
            value.record_ref() == registration_ref
          })
          is Some(schedule_index) else {
          raise ReplayBindingViolation(
            field="lease_renewal_v2_registration_missing",
          )
        }
        let prefix = prefix_projection_v2(
          workflow, event, schedules, claims, claim_event_refs, renewals, releases,
          expiries, reclaims, active_lease, terminal_lease, epoch_floor, fencing_floor,
          allow_verified_root_binding_events,
        )
        guard prefix.committed_lease_authority_receipt()
          is Some(current_receipt) else {
          raise ScheduleStateViolation(field="lease_renewal_v2_no_active")
        }
        let decoded = LeaseRenewalV2::decode(
          envelope.subject().id(),
          schedules[schedule_index],
          prefix,
          current_receipt,
          envelope.payload(),
        )
        if decoded.record_ref() != envelope.subject() {
          raise ReplayBindingViolation(field="lease_renewal_v2_binding")
        }
        require_v2_transport_binding(
          event,
          lease_renewed_event_kind_v2,
          decoded.record_ref(),
          decoded.evidence(),
          decoded.causation(),
        )
        require_v2_payload_idempotency(event, decoded.idempotency_key())
        renewals.push(decoded)
        active_lease = Some(Renewed(decoded, event.event_ref()))
      }
      "lease.released.v2" => {
        if envelope.subject().kind() != "orchestration-lease-release-v2" ||
          envelope.subject().version().text() != orchestration_record_version_v2 {
          raise IdentityMismatch(field="lease_release_v2_subject")
        }
        if releases.any(value => {
            same_record_identity_v2(value.record_ref(), envelope.subject())
          }) {
          raise ReplayBindingViolation(
            field="lease_release_v2_identity_conflict",
          )
        }
        let registration_ref = lifecycle_registration_ref_v2(
          b"FLOW7/LEASE-RELEASE-V2/2.1.0",
          envelope.subject().id(),
          envelope.payload(),
        )
        guard schedules.search_by(value => {
            value.record_ref() == registration_ref
          })
          is Some(schedule_index) else {
          raise ReplayBindingViolation(
            field="lease_release_v2_registration_missing",
          )
        }
        let prefix = prefix_projection_v2(
          workflow, event, schedules, claims, claim_event_refs, renewals, releases,
          expiries, reclaims, active_lease, terminal_lease, epoch_floor, fencing_floor,
          allow_verified_root_binding_events,
        )
        guard prefix.committed_lease_authority_receipt()
          is Some(current_receipt) else {
          raise ScheduleStateViolation(field="lease_release_v2_no_active")
        }
        let decoded = LeaseReleaseV2::decode(
          envelope.subject().id(),
          schedules[schedule_index],
          prefix,
          current_receipt,
          envelope.payload(),
        )
        if decoded.record_ref() != envelope.subject() {
          raise ReplayBindingViolation(field="lease_release_v2_binding")
        }
        require_v2_transport_binding(
          event,
          lease_released_event_kind_v2,
          decoded.record_ref(),
          decoded.evidence(),
          decoded.causation(),
        )
        require_v2_payload_idempotency(event, decoded.idempotency_key())
        releases.push(decoded)
        active_lease = None
        terminal_lease = Some(ReleasedTerminal(decoded, event.event_ref()))
      }
      "lease.expired.v2" => {
        if envelope.subject().kind() != "orchestration-lease-expiry-v2" ||
          envelope.subject().version().text() != orchestration_record_version_v2 {
          raise IdentityMismatch(field="lease_expiry_v2_subject")
        }
        if expiries.any(value => {
            same_record_identity_v2(value.record_ref(), envelope.subject())
          }) {
          raise ReplayBindingViolation(
            field="lease_expiry_v2_identity_conflict",
          )
        }
        let registration_ref = lifecycle_registration_ref_v2(
          b"FLOW7/LEASE-EXPIRY-V2/2.1.0",
          envelope.subject().id(),
          envelope.payload(),
        )
        guard schedules.search_by(value => {
            value.record_ref() == registration_ref
          })
          is Some(schedule_index) else {
          raise ReplayBindingViolation(
            field="lease_expiry_v2_registration_missing",
          )
        }
        let prefix = prefix_projection_v2(
          workflow, event, schedules, claims, claim_event_refs, renewals, releases,
          expiries, reclaims, active_lease, terminal_lease, epoch_floor, fencing_floor,
          allow_verified_root_binding_events,
        )
        guard prefix.committed_lease_authority_receipt()
          is Some(current_receipt) else {
          raise ScheduleStateViolation(field="lease_expiry_v2_no_active")
        }
        let decoded = LeaseExpiryV2::decode(
          envelope.subject().id(),
          schedules[schedule_index],
          prefix,
          current_receipt,
          envelope.payload(),
        )
        if decoded.record_ref() != envelope.subject() {
          raise ReplayBindingViolation(field="lease_expiry_v2_binding")
        }
        require_v2_transport_binding(
          event,
          lease_expired_event_kind_v2,
          decoded.record_ref(),
          decoded.evidence(),
          decoded.causation(),
        )
        require_v2_payload_idempotency(event, decoded.idempotency_key())
        expiries.push(decoded)
        active_lease = None
        terminal_lease = Some(ExpiredTerminal(decoded, event.event_ref()))
      }
      "lease.reclaimed.v2" => {
        if envelope.subject().kind() != "orchestration-lease-reclaim-v2" ||
          envelope.subject().version().text() != orchestration_record_version_v2 {
          raise IdentityMismatch(field="lease_reclaim_v2_subject")
        }
        if active_lease is Some(_) {
          raise ScheduleStateViolation(field="lease_reclaim_v2_active")
        }
        guard terminal_lease is Some(_) else {
          raise ScheduleStateViolation(field="lease_reclaim_v2_no_terminal")
        }
        if reclaims.any(value => {
            same_record_identity_v2(value.record_ref(), envelope.subject())
          }) {
          raise ReplayBindingViolation(
            field="lease_reclaim_v2_identity_conflict",
          )
        }
        let registration_ref = lifecycle_registration_ref_v2(
          b"FLOW7/LEASE-RECLAIM-V2/2.1.0",
          envelope.subject().id(),
          envelope.payload(),
        )
        guard schedules.search_by(value => {
            value.record_ref() == registration_ref
          })
          is Some(schedule_index) else {
          raise ReplayBindingViolation(
            field="lease_reclaim_v2_registration_missing",
          )
        }
        let prefix = prefix_projection_v2(
          workflow, event, schedules, claims, claim_event_refs, renewals, releases,
          expiries, reclaims, active_lease, terminal_lease, epoch_floor, fencing_floor,
          allow_verified_root_binding_events,
        )
        guard prefix.committed_lease_terminal_receipt()
          is Some(terminal_receipt) else {
          raise ScheduleStateViolation(field="lease_reclaim_v2_no_receipt")
        }
        let decoded = LeaseReclaimV2::decode(
          envelope.subject().id(),
          schedules[schedule_index],
          prefix,
          terminal_receipt,
          envelope.payload(),
        )
        if decoded.record_ref() != envelope.subject() ||
          decoded.epoch() <= epoch_floor ||
          decoded.fencing_token() <= fencing_floor {
          raise ReplayBindingViolation(field="lease_reclaim_v2_binding")
        }
        require_v2_transport_binding(
          event,
          lease_reclaimed_event_kind_v2,
          decoded.record_ref(),
          decoded.evidence(),
          decoded.causation(),
        )
        require_v2_payload_idempotency(event, decoded.idempotency_key())
        reclaims.push(decoded)
        active_lease = Some(Reclaimed(decoded, event.event_ref()))
        terminal_lease = None
        epoch_floor = decoded.epoch()
        fencing_floor = decoded.fencing_token()
      }
      "EvidenceAttached"
      | "AuthorityRequested"
      | "AuthorityGranted"
      | "AuthorityDenied"
      | "ReviewRequested"
      | "ReviewDecisionRecorded"
      | "ReviewReceiptBound"
      | "attempt.registered.v1"
      | "effect.intent.requested.v1"
      | "effect.dispatch.observed.v1"
      | "effect.receipt.recorded.v1"
      | "effect.outcome.unknown.v1"
      | "effect.reconciliation.requested.v1"
      | "effect.reconciliation.resolved.v1"
      | "effect.recovery.activated.v3"
      | "effect.dispatch.claimed.v3"
      | "effect.dispatch.invocation-started.v3"
      | "effect.dispatch.observed.v3" =>
        if !allow_verified_effect_events {
          raise ReplayBindingViolation(
            field="orchestration_v2_unknown_event_kind",
          )
        }
      "retry.policy.bound.v2" | "cancellation.governance.bound.v2" =>
        if !allow_verified_root_binding_events {
          raise ReplayBindingViolation(
            field="orchestration_v2_unknown_event_kind",
          )
        }
      "work.cancellation.requested.v2" | "work.terminal.v2" =>
        if !allow_verified_root_binding_events {
          raise ReplayBindingViolation(
            field="orchestration_v2_unknown_event_kind",
          )
        }
      _ =>
        raise ReplayBindingViolation(
          field="orchestration_v2_unknown_event_kind",
        )
    }
  }
  build_projection_v2(
    workflow,
    head.sequence(),
    head.revision(),
    head.last_event_digest(),
    schedules,
    claims,
    claim_event_refs,
    renewals,
    releases,
    expiries,
    reclaims,
    active_lease,
    terminal_lease,
    epoch_floor,
    fencing_floor,
    root_binding_verified=allow_verified_root_binding_events,
  )
}

///|
pub fn fold_orchestration_v2(
  replay : @storage.ReplayResult,
) -> OrchestrationProjectionV2 raise OrchestrationError {
  let events = replay.events()
  if events.length() >= 3 &&
    events[0].payload().envelope_kind() == schedule_registered_event_kind_v2 &&
    events[1].payload().envelope_kind() == retry_policy_bound_event_kind_v22 &&
    events[2].payload().envelope_kind() ==
    cancellation_governance_bound_event_kind_v22 {
    fold_root_bound_orchestration_auto_v22(replay)
  } else {
    fold_orchestration_v2_internal(replay, false, false)
  }
}

///|
fn v2_lifecycle_envelope(
  event_id : String,
  event_kind : String,
  workflow : @contracts.RecordRef,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  event_idempotency_key : String,
  previous_digest : @contracts.ContentDigest?,
) -> @contracts.WireEnvelope raise {
  @contracts.WireEnvelope::new(
    orchestration_contract_id,
    orchestration_record_version,
    event_id,
    event_kind,
    subject,
    orchestration_schema(event_kind),
    payload,
    orchestration_producer_id,
    orchestration_record_version,
    [],
    evidence,
    run_ref=workflow,
    correlation_ref=workflow.id(),
    causation_ref=causation.id(),
    idempotency_ref=event_idempotency_key,
    previous_digest?,
  )
}

///|
fn prepare_v2_lifecycle_event(
  projection : OrchestrationProjectionV2,
  event_id : String,
  event_kind : String,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  event_idempotency_key : String,
) -> @storage.WorkflowEvent raise {
  let previous_event_digest = projection.last_event_digest()
  let envelope = v2_lifecycle_envelope(
    event_id,
    event_kind,
    projection.workflow(),
    subject,
    payload,
    evidence,
    causation,
    event_idempotency_key,
    previous_event_digest,
  )
  let canonical_evidence = [ for value in envelope.evidence() => value ]
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    projection.workflow(),
    event_id,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    event_idempotency_key,
    envelope,
    canonical_evidence,
    previous_event_digest?,
  )
}

///|
/// Prepare one CAS-bound lease claim. The exact committed schedule registration
/// and replay-derived fencing floors are mandatory inputs from the projection.
fn prepare_lease_claimed_v2(
  projection : OrchestrationProjectionV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  claimed : LeaseClaimedV2,
) -> @storage.CommitRequest raise {
  require_root_binding_verified_v22(projection)
  if claimed.workflow() != projection.workflow() {
    raise WorkflowMismatch(field="lease_claimed_v2_prepare_workflow")
  }
  // The event and payload share one lifecycle key. The command key remains a
  // separate CAS-command idempotency namespace.
  if event_idempotency_key != claimed.claim.idempotency_key() {
    raise IdempotencyConflict(key=event_idempotency_key)
  }
  if !projection.schedules.any(value => {
      value.record_ref() == claimed.schedule_registration_ref()
    }) {
    raise ReplayBindingViolation(
      field="lease_claimed_v2_registration_not_committed",
    )
  }
  if claimed.epoch() <= projection.epoch_floor() {
    raise LeaseEpochViolation(
      expected_greater_than=projection.epoch_floor(),
      actual=claimed.epoch(),
    )
  }
  if claimed.fencing_token() <= projection.fencing_floor() {
    raise FencingViolation(
      expected_greater_than=projection.fencing_floor(),
      actual=claimed.fencing_token(),
    )
  }
  if projection.has_active_lease() || projection.has_terminal_lease() {
    raise ScheduleStateViolation(field="lease_claimed_v2_not_initial")
  }
  if projection.claims.any(value => {
      same_record_identity_v2(value.record_ref(), claimed.record_ref())
    }) {
    raise ReplayBindingViolation(field="lease_claimed_v2_already_present")
  }
  let event = prepare_v2_lifecycle_event(
    projection,
    event_id,
    lease_claimed_event_kind_v2,
    claimed.record_ref(),
    claimed.canonical_bytes(),
    [
      for value in claimed.claim.evidence() => value
    ],
    claimed.claim.causation(),
    event_idempotency_key,
  )
  @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    projection.workflow(),
    projection.revision(),
    command_idempotency_key,
    [event],
    [],
  )
}

///|
fn require_root_binding_verified_v22(
  projection : OrchestrationProjectionV2,
) -> Unit raise OrchestrationError {
  if !projection.root_binding_verified {
    raise ReplayBindingViolation(field="initial_work_root_binding_required")
  }
}

///|
fn require_current_receipt_v2(
  projection : OrchestrationProjectionV2,
  predecessor_ref : @contracts.RecordRef,
  predecessor_digest : @contracts.ContentDigest,
  predecessor_bytes : Bytes,
  field : String,
) -> CommittedLeaseAuthorityReceiptV2 raise OrchestrationError {
  guard projection.committed_lease_authority_receipt() is Some(current) else {
    raise ScheduleStateViolation(field="lease_lifecycle_v2_no_active")
  }
  require_exact_predecessor_receipt_v2(
    predecessor_ref, predecessor_digest, predecessor_bytes, current, field,
  )
  current
}

///|
fn prepare_lease_successor_event_v2(
  projection : OrchestrationProjectionV2,
  event_id : String,
  event_kind : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
) -> @storage.CommitRequest raise {
  let event = prepare_v2_lifecycle_event(
    projection, event_id, event_kind, subject, payload, evidence, causation, event_idempotency_key,
  )
  @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    projection.workflow(),
    projection.revision(),
    command_idempotency_key,
    [event],
    [],
  )
}

///|
/// Prepare an exact-receipt-bound renewal. Only storage commit creates the
/// successor event; this function performs no clock read or external effect.
fn prepare_lease_renewed_v2(
  projection : OrchestrationProjectionV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  renewal : LeaseRenewalV2,
) -> @storage.CommitRequest raise {
  require_root_binding_verified_v22(projection)
  if renewal.workflow() != projection.workflow() {
    raise WorkflowMismatch(field="lease_renewal_v2_prepare_workflow")
  }
  if event_idempotency_key != renewal.idempotency_key() {
    raise IdempotencyConflict(key=event_idempotency_key)
  }
  ignore(
    require_current_receipt_v2(
      projection,
      renewal.predecessor_receipt_ref,
      renewal.predecessor_receipt_digest,
      renewal.predecessor_receipt_bytes,
      "lease_renewal_v2_prepare_predecessor",
    ),
  )
  prepare_lease_successor_event_v2(
    projection,
    event_id,
    lease_renewed_event_kind_v2,
    event_idempotency_key,
    command_idempotency_key,
    renewal.record_ref(),
    renewal.canonical_bytes(),
    [
      for value in renewal.evidence() => value
    ],
    renewal.causation(),
  )
}

///|
/// Prepare an exact-receipt-bound terminal release.
fn prepare_lease_released_v2(
  projection : OrchestrationProjectionV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  release : LeaseReleaseV2,
) -> @storage.CommitRequest raise {
  require_root_binding_verified_v22(projection)
  if release.workflow() != projection.workflow() {
    raise WorkflowMismatch(field="lease_release_v2_prepare_workflow")
  }
  if event_idempotency_key != release.idempotency_key() {
    raise IdempotencyConflict(key=event_idempotency_key)
  }
  ignore(
    require_current_receipt_v2(
      projection,
      release.predecessor_receipt_ref,
      release.predecessor_receipt_digest,
      release.predecessor_receipt_bytes,
      "lease_release_v2_prepare_predecessor",
    ),
  )
  prepare_lease_successor_event_v2(
    projection,
    event_id,
    lease_released_event_kind_v2,
    event_idempotency_key,
    command_idempotency_key,
    release.record_ref(),
    release.canonical_bytes(),
    [
      for value in release.evidence() => value
    ],
    release.causation(),
  )
}

///|
/// Prepare an exact-receipt-bound expiry whose due decision is frozen in its
/// strict 2.1 request-bound operation Admission proof. No caller-supplied
/// ambient time is accepted.
fn prepare_lease_expired_v2(
  projection : OrchestrationProjectionV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  expiry : LeaseExpiryV2,
) -> @storage.CommitRequest raise {
  require_root_binding_verified_v22(projection)
  if expiry.workflow() != projection.workflow() {
    raise WorkflowMismatch(field="lease_expiry_v2_prepare_workflow")
  }
  if event_idempotency_key != expiry.idempotency_key() {
    raise IdempotencyConflict(key=event_idempotency_key)
  }
  ignore(
    require_current_receipt_v2(
      projection,
      expiry.predecessor_receipt_ref,
      expiry.predecessor_receipt_digest,
      expiry.predecessor_receipt_bytes,
      "lease_expiry_v2_prepare_predecessor",
    ),
  )
  prepare_lease_successor_event_v2(
    projection,
    event_id,
    lease_expired_event_kind_v2,
    event_idempotency_key,
    command_idempotency_key,
    expiry.record_ref(),
    expiry.canonical_bytes(),
    [
      for value in expiry.evidence() => value
    ],
    expiry.causation(),
  )
}

///|
/// Prepare a terminal-only reclaim. The exact replay-derived terminal record,
/// CAS head, and strict 2.1 request-bound operation Admission proof authorize
/// succession.
fn prepare_lease_reclaimed_v2(
  projection : OrchestrationProjectionV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  reclaim : LeaseReclaimV2,
) -> @storage.CommitRequest raise {
  require_root_binding_verified_v22(projection)
  if reclaim.workflow() != projection.workflow() {
    raise WorkflowMismatch(field="lease_reclaim_v2_prepare_workflow")
  }
  if event_idempotency_key != reclaim.idempotency_key() {
    raise IdempotencyConflict(key=event_idempotency_key)
  }
  if projection.has_active_lease() {
    raise ScheduleStateViolation(field="lease_reclaim_v2_active")
  }
  guard projection.committed_lease_terminal_receipt() is Some(terminal_receipt) else {
    raise ScheduleStateViolation(field="lease_reclaim_v2_no_terminal")
  }
  terminal_receipt.validate_current(projection)
  if reclaim.terminal_ref != terminal_receipt.receipt_ref() ||
    reclaim.terminal_digest != terminal_receipt.digest() ||
    reclaim.terminal_bytes != terminal_receipt.canonical_bytes() {
    raise ReplayBindingViolation(field="lease_reclaim_v2_prepare_terminal")
  }
  if reclaim.epoch() <= projection.epoch_floor() {
    raise LeaseEpochViolation(
      expected_greater_than=projection.epoch_floor(),
      actual=reclaim.epoch(),
    )
  }
  if reclaim.fencing_token() <= projection.fencing_floor() {
    raise FencingViolation(
      expected_greater_than=projection.fencing_floor(),
      actual=reclaim.fencing_token(),
    )
  }
  prepare_lease_successor_event_v2(
    projection,
    event_id,
    lease_reclaimed_event_kind_v2,
    event_idempotency_key,
    command_idempotency_key,
    reclaim.record_ref(),
    reclaim.canonical_bytes(),
    [
      for value in reclaim.evidence() => value
    ],
    reclaim.causation(),
  )
}

///|
/// Append through the existing domain-neutral StoragePort. The storage CAS and
/// idempotency rules remain the sole mutation boundary.
fn[S : @storage.StoragePort] commit_orchestration_v2(
  store : S,
  request : @storage.CommitRequest,
) -> @storage.CommitResult raise {
  store.commit(request)
}

///|
/// Rebuild semantic V2 state through the existing storage port and strict
/// committed-byte fold. No caller-supplied schedule or lease object participates.
pub fn[S : @storage.StoragePort] replay_orchestration_v2(
  store : S,
  workflow : @contracts.RecordRef,
) -> OrchestrationProjectionV2 raise {
  fold_orchestration_v2(store.replay(workflow))
}
