///|
/// A strict durable renewal of the exact currently committed V2 lease receipt.
pub struct LeaseRenewalV2 {
  record_ref : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  predecessor_receipt_ref : @contracts.RecordRef
  predecessor_receipt_digest : @contracts.ContentDigest
  predecessor_receipt_bytes : Bytes
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
fn require_receipt_schedule_v2(
  registration : ScheduleRegisteredV2,
  receipt : CommittedLeaseAuthorityReceiptV2,
  field : String,
) -> Unit raise OrchestrationError {
  if receipt.workflow() != registration.workflow() ||
    receipt.schedule_registration_ref() != registration.record_ref() ||
    receipt.schedule_ref() != registration.schedule_ref() ||
    receipt.schedule_digest() != registration.schedule().digest() {
    raise ReplayBindingViolation(field~)
  }
}

///|
fn require_exact_predecessor_receipt_v2(
  serialized_ref : @contracts.RecordRef,
  serialized_digest : @contracts.ContentDigest,
  serialized_bytes : Bytes,
  expected : CommittedLeaseAuthorityReceiptV2,
  field : String,
) -> Unit raise OrchestrationError {
  if serialized_ref != expected.receipt_ref() ||
    serialized_digest != expected.digest() ||
    serialized_bytes != expected.canonical_bytes() ||
    @contracts.sha256_digest(serialized_bytes) != serialized_digest {
    raise ReplayBindingViolation(field~)
  }
}

///|
/// Construct a renewal exclusively from the exact current replay receipt and
/// a request-bound operation authorization. No ambient time or loose evidence
/// is accepted by this API.
pub fn LeaseRenewalV2::new(
  renewal_id : String,
  registration : ScheduleRegisteredV2,
  current_receipt : CommittedLeaseAuthorityReceiptV2,
  authorization : LeaseLifecycleAuthorizationV2,
) -> LeaseRenewalV2 raise OrchestrationError {
  require_text(renewal_id, "lease_renewal_v2_id")
  require_receipt_schedule_v2(
    registration, current_receipt, "lease_renewal_v2_schedule",
  )
  let request = authorization.request()
  if request.verb() != RenewLeaseV2 ||
    request.registration_ref() != registration.record_ref() ||
    request.predecessor_receipt_ref() != current_receipt.receipt_ref() ||
    request.predecessor_receipt_digest() != current_receipt.digest() ||
    request.predecessor_state_ref() != current_receipt.lease_state_ref() ||
    request.predecessor_state_digest() != current_receipt.lease_state_digest() {
    raise ReplayBindingViolation(field="lease_renewal_v2_authorization")
  }
  guard request.requested_ttl() is Some(ttl) else {
    raise TtlViolation(field="lease_renewal_v2_ttl")
  }
  let observed_at = authorization.observed_at()
  if observed_at > int64_max - ttl {
    raise ArithmeticOverflow(field="lease_renewal_v2_expiry")
  }
  let expires_at = observed_at + ttl
  if expires_at <= current_receipt.expires_at() {
    raise TtlViolation(field="lease_renewal_v2_not_extended")
  }
  let mut deadline = lease_deadline_v2(
    registration.schedule(),
    registration.schedule().admission(),
  )
  if authorization.operation_deadline() < deadline {
    deadline = authorization.operation_deadline()
  }
  if expires_at > deadline {
    raise AuthorityExpired(expires_at=deadline, observed_at=expires_at)
  }
  let evidence = [ for value in authorization.evidence() => value ]
  let admission = authorization.admission()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-RENEWAL-V2/2.1.0")
  writer.string("2.1.0")
  writer.string(renewal_id)
  write_ref(writer, registration.record_ref())
  writer.string(request.request_ref().id())
  writer.bytes(request.canonical_bytes())
  writer.string(admission.proof_ref().id())
  writer.bytes(admission.proof_bytes())
  write_ref(writer, registration.workflow())
  write_ref(writer, request.owner())
  writer.int64(observed_at)
  writer.int64(expires_at)
  writer.int64(request.proposed_epoch())
  writer.int64(request.proposed_fencing_token())
  writer.string(request.idempotency_key())
  write_evidence(writer, evidence)
  write_ref(writer, request.causation())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v2(
      "orchestration-lease-renewal-v2", renewal_id, digest,
    ),
    schedule_registration_ref: registration.record_ref(),
    predecessor_receipt_ref: current_receipt.receipt_ref(),
    predecessor_receipt_digest: current_receipt.digest(),
    predecessor_receipt_bytes: current_receipt.canonical_bytes(),
    workflow: registration.workflow(),
    owner: request.owner(),
    observed_at,
    expires_at,
    epoch: request.proposed_epoch(),
    fencing_token: request.proposed_fencing_token(),
    idempotency_key: request.idempotency_key(),
    evidence: ReadOnlyArray::from_array(evidence),
    causation: request.causation(),
    canonical,
    digest,
  }
}

///|
pub fn LeaseRenewalV2::decode(
  expected_id : String,
  registration : ScheduleRegisteredV2,
  projection : OrchestrationProjectionV2,
  current_receipt : CommittedLeaseAuthorityReceiptV2,
  bytes : Bytes,
) -> LeaseRenewalV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/LEASE-RENEWAL-V2/2.1.0" ||
    reader.read_string() != "2.1.0" {
    raise MalformedInput(field="lease_renewal_v2_tag")
  }
  if reader.read_string() != expected_id ||
    reader.read_ref() != registration.record_ref() {
    raise IdentityMismatch(field="lease_renewal_v2_identity")
  }
  let request_id = reader.read_string()
  let request_bytes = reader.read_bytes()
  let request = decode_lease_lifecycle_request_v2(
    request_id,
    registration,
    current_receipt.receipt_ref(),
    current_receipt.digest(),
    current_receipt.canonical_bytes(),
    current_receipt.lease_state_ref(),
    current_receipt.lease_state_digest(),
    request_bytes,
  )
  let proof_id = reader.read_string()
  let admission = AdmissionV2::decode(proof_id, reader.read_bytes())
  ignore(reader.read_ref())
  ignore(reader.read_ref())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_string())
  ignore(reader.read_evidence())
  ignore(reader.read_ref())
  reader.require_end()
  let authorization = LeaseLifecycleAuthorizationV2::for_active(
    request, admission, projection, current_receipt,
  )
  let decoded = LeaseRenewalV2::new(
    expected_id, registration, current_receipt, authorization,
  )
  if decoded.canonical_bytes() != bytes {
    raise DigestMismatch(field="lease_renewal_v2_canonical")
  }
  decoded
}

///|
pub fn LeaseRenewalV2::record_ref(
  self : LeaseRenewalV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn LeaseRenewalV2::schedule_registration_ref(
  self : LeaseRenewalV2,
) -> @contracts.RecordRef {
  self.schedule_registration_ref
}

///|
pub fn LeaseRenewalV2::predecessor_receipt_ref(
  self : LeaseRenewalV2,
) -> @contracts.RecordRef {
  self.predecessor_receipt_ref
}

///|
pub fn LeaseRenewalV2::workflow(self : LeaseRenewalV2) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn LeaseRenewalV2::owner(self : LeaseRenewalV2) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn LeaseRenewalV2::observed_at(self : LeaseRenewalV2) -> Int64 {
  self.observed_at
}

///|
pub fn LeaseRenewalV2::expires_at(self : LeaseRenewalV2) -> Int64 {
  self.expires_at
}

///|
pub fn LeaseRenewalV2::epoch(self : LeaseRenewalV2) -> Int64 {
  self.epoch
}

///|
pub fn LeaseRenewalV2::fencing_token(self : LeaseRenewalV2) -> Int64 {
  self.fencing_token
}

///|
pub fn LeaseRenewalV2::idempotency_key(self : LeaseRenewalV2) -> String {
  self.idempotency_key
}

///|
pub fn LeaseRenewalV2::evidence(
  self : LeaseRenewalV2,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn LeaseRenewalV2::causation(self : LeaseRenewalV2) -> @contracts.RecordRef {
  self.causation
}

///|
pub fn LeaseRenewalV2::canonical_bytes(self : LeaseRenewalV2) -> Bytes {
  self.canonical
}

///|
pub fn LeaseRenewalV2::digest(
  self : LeaseRenewalV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// A strict terminal release of the exact currently committed V2 lease receipt.
pub struct LeaseReleaseV2 {
  record_ref : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  predecessor_receipt_ref : @contracts.RecordRef
  predecessor_receipt_digest : @contracts.ContentDigest
  predecessor_receipt_bytes : Bytes
  workflow : @contracts.RecordRef
  owner : @contracts.RecordRef
  observed_at : Int64
  epoch : Int64
  fencing_token : Int64
  idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
/// Canonical release payload shared by the validated constructor and
/// white-box raw-replay parity tests. Package callers still cannot construct a
/// LeaseReleaseV2 value without the strict authorization boundary.
fn canonical_lease_release_payload_v2(
  release_id : String,
  registration : ScheduleRegisteredV2,
  request : LeaseLifecycleRequestV2,
  admission : AdmissionV2,
  observed_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-RELEASE-V2/2.1.0")
  writer.string("2.1.0")
  writer.string(release_id)
  write_ref(writer, registration.record_ref())
  writer.string(request.request_ref().id())
  writer.bytes(request.canonical_bytes())
  writer.string(admission.proof_ref().id())
  writer.bytes(admission.proof_bytes())
  write_ref(writer, registration.workflow())
  write_ref(writer, request.owner())
  writer.int64(observed_at)
  writer.int64(request.proposed_epoch())
  writer.int64(request.proposed_fencing_token())
  writer.string(request.idempotency_key())
  write_evidence(writer, evidence)
  write_ref(writer, request.causation())
  writer.finish()
}

///|
pub fn LeaseReleaseV2::new(
  release_id : String,
  registration : ScheduleRegisteredV2,
  current_receipt : CommittedLeaseAuthorityReceiptV2,
  authorization : LeaseLifecycleAuthorizationV2,
) -> LeaseReleaseV2 raise OrchestrationError {
  require_text(release_id, "lease_release_v2_id")
  require_receipt_schedule_v2(
    registration, current_receipt, "lease_release_v2_schedule",
  )
  let request = authorization.request()
  if request.verb() != ReleaseLeaseV2 ||
    request.requested_ttl() is Some(_) ||
    request.registration_ref() != registration.record_ref() ||
    request.predecessor_receipt_ref() != current_receipt.receipt_ref() ||
    request.predecessor_receipt_digest() != current_receipt.digest() ||
    request.predecessor_state_ref() != current_receipt.lease_state_ref() ||
    request.predecessor_state_digest() != current_receipt.lease_state_digest() {
    raise ReplayBindingViolation(field="lease_release_v2_authorization")
  }
  let observed_at = authorization.observed_at()
  let evidence = [ for value in authorization.evidence() => value ]
  let admission = authorization.admission()
  let canonical = canonical_lease_release_payload_v2(
    release_id, registration, request, admission, observed_at, evidence,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v2(
      "orchestration-lease-release-v2", release_id, digest,
    ),
    schedule_registration_ref: registration.record_ref(),
    predecessor_receipt_ref: current_receipt.receipt_ref(),
    predecessor_receipt_digest: current_receipt.digest(),
    predecessor_receipt_bytes: current_receipt.canonical_bytes(),
    workflow: registration.workflow(),
    owner: request.owner(),
    observed_at,
    epoch: request.proposed_epoch(),
    fencing_token: request.proposed_fencing_token(),
    idempotency_key: request.idempotency_key(),
    evidence: ReadOnlyArray::from_array(evidence),
    causation: request.causation(),
    canonical,
    digest,
  }
}

///|
pub fn LeaseReleaseV2::decode(
  expected_id : String,
  registration : ScheduleRegisteredV2,
  projection : OrchestrationProjectionV2,
  current_receipt : CommittedLeaseAuthorityReceiptV2,
  bytes : Bytes,
) -> LeaseReleaseV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/LEASE-RELEASE-V2/2.1.0" ||
    reader.read_string() != "2.1.0" {
    raise MalformedInput(field="lease_release_v2_tag")
  }
  if reader.read_string() != expected_id ||
    reader.read_ref() != registration.record_ref() {
    raise IdentityMismatch(field="lease_release_v2_identity")
  }
  let request_id = reader.read_string()
  let request = decode_lease_lifecycle_request_v2(
    request_id,
    registration,
    current_receipt.receipt_ref(),
    current_receipt.digest(),
    current_receipt.canonical_bytes(),
    current_receipt.lease_state_ref(),
    current_receipt.lease_state_digest(),
    reader.read_bytes(),
  )
  let proof_id = reader.read_string()
  let admission = AdmissionV2::decode(proof_id, reader.read_bytes())
  ignore(reader.read_ref())
  ignore(reader.read_ref())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_string())
  ignore(reader.read_evidence())
  ignore(reader.read_ref())
  reader.require_end()
  let authorization = LeaseLifecycleAuthorizationV2::for_active(
    request, admission, projection, current_receipt,
  )
  let decoded = LeaseReleaseV2::new(
    expected_id, registration, current_receipt, authorization,
  )
  if decoded.canonical_bytes() != bytes {
    raise DigestMismatch(field="lease_release_v2_canonical")
  }
  decoded
}

///|
pub fn LeaseReleaseV2::record_ref(
  self : LeaseReleaseV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn LeaseReleaseV2::workflow(self : LeaseReleaseV2) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn LeaseReleaseV2::owner(self : LeaseReleaseV2) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn LeaseReleaseV2::observed_at(self : LeaseReleaseV2) -> Int64 {
  self.observed_at
}

///|
pub fn LeaseReleaseV2::epoch(self : LeaseReleaseV2) -> Int64 {
  self.epoch
}

///|
pub fn LeaseReleaseV2::fencing_token(self : LeaseReleaseV2) -> Int64 {
  self.fencing_token
}

///|
pub fn LeaseReleaseV2::idempotency_key(self : LeaseReleaseV2) -> String {
  self.idempotency_key
}

///|
pub fn LeaseReleaseV2::evidence(
  self : LeaseReleaseV2,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn LeaseReleaseV2::causation(self : LeaseReleaseV2) -> @contracts.RecordRef {
  self.causation
}

///|
pub fn LeaseReleaseV2::canonical_bytes(self : LeaseReleaseV2) -> Bytes {
  self.canonical
}

///|
pub fn LeaseReleaseV2::digest(
  self : LeaseReleaseV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// A strict terminal expiry carrying the exact canonical clock observation.
pub struct LeaseExpiryV2 {
  record_ref : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  predecessor_receipt_ref : @contracts.RecordRef
  predecessor_receipt_digest : @contracts.ContentDigest
  predecessor_receipt_bytes : Bytes
  workflow : @contracts.RecordRef
  owner : @contracts.RecordRef
  observed_at : Int64
  epoch : Int64
  fencing_token : Int64
  idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn LeaseExpiryV2::new(
  expiry_id : String,
  registration : ScheduleRegisteredV2,
  current_receipt : CommittedLeaseAuthorityReceiptV2,
  authorization : LeaseLifecycleAuthorizationV2,
) -> LeaseExpiryV2 raise OrchestrationError {
  require_text(expiry_id, "lease_expiry_v2_id")
  require_receipt_schedule_v2(
    registration, current_receipt, "lease_expiry_v2_schedule",
  )
  let request = authorization.request()
  if request.verb() != ExpireLeaseV2 ||
    request.requested_ttl() is Some(_) ||
    request.registration_ref() != registration.record_ref() ||
    request.predecessor_receipt_ref() != current_receipt.receipt_ref() ||
    request.predecessor_receipt_digest() != current_receipt.digest() ||
    request.predecessor_state_ref() != current_receipt.lease_state_ref() ||
    request.predecessor_state_digest() != current_receipt.lease_state_digest() {
    raise ReplayBindingViolation(field="lease_expiry_v2_authorization")
  }
  let observed_at = authorization.observed_at()
  let evidence = [ for value in authorization.evidence() => value ]
  let admission = authorization.admission()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-EXPIRY-V2/2.1.0")
  writer.string("2.1.0")
  writer.string(expiry_id)
  write_ref(writer, registration.record_ref())
  writer.string(request.request_ref().id())
  writer.bytes(request.canonical_bytes())
  writer.string(admission.proof_ref().id())
  writer.bytes(admission.proof_bytes())
  write_ref(writer, registration.workflow())
  write_ref(writer, request.owner())
  writer.int64(observed_at)
  writer.int64(request.proposed_epoch())
  writer.int64(request.proposed_fencing_token())
  writer.string(request.idempotency_key())
  write_evidence(writer, evidence)
  write_ref(writer, request.causation())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v2("orchestration-lease-expiry-v2", expiry_id, digest),
    schedule_registration_ref: registration.record_ref(),
    predecessor_receipt_ref: current_receipt.receipt_ref(),
    predecessor_receipt_digest: current_receipt.digest(),
    predecessor_receipt_bytes: current_receipt.canonical_bytes(),
    workflow: registration.workflow(),
    owner: request.owner(),
    observed_at,
    epoch: request.proposed_epoch(),
    fencing_token: request.proposed_fencing_token(),
    idempotency_key: request.idempotency_key(),
    evidence: ReadOnlyArray::from_array(evidence),
    causation: request.causation(),
    canonical,
    digest,
  }
}

///|
pub fn LeaseExpiryV2::decode(
  expected_id : String,
  registration : ScheduleRegisteredV2,
  projection : OrchestrationProjectionV2,
  current_receipt : CommittedLeaseAuthorityReceiptV2,
  bytes : Bytes,
) -> LeaseExpiryV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/LEASE-EXPIRY-V2/2.1.0" ||
    reader.read_string() != "2.1.0" {
    raise MalformedInput(field="lease_expiry_v2_tag")
  }
  if reader.read_string() != expected_id ||
    reader.read_ref() != registration.record_ref() {
    raise IdentityMismatch(field="lease_expiry_v2_identity")
  }
  let request_id = reader.read_string()
  let request = decode_lease_lifecycle_request_v2(
    request_id,
    registration,
    current_receipt.receipt_ref(),
    current_receipt.digest(),
    current_receipt.canonical_bytes(),
    current_receipt.lease_state_ref(),
    current_receipt.lease_state_digest(),
    reader.read_bytes(),
  )
  let proof_id = reader.read_string()
  let admission = AdmissionV2::decode(proof_id, reader.read_bytes())
  ignore(reader.read_ref())
  ignore(reader.read_ref())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_string())
  ignore(reader.read_evidence())
  ignore(reader.read_ref())
  reader.require_end()
  let authorization = LeaseLifecycleAuthorizationV2::for_active(
    request, admission, projection, current_receipt,
  )
  let decoded = LeaseExpiryV2::new(
    expected_id, registration, current_receipt, authorization,
  )
  if decoded.canonical_bytes() != bytes {
    raise DigestMismatch(field="lease_expiry_v2_canonical")
  }
  decoded
}

///|
pub fn LeaseExpiryV2::record_ref(self : LeaseExpiryV2) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn LeaseExpiryV2::workflow(self : LeaseExpiryV2) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn LeaseExpiryV2::owner(self : LeaseExpiryV2) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn LeaseExpiryV2::observed_at(self : LeaseExpiryV2) -> Int64 {
  self.observed_at
}

///|
pub fn LeaseExpiryV2::epoch(self : LeaseExpiryV2) -> Int64 {
  self.epoch
}

///|
pub fn LeaseExpiryV2::fencing_token(self : LeaseExpiryV2) -> Int64 {
  self.fencing_token
}

///|
pub fn LeaseExpiryV2::idempotency_key(self : LeaseExpiryV2) -> String {
  self.idempotency_key
}

///|
pub fn LeaseExpiryV2::evidence(
  self : LeaseExpiryV2,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn LeaseExpiryV2::causation(self : LeaseExpiryV2) -> @contracts.RecordRef {
  self.causation
}

///|
pub fn LeaseExpiryV2::canonical_bytes(self : LeaseExpiryV2) -> Bytes {
  self.canonical
}

///|
pub fn LeaseExpiryV2::digest(self : LeaseExpiryV2) -> @contracts.ContentDigest {
  self.digest
}

///|
/// A successor claim authorized by a committed release/expiry, not by
/// reinterpreting the initial AdmissionV2 fencing identity.
pub struct LeaseReclaimV2 {
  record_ref : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  terminal_ref : @contracts.RecordRef
  terminal_digest : @contracts.ContentDigest
  terminal_bytes : Bytes
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
pub fn LeaseReclaimV2::new(
  reclaim_id : String,
  registration : ScheduleRegisteredV2,
  terminal_receipt : CommittedLeaseTerminalReceiptV2,
  authorization : LeaseLifecycleAuthorizationV2,
) -> LeaseReclaimV2 raise OrchestrationError {
  require_text(reclaim_id, "lease_reclaim_v2_id")
  let request = authorization.request()
  if request.verb() != ReclaimLeaseV2 ||
    request.registration_ref() != registration.record_ref() ||
    request.predecessor_receipt_ref() != terminal_receipt.receipt_ref() ||
    request.predecessor_receipt_digest() != terminal_receipt.digest() ||
    request.predecessor_state_ref() != terminal_receipt.terminal_ref() ||
    request.predecessor_state_digest() != terminal_receipt.terminal_digest() {
    raise ReplayBindingViolation(field="lease_reclaim_v2_authorization")
  }
  guard request.requested_ttl() is Some(ttl) else {
    raise TtlViolation(field="lease_reclaim_v2_ttl")
  }
  let observed_at = authorization.observed_at()
  if observed_at > int64_max - ttl {
    raise ArithmeticOverflow(field="lease_reclaim_v2_expiry")
  }
  let expires_at = observed_at + ttl
  let mut deadline = lease_deadline_v2(
    registration.schedule(),
    registration.schedule().admission(),
  )
  if authorization.operation_deadline() < deadline {
    deadline = authorization.operation_deadline()
  }
  if expires_at > deadline {
    raise AuthorityExpired(expires_at=deadline, observed_at=expires_at)
  }
  let evidence = [ for value in authorization.evidence() => value ]
  let admission = authorization.admission()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-RECLAIM-V2/2.1.0")
  writer.string("2.1.0")
  writer.string(reclaim_id)
  write_ref(writer, registration.record_ref())
  writer.string(request.request_ref().id())
  writer.bytes(request.canonical_bytes())
  writer.string(admission.proof_ref().id())
  writer.bytes(admission.proof_bytes())
  write_ref(writer, registration.workflow())
  write_ref(writer, request.owner())
  writer.int64(observed_at)
  writer.int64(expires_at)
  writer.int64(request.proposed_epoch())
  writer.int64(request.proposed_fencing_token())
  writer.string(request.idempotency_key())
  write_evidence(writer, evidence)
  write_ref(writer, request.causation())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v2(
      "orchestration-lease-reclaim-v2", reclaim_id, digest,
    ),
    schedule_registration_ref: registration.record_ref(),
    terminal_ref: terminal_receipt.receipt_ref(),
    terminal_digest: terminal_receipt.digest(),
    terminal_bytes: terminal_receipt.canonical_bytes(),
    workflow: registration.workflow(),
    owner: request.owner(),
    observed_at,
    expires_at,
    epoch: request.proposed_epoch(),
    fencing_token: request.proposed_fencing_token(),
    idempotency_key: request.idempotency_key(),
    evidence: ReadOnlyArray::from_array(evidence),
    causation: request.causation(),
    canonical,
    digest,
  }
}

///|
pub fn LeaseReclaimV2::decode(
  expected_id : String,
  registration : ScheduleRegisteredV2,
  projection : OrchestrationProjectionV2,
  terminal_receipt : CommittedLeaseTerminalReceiptV2,
  bytes : Bytes,
) -> LeaseReclaimV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/LEASE-RECLAIM-V2/2.1.0" ||
    reader.read_string() != "2.1.0" {
    raise MalformedInput(field="lease_reclaim_v2_tag")
  }
  if reader.read_string() != expected_id ||
    reader.read_ref() != registration.record_ref() {
    raise IdentityMismatch(field="lease_reclaim_v2_identity")
  }
  let request_id = reader.read_string()
  let request = decode_lease_lifecycle_request_v2(
    request_id,
    registration,
    terminal_receipt.receipt_ref(),
    terminal_receipt.digest(),
    terminal_receipt.canonical_bytes(),
    terminal_receipt.terminal_ref(),
    terminal_receipt.terminal_digest(),
    reader.read_bytes(),
  )
  let proof_id = reader.read_string()
  let admission = AdmissionV2::decode(proof_id, reader.read_bytes())
  ignore(reader.read_ref())
  ignore(reader.read_ref())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_int64())
  ignore(reader.read_string())
  ignore(reader.read_evidence())
  ignore(reader.read_ref())
  reader.require_end()
  let authorization = LeaseLifecycleAuthorizationV2::for_terminal(
    request, admission, projection, terminal_receipt,
  )
  let decoded = LeaseReclaimV2::new(
    expected_id, registration, terminal_receipt, authorization,
  )
  if decoded.canonical_bytes() != bytes {
    raise DigestMismatch(field="lease_reclaim_v2_canonical")
  }
  decoded
}

///|
pub fn LeaseReclaimV2::record_ref(
  self : LeaseReclaimV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn LeaseReclaimV2::workflow(self : LeaseReclaimV2) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn LeaseReclaimV2::owner(self : LeaseReclaimV2) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn LeaseReclaimV2::observed_at(self : LeaseReclaimV2) -> Int64 {
  self.observed_at
}

///|
pub fn LeaseReclaimV2::expires_at(self : LeaseReclaimV2) -> Int64 {
  self.expires_at
}

///|
pub fn LeaseReclaimV2::epoch(self : LeaseReclaimV2) -> Int64 {
  self.epoch
}

///|
pub fn LeaseReclaimV2::fencing_token(self : LeaseReclaimV2) -> Int64 {
  self.fencing_token
}

///|
pub fn LeaseReclaimV2::idempotency_key(self : LeaseReclaimV2) -> String {
  self.idempotency_key
}

///|
pub fn LeaseReclaimV2::evidence(
  self : LeaseReclaimV2,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn LeaseReclaimV2::causation(self : LeaseReclaimV2) -> @contracts.RecordRef {
  self.causation
}

///|
pub fn LeaseReclaimV2::canonical_bytes(self : LeaseReclaimV2) -> Bytes {
  self.canonical
}

///|
pub fn LeaseReclaimV2::digest(
  self : LeaseReclaimV2,
) -> @contracts.ContentDigest {
  self.digest
}
