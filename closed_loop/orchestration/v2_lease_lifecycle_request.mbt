///|
/// Closed verbs for a non-fungible lease lifecycle authorization request.
pub(all) enum LeaseLifecycleVerbV2 {
  RenewLeaseV2
  ReleaseLeaseV2
  ExpireLeaseV2
  ReclaimLeaseV2
} derive(Eq, Debug)

///|
fn LeaseLifecycleVerbV2::wire(self : LeaseLifecycleVerbV2) -> String {
  match self {
    RenewLeaseV2 => "renew"
    ReleaseLeaseV2 => "release"
    ExpireLeaseV2 => "expire"
    ReclaimLeaseV2 => "reclaim"
  }
}

///|
fn decode_lease_lifecycle_verb_v2(
  value : String,
) -> LeaseLifecycleVerbV2 raise OrchestrationError {
  match value {
    "renew" => RenewLeaseV2
    "release" => ReleaseLeaseV2
    "expire" => ExpireLeaseV2
    "reclaim" => ReclaimLeaseV2
    _ => raise MalformedInput(field="lease_lifecycle_request_v2_verb")
  }
}

///|
/// Canonical pre-proof request. A lifecycle authorization proof must bind both
/// requested-work and effect-request to this exact self-addressed record.
pub struct LeaseLifecycleRequestV2 {
  request_ref : @contracts.RecordRef
  verb : LeaseLifecycleVerbV2
  registration_ref : @contracts.RecordRef
  registration_digest : @contracts.ContentDigest
  registration_bytes : Bytes
  predecessor_receipt_ref : @contracts.RecordRef
  predecessor_receipt_digest : @contracts.ContentDigest
  predecessor_receipt_bytes : Bytes
  predecessor_state_ref : @contracts.RecordRef
  predecessor_state_digest : @contracts.ContentDigest
  workflow : @contracts.RecordRef
  owner : @contracts.RecordRef
  requested_ttl : Int64?
  proposed_epoch : Int64
  proposed_fencing_token : Int64
  idempotency_key : String
  causation : @contracts.RecordRef
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn validate_lifecycle_request_shape_v2(
  verb : LeaseLifecycleVerbV2,
  requested_ttl : Int64?,
  proposed_epoch : Int64,
  proposed_fencing_token : Int64,
) -> Unit raise OrchestrationError {
  match verb {
    RenewLeaseV2 | ReclaimLeaseV2 =>
      match requested_ttl {
        Some(value) if value > 0L => ()
        _ => raise TtlViolation(field="lease_lifecycle_request_v2_ttl")
      }
    ReleaseLeaseV2 | ExpireLeaseV2 =>
      if requested_ttl is Some(_) {
        raise TtlViolation(field="lease_lifecycle_request_v2_terminal_ttl")
      }
  }
  if proposed_epoch <= 0L {
    raise LeaseEpochViolation(expected_greater_than=0L, actual=proposed_epoch)
  }
  if proposed_fencing_token <= 0L {
    raise FencingViolation(
      expected_greater_than=0L,
      actual=proposed_fencing_token,
    )
  }
}

///|
fn new_lease_lifecycle_request_v2(
  request_id : String,
  verb : LeaseLifecycleVerbV2,
  registration : ScheduleRegisteredV2,
  predecessor_receipt_ref : @contracts.RecordRef,
  predecessor_receipt_digest : @contracts.ContentDigest,
  predecessor_receipt_bytes : Bytes,
  predecessor_state_ref : @contracts.RecordRef,
  predecessor_state_digest : @contracts.ContentDigest,
  owner : @contracts.RecordRef,
  requested_ttl : Int64?,
  proposed_epoch : Int64,
  proposed_fencing_token : Int64,
  idempotency_key : String,
  causation : @contracts.RecordRef,
) -> LeaseLifecycleRequestV2 raise OrchestrationError {
  require_text(request_id, "lease_lifecycle_request_v2_id")
  require_text(idempotency_key, "lease_lifecycle_request_v2_idempotency_key")
  validate_lifecycle_request_shape_v2(
    verb, requested_ttl, proposed_epoch, proposed_fencing_token,
  )
  if predecessor_receipt_ref.digest() != predecessor_receipt_digest ||
    @contracts.sha256_digest(predecessor_receipt_bytes) !=
    predecessor_receipt_digest {
    raise DigestMismatch(field="lease_lifecycle_request_v2_predecessor_receipt")
  }
  if predecessor_state_ref.digest() != predecessor_state_digest {
    raise DigestMismatch(field="lease_lifecycle_request_v2_predecessor_state")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-LIFECYCLE-REQUEST-V2/2.1.0")
  writer.string("2.1.0")
  writer.string(request_id)
  writer.string(verb.wire())
  write_ref(writer, registration.record_ref())
  writer.string(registration.digest().text())
  writer.bytes(registration.canonical_bytes())
  write_ref(writer, predecessor_receipt_ref)
  writer.string(predecessor_receipt_digest.text())
  writer.bytes(predecessor_receipt_bytes)
  write_ref(writer, predecessor_state_ref)
  writer.string(predecessor_state_digest.text())
  write_ref(writer, registration.workflow())
  write_ref(writer, owner)
  writer.optional_int64(requested_ttl)
  writer.int64(proposed_epoch)
  writer.int64(proposed_fencing_token)
  writer.string(idempotency_key)
  write_ref(writer, causation)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    request_ref: self_ref_v2(
      "orchestration-lease-lifecycle-request-v2", request_id, digest,
    ),
    verb,
    registration_ref: registration.record_ref(),
    registration_digest: registration.digest(),
    registration_bytes: registration.canonical_bytes(),
    predecessor_receipt_ref,
    predecessor_receipt_digest,
    predecessor_receipt_bytes,
    predecessor_state_ref,
    predecessor_state_digest,
    workflow: registration.workflow(),
    owner,
    requested_ttl,
    proposed_epoch,
    proposed_fencing_token,
    idempotency_key,
    causation,
    canonical,
    digest,
  }
}

///|
/// Construct a request for an active lease. Owner and current fencing values
/// are derived from the opaque replay-minted receipt, never caller supplied.
pub fn LeaseLifecycleRequestV2::for_active(
  request_id : String,
  verb : LeaseLifecycleVerbV2,
  registration : ScheduleRegisteredV2,
  receipt : CommittedLeaseAuthorityReceiptV2,
  requested_ttl : Int64?,
  idempotency_key : String,
  causation : @contracts.RecordRef,
) -> LeaseLifecycleRequestV2 raise OrchestrationError {
  if verb == ReclaimLeaseV2 {
    raise ScheduleStateViolation(
      field="lease_lifecycle_request_v2_active_reclaim",
    )
  }
  require_receipt_schedule_v2(
    registration, receipt, "lease_lifecycle_request_v2_registration",
  )
  new_lease_lifecycle_request_v2(
    request_id,
    verb,
    registration,
    receipt.receipt_ref(),
    receipt.digest(),
    receipt.canonical_bytes(),
    receipt.lease_state_ref(),
    receipt.lease_state_digest(),
    receipt.owner(),
    requested_ttl,
    receipt.epoch(),
    receipt.fencing_token(),
    idempotency_key,
    causation,
  )
}

///|
/// Construct a reclaim request from the exact opaque terminal receipt minted
/// by replay. The next owner and strictly greater fencing identity are explicit
/// request semantics; terminal state and registration identity are not.
pub fn LeaseLifecycleRequestV2::for_terminal(
  request_id : String,
  registration : ScheduleRegisteredV2,
  receipt : CommittedLeaseTerminalReceiptV2,
  owner : @contracts.RecordRef,
  requested_ttl : Int64,
  proposed_epoch : Int64,
  proposed_fencing_token : Int64,
  idempotency_key : String,
  causation : @contracts.RecordRef,
) -> LeaseLifecycleRequestV2 raise OrchestrationError {
  if receipt.workflow() != registration.workflow() ||
    receipt.schedule_registration_ref() != registration.record_ref() ||
    receipt.schedule_registration_digest() != registration.digest() {
    raise ReplayBindingViolation(
      field="lease_lifecycle_request_v2_terminal_registration",
    )
  }
  if proposed_epoch <= receipt.epoch() {
    raise LeaseEpochViolation(
      expected_greater_than=receipt.epoch(),
      actual=proposed_epoch,
    )
  }
  if proposed_fencing_token <= receipt.fencing_token() {
    raise FencingViolation(
      expected_greater_than=receipt.fencing_token(),
      actual=proposed_fencing_token,
    )
  }
  new_lease_lifecycle_request_v2(
    request_id,
    ReclaimLeaseV2,
    registration,
    receipt.receipt_ref(),
    receipt.digest(),
    receipt.canonical_bytes(),
    receipt.terminal_ref(),
    receipt.terminal_digest(),
    owner,
    Some(requested_ttl),
    proposed_epoch,
    proposed_fencing_token,
    idempotency_key,
    causation,
  )
}

///|
fn decode_lease_lifecycle_request_v2(
  expected_id : String,
  registration : ScheduleRegisteredV2,
  predecessor_receipt_ref : @contracts.RecordRef,
  predecessor_receipt_digest : @contracts.ContentDigest,
  predecessor_receipt_bytes : Bytes,
  predecessor_state_ref : @contracts.RecordRef,
  predecessor_state_digest : @contracts.ContentDigest,
  bytes : Bytes,
) -> LeaseLifecycleRequestV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/LEASE-LIFECYCLE-REQUEST-V2/2.1.0" {
    raise MalformedInput(field="lease_lifecycle_request_v2_tag")
  }
  if reader.read_string() != "2.1.0" {
    raise UnsupportedVersion(
      field="lease_lifecycle_request_v2",
      version="not-2.1.0",
    )
  }
  if reader.read_string() != expected_id {
    raise IdentityMismatch(field="lease_lifecycle_request_v2_id")
  }
  let verb = decode_lease_lifecycle_verb_v2(reader.read_string())
  let serialized_registration_ref = reader.read_ref()
  let serialized_registration_digest = reader.read_digest()
  let serialized_registration_bytes = reader.read_bytes()
  let serialized_receipt_ref = reader.read_ref()
  let serialized_receipt_digest = reader.read_digest()
  let serialized_receipt_bytes = reader.read_bytes()
  let serialized_state_ref = reader.read_ref()
  let serialized_state_digest = reader.read_digest()
  let workflow = reader.read_ref()
  let owner = reader.read_ref()
  let requested_ttl = reader.read_optional_int64()
  let proposed_epoch = reader.read_int64()
  let proposed_fencing_token = reader.read_int64()
  let idempotency_key = reader.read_string()
  let causation = reader.read_ref()
  reader.require_end()
  if serialized_registration_ref != registration.record_ref() ||
    serialized_registration_digest != registration.digest() ||
    serialized_registration_bytes != registration.canonical_bytes() {
    raise ReplayBindingViolation(
      field="lease_lifecycle_request_v2_registration",
    )
  }
  if serialized_receipt_ref != predecessor_receipt_ref ||
    serialized_receipt_digest != predecessor_receipt_digest ||
    serialized_receipt_bytes != predecessor_receipt_bytes {
    raise ReplayBindingViolation(
      field="lease_lifecycle_request_v2_predecessor_receipt",
    )
  }
  if serialized_state_ref != predecessor_state_ref ||
    serialized_state_digest != predecessor_state_digest {
    raise ReplayBindingViolation(
      field="lease_lifecycle_request_v2_predecessor_state",
    )
  }
  if workflow != registration.workflow() {
    raise WorkflowMismatch(field="lease_lifecycle_request_v2_workflow")
  }
  let decoded = new_lease_lifecycle_request_v2(
    expected_id, verb, registration, predecessor_receipt_ref, predecessor_receipt_digest,
    predecessor_receipt_bytes, predecessor_state_ref, predecessor_state_digest, owner,
    requested_ttl, proposed_epoch, proposed_fencing_token, idempotency_key, causation,
  )
  if decoded.canonical_bytes() != bytes {
    raise DigestMismatch(field="lease_lifecycle_request_v2_canonical")
  }
  decoded
}

///|
pub fn LeaseLifecycleRequestV2::request_ref(
  self : LeaseLifecycleRequestV2,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn LeaseLifecycleRequestV2::verb(
  self : LeaseLifecycleRequestV2,
) -> LeaseLifecycleVerbV2 {
  self.verb
}

///|
pub fn LeaseLifecycleRequestV2::registration_ref(
  self : LeaseLifecycleRequestV2,
) -> @contracts.RecordRef {
  self.registration_ref
}

///|
pub fn LeaseLifecycleRequestV2::registration_digest(
  self : LeaseLifecycleRequestV2,
) -> @contracts.ContentDigest {
  self.registration_digest
}

///|
pub fn LeaseLifecycleRequestV2::predecessor_receipt_ref(
  self : LeaseLifecycleRequestV2,
) -> @contracts.RecordRef {
  self.predecessor_receipt_ref
}

///|
pub fn LeaseLifecycleRequestV2::predecessor_receipt_digest(
  self : LeaseLifecycleRequestV2,
) -> @contracts.ContentDigest {
  self.predecessor_receipt_digest
}

///|
pub fn LeaseLifecycleRequestV2::predecessor_state_ref(
  self : LeaseLifecycleRequestV2,
) -> @contracts.RecordRef {
  self.predecessor_state_ref
}

///|
pub fn LeaseLifecycleRequestV2::predecessor_state_digest(
  self : LeaseLifecycleRequestV2,
) -> @contracts.ContentDigest {
  self.predecessor_state_digest
}

///|
pub fn LeaseLifecycleRequestV2::workflow(
  self : LeaseLifecycleRequestV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn LeaseLifecycleRequestV2::owner(
  self : LeaseLifecycleRequestV2,
) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn LeaseLifecycleRequestV2::requested_ttl(
  self : LeaseLifecycleRequestV2,
) -> Int64? {
  self.requested_ttl
}

///|
pub fn LeaseLifecycleRequestV2::proposed_epoch(
  self : LeaseLifecycleRequestV2,
) -> Int64 {
  self.proposed_epoch
}

///|
pub fn LeaseLifecycleRequestV2::proposed_fencing_token(
  self : LeaseLifecycleRequestV2,
) -> Int64 {
  self.proposed_fencing_token
}

///|
pub fn LeaseLifecycleRequestV2::idempotency_key(
  self : LeaseLifecycleRequestV2,
) -> String {
  self.idempotency_key
}

///|
pub fn LeaseLifecycleRequestV2::causation(
  self : LeaseLifecycleRequestV2,
) -> @contracts.RecordRef {
  self.causation
}

///|
pub fn LeaseLifecycleRequestV2::canonical_bytes(
  self : LeaseLifecycleRequestV2,
) -> Bytes {
  self.canonical
}

///|
pub fn LeaseLifecycleRequestV2::digest(
  self : LeaseLifecycleRequestV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Validated binding between one exact lifecycle request, one strict
/// authorization proof, and one exact replayed active-lease head.
pub struct LeaseLifecycleAuthorizationV2 {
  request : LeaseLifecycleRequestV2
  admission : AdmissionV2
  observed_at : Int64
  operation_deadline : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn require_lifecycle_request_committed_registration_v2(
  request : LeaseLifecycleRequestV2,
  projection : OrchestrationProjectionV2,
) -> Unit raise OrchestrationError {
  guard projection.schedules.search_by(value => {
      value.record_ref() == request.registration_ref
    })
    is Some(index) else {
    raise ReplayBindingViolation(
      field="lease_lifecycle_request_v2_registration_not_committed",
    )
  }
  let committed = projection.schedules[index]
  if committed.digest() != request.registration_digest ||
    committed.canonical_bytes() != request.registration_bytes {
    raise ReplayBindingViolation(
      field="lease_lifecycle_request_v2_registration_not_exact",
    )
  }
}

///|
fn require_lifecycle_operation_head_v2(
  admission : AdmissionV2,
  projection : OrchestrationProjectionV2,
) -> Unit raise OrchestrationError {
  let head = admission.eligibility().authoritative_head()
  guard projection.last_event_digest() is Some(expected_head_digest) else {
    raise ReplayBindingViolation(
      field="lease_lifecycle_operation_v2_head_absent",
    )
  }
  if head.event_ref().digest() != head.event_digest() ||
    head.event_digest() != expected_head_digest ||
    head.sequence() != projection.sequence() ||
    head.revision() != projection.revision() {
    raise ReplayBindingViolation(
      field="lease_lifecycle_operation_v2_authoritative_head",
    )
  }
}

///|
fn require_lifecycle_operation_tuple_v2(
  request : LeaseLifecycleRequestV2,
  admission : AdmissionV2,
) -> Unit raise OrchestrationError {
  let planned = admission.planned()
  if planned.workflow() != request.workflow() {
    raise WorkflowMismatch(
      field="lease_lifecycle_operation_v2_planned_workflow",
    )
  }
  if planned.subject() != request.predecessor_state_ref() {
    raise IdentityMismatch(field="lease_lifecycle_operation_v2_planned_subject")
  }
  if planned.requested_work_ref() != request.request_ref() ||
    planned.requested_work_digest() != request.digest() ||
    planned.effect_request_ref() != request.request_ref() ||
    planned.effect_request_digest() != request.digest() {
    raise EffectProofMismatch(
      field="lease_lifecycle_operation_v2_request_tuple",
    )
  }
  if admission.governance().governed_subject() !=
    request.predecessor_state_ref() {
    raise GovernanceMismatch(
      field="lease_lifecycle_operation_v2_governed_subject",
    )
  }
}

///|
fn require_lifecycle_operation_controls_v2(
  request : LeaseLifecycleRequestV2,
  admission : AdmissionV2,
) -> Array[@contracts.EvidenceRef] raise OrchestrationError {
  let controls = admission.controls()
  if controls.capability() is None {
    raise EffectProofMismatch(field="lease_lifecycle_operation_v2_capability")
  }
  let fencing = match controls.fencing() {
    Some(value) => value
    None =>
      raise EffectProofMismatch(field="lease_lifecycle_operation_v2_fencing")
  }
  if fencing.lease_epoch() != request.proposed_epoch() ||
    fencing.fencing_token() != request.proposed_fencing_token() {
    raise EffectProofMismatch(field="lease_lifecycle_operation_v2_fencing")
  }
  let bindings = controls.evidence()
  if bindings.is_empty() {
    raise EvidenceMismatch(field="lease_lifecycle_operation_v2_evidence_empty")
  }
  let evidence : Array[@contracts.EvidenceRef] = []
  for binding in bindings {
    let item = @contracts.EvidenceRef::new(
      binding.evidence_ref(),
      admission.producer().record_ref(),
      binding.evidence_digest().text(),
    ) catch {
      _ => raise EvidenceMismatch(field="lease_lifecycle_operation_v2_evidence")
    }
    evidence.push(item)
  }
  evidence
}

///|
pub fn LeaseLifecycleAuthorizationV2::for_active(
  request : LeaseLifecycleRequestV2,
  admission : AdmissionV2,
  projection : OrchestrationProjectionV2,
  receipt : CommittedLeaseAuthorityReceiptV2,
) -> LeaseLifecycleAuthorizationV2 raise OrchestrationError {
  require_root_binding_verified_v22(projection)
  if request.verb() == ReclaimLeaseV2 {
    raise ScheduleStateViolation(
      field="lease_lifecycle_operation_v2_active_reclaim",
    )
  }
  ignore(
    require_current_receipt_v2(
      projection,
      request.predecessor_receipt_ref,
      request.predecessor_receipt_digest,
      request.predecessor_receipt_bytes,
      "lease_lifecycle_operation_v2_current_receipt",
    ),
  )
  if receipt.receipt_ref() != request.predecessor_receipt_ref() ||
    receipt.digest() != request.predecessor_receipt_digest() ||
    receipt.canonical_bytes() != request.predecessor_receipt_bytes ||
    receipt.lease_state_ref() != request.predecessor_state_ref() ||
    receipt.lease_state_digest() != request.predecessor_state_digest() {
    raise ReplayBindingViolation(field="lease_lifecycle_operation_v2_receipt")
  }
  if request.owner() != receipt.owner() {
    raise LeaseOwnerViolation(field="lease_lifecycle_operation_v2_owner")
  }
  if request.proposed_epoch() != receipt.epoch() {
    raise ReplayBindingViolation(field="lease_lifecycle_operation_v2_epoch")
  }
  if request.proposed_fencing_token() != receipt.fencing_token() {
    raise ReplayBindingViolation(
      field="lease_lifecycle_operation_v2_fencing_token",
    )
  }
  require_lifecycle_request_committed_registration_v2(request, projection)
  require_lifecycle_operation_tuple_v2(request, admission)
  require_lifecycle_operation_head_v2(admission, projection)
  let observed_at = admission.eligibility().clock()
  if !admission.governance().accepts(observed_at) ||
    !admission.controls().accepts(observed_at) {
    raise AuthorityExpired(
      expires_at=admission.controls().deadline_inclusive(),
      observed_at~,
    )
  }
  match request.verb() {
    RenewLeaseV2 | ReleaseLeaseV2 =>
      if observed_at < receipt.observed_at() ||
        observed_at >= receipt.expires_at() {
        raise AuthorityExpired(expires_at=receipt.expires_at(), observed_at~)
      }
    ExpireLeaseV2 =>
      if observed_at < receipt.expires_at() {
        raise AuthorityExpired(expires_at=receipt.expires_at(), observed_at~)
      }
    ReclaimLeaseV2 => ()
  }
  let evidence = require_lifecycle_operation_controls_v2(request, admission)
  let mut operation_deadline = admission.governance().valid_until_inclusive()
  if admission.controls().deadline_inclusive() < operation_deadline {
    operation_deadline = admission.controls().deadline_inclusive()
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-LIFECYCLE-AUTHORIZATION-V2/2.1.0")
  writer.bytes(request.canonical_bytes())
  writer.string(admission.proof_ref().id())
  writer.bytes(admission.proof_bytes())
  writer.int64(observed_at)
  writer.int64(operation_deadline)
  let canonical = writer.finish()
  {
    request,
    admission,
    observed_at,
    operation_deadline,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
/// Validate an exact reclaim request against the current replay-minted
/// terminal receipt and a fresh authorization proof for that terminal head.
pub fn LeaseLifecycleAuthorizationV2::for_terminal(
  request : LeaseLifecycleRequestV2,
  admission : AdmissionV2,
  projection : OrchestrationProjectionV2,
  receipt : CommittedLeaseTerminalReceiptV2,
) -> LeaseLifecycleAuthorizationV2 raise OrchestrationError {
  require_root_binding_verified_v22(projection)
  if request.verb() != ReclaimLeaseV2 {
    raise ScheduleStateViolation(
      field="lease_lifecycle_operation_v2_terminal_not_reclaim",
    )
  }
  receipt.validate_current(projection)
  if receipt.receipt_ref() != request.predecessor_receipt_ref() ||
    receipt.digest() != request.predecessor_receipt_digest() ||
    receipt.canonical_bytes() != request.predecessor_receipt_bytes ||
    receipt.terminal_ref() != request.predecessor_state_ref() ||
    receipt.terminal_digest() != request.predecessor_state_digest() {
    raise ReplayBindingViolation(
      field="lease_lifecycle_operation_v2_terminal_receipt",
    )
  }
  if request.proposed_epoch() <= projection.epoch_floor() {
    raise LeaseEpochViolation(
      expected_greater_than=projection.epoch_floor(),
      actual=request.proposed_epoch(),
    )
  }
  if request.proposed_fencing_token() <= projection.fencing_floor() {
    raise FencingViolation(
      expected_greater_than=projection.fencing_floor(),
      actual=request.proposed_fencing_token(),
    )
  }
  require_lifecycle_request_committed_registration_v2(request, projection)
  require_lifecycle_operation_tuple_v2(request, admission)
  require_lifecycle_operation_head_v2(admission, projection)
  let observed_at = admission.eligibility().clock()
  if !admission.governance().accepts(observed_at) ||
    !admission.controls().accepts(observed_at) {
    raise AuthorityExpired(
      expires_at=admission.controls().deadline_inclusive(),
      observed_at~,
    )
  }
  if observed_at < receipt.observed_at() {
    raise OrderingViolation(
      field="lease_lifecycle_operation_v2_before_terminal",
    )
  }
  let evidence = require_lifecycle_operation_controls_v2(request, admission)
  let mut operation_deadline = admission.governance().valid_until_inclusive()
  if admission.controls().deadline_inclusive() < operation_deadline {
    operation_deadline = admission.controls().deadline_inclusive()
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-LIFECYCLE-AUTHORIZATION-V2/2.1.0")
  writer.bytes(request.canonical_bytes())
  writer.string(admission.proof_ref().id())
  writer.bytes(admission.proof_bytes())
  writer.int64(observed_at)
  writer.int64(operation_deadline)
  let canonical = writer.finish()
  {
    request,
    admission,
    observed_at,
    operation_deadline,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn LeaseLifecycleAuthorizationV2::request(
  self : LeaseLifecycleAuthorizationV2,
) -> LeaseLifecycleRequestV2 {
  self.request
}

///|
pub fn LeaseLifecycleAuthorizationV2::admission(
  self : LeaseLifecycleAuthorizationV2,
) -> AdmissionV2 {
  self.admission
}

///|
pub fn LeaseLifecycleAuthorizationV2::observed_at(
  self : LeaseLifecycleAuthorizationV2,
) -> Int64 {
  self.observed_at
}

///|
pub fn LeaseLifecycleAuthorizationV2::operation_deadline(
  self : LeaseLifecycleAuthorizationV2,
) -> Int64 {
  self.operation_deadline
}

///|
pub fn LeaseLifecycleAuthorizationV2::evidence(
  self : LeaseLifecycleAuthorizationV2,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn LeaseLifecycleAuthorizationV2::canonical_bytes(
  self : LeaseLifecycleAuthorizationV2,
) -> Bytes {
  self.canonical
}

///|
pub fn LeaseLifecycleAuthorizationV2::digest(
  self : LeaseLifecycleAuthorizationV2,
) -> @contracts.ContentDigest {
  self.digest
}
