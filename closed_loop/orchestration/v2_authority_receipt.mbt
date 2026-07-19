///|
/// Opaque proof that one exact lease claim is the current committed lease in an
/// exact replayed projection. This proves lease/fencing ownership only. It is
/// never dispatch, external-effect, application, execution, or domain authority.
///
/// `pub struct` keeps construction private outside this package. There is no
/// public constructor, decoder, or literal-construction surface.
pub struct CommittedLeaseAuthorityReceiptV2 {
  receipt_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  schedule_ref : @contracts.RecordRef
  schedule_digest : @contracts.ContentDigest
  lease_claimed_ref : @contracts.RecordRef
  lease_claimed_digest : @contracts.ContentDigest
  lease_state_ref : @contracts.RecordRef
  lease_state_digest : @contracts.ContentDigest
  owner : @contracts.RecordRef
  observed_at : Int64
  expires_at : Int64
  epoch : Int64
  fencing_token : Int64
  committed_event_ref : @contracts.RecordRef
  committed_event_digest : @contracts.ContentDigest
  projection_sequence : Int64
  projection_revision : Int64
  projection_head_digest : @contracts.ContentDigest
  semantic_projection_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn mint_committed_lease_authority_receipt_v2(
  projection : OrchestrationProjectionV2,
  registration : ScheduleRegisteredV2,
  active : ActiveLeaseV2,
) -> CommittedLeaseAuthorityReceiptV2 raise OrchestrationError {
  if active.schedule_registration_ref() != registration.record_ref() ||
    registration.workflow() != projection.workflow {
    raise RecoveryViolation(field="lease_authority_v2_claim_binding")
  }
  guard projection.last_event_digest is Some(projection_head_digest) else {
    raise RecoveryViolation(field="lease_authority_v2_projection_head")
  }
  let lease_claimed_ref = active.authority_ref()
  let lease_state_ref = active.state_ref()
  let committed_event_ref = active.committed_event_ref()
  let committed_event_digest = committed_event_ref.digest()
  let semantic_projection_digest = projection.digest
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-LEASE-AUTHORITY-RECEIPT-V2/2.0.0")
  writer.string(orchestration_record_version_v2)
  write_ref(writer, projection.workflow)
  write_ref(writer, registration.record_ref())
  write_ref(writer, registration.schedule_ref())
  writer.string(registration.schedule().digest().text())
  write_ref(writer, lease_claimed_ref)
  writer.string(active.authority_digest().text())
  write_ref(writer, lease_state_ref)
  writer.string(active.state_digest().text())
  write_ref(writer, active.owner())
  writer.int64(active.observed_at())
  writer.int64(active.expires_at())
  writer.int64(active.epoch())
  writer.int64(active.fencing_token())
  write_ref(writer, committed_event_ref)
  writer.string(committed_event_digest.text())
  writer.int64(projection.sequence)
  writer.int64(projection.revision)
  writer.string(projection_head_digest.text())
  writer.string(semantic_projection_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref_v2(
      "orchestration-committed-lease-authority-receipt-v2",
      lease_claimed_ref.id(),
      digest,
    ),
    workflow: projection.workflow,
    schedule_registration_ref: registration.record_ref(),
    schedule_ref: registration.schedule_ref(),
    schedule_digest: registration.schedule().digest(),
    lease_claimed_ref,
    lease_claimed_digest: active.authority_digest(),
    lease_state_ref,
    lease_state_digest: active.state_digest(),
    owner: active.owner(),
    observed_at: active.observed_at(),
    expires_at: active.expires_at(),
    epoch: active.epoch(),
    fencing_token: active.fencing_token(),
    committed_event_ref,
    committed_event_digest,
    projection_sequence: projection.sequence,
    projection_revision: projection.revision,
    projection_head_digest,
    semantic_projection_digest,
    canonical,
    digest,
  }
}

///|
/// Mint from the latest exact claim/event pair retained only by successful V2
/// replay. Empty or schedule-only projections have no lease authority.
pub fn OrchestrationProjectionV2::committed_lease_authority_receipt(
  self : OrchestrationProjectionV2,
) -> CommittedLeaseAuthorityReceiptV2? raise OrchestrationError {
  guard self.active_lease is Some(active) else { return None }
  guard self.schedules.search_by(registration => {
      registration.record_ref() == active.schedule_registration_ref()
    })
    is Some(registration_index) else {
    raise RecoveryViolation(field="lease_authority_v2_schedule_registration")
  }
  Some(
    mint_committed_lease_authority_receipt_v2(
      self,
      self.schedules[registration_index],
      active,
    ),
  )
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::lease_authority_ref(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.RecordRef {
  self.lease_claimed_ref
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::lease_authority_digest(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.ContentDigest {
  self.lease_claimed_digest
}

///|
/// Fail-closed validation against the exact current replay and explicit time.
/// A valid result still grants no permission to dispatch or perform an effect.
pub fn CommittedLeaseAuthorityReceiptV2::validate_current(
  self : CommittedLeaseAuthorityReceiptV2,
  projection : OrchestrationProjectionV2,
  now : Int64,
) -> Unit raise OrchestrationError {
  if now < 0L {
    raise MalformedInput(field="lease_authority_v2_now")
  }
  if self.workflow != projection.workflow() {
    raise WorkflowMismatch(field="lease_authority_v2_projection_workflow")
  }
  if self.projection_revision != projection.revision() {
    raise RevisionMismatch(
      expected=self.projection_revision,
      actual=projection.revision(),
    )
  }
  if self.projection_sequence != projection.sequence() {
    raise OrderingViolation(field="lease_authority_v2_projection_sequence")
  }
  if self.semantic_projection_digest != projection.state_digest() {
    raise DigestMismatch(field="lease_authority_v2_semantic_projection")
  }
  if projection.last_event_digest() != Some(self.projection_head_digest) {
    raise DigestMismatch(field="lease_authority_v2_projection_head")
  }
  if @contracts.sha256_digest(self.canonical) != self.digest ||
    self.receipt_ref.digest() != self.digest {
    raise DigestMismatch(field="lease_authority_v2_receipt_integrity")
  }
  guard projection.committed_lease_authority_receipt() is Some(current) else {
    raise ReplayBindingViolation(
      field="lease_authority_v2_current_lease_absent",
    )
  }
  if current.receipt_ref != self.receipt_ref ||
    current.digest != self.digest ||
    current.canonical != self.canonical {
    raise ReplayBindingViolation(field="lease_authority_v2_current_lease")
  }
  if now < self.observed_at {
    raise OrderingViolation(field="lease_authority_v2_before_observed")
  }
  if now >= self.expires_at {
    raise AuthorityExpired(expires_at=self.expires_at, observed_at=now)
  }
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::receipt_ref(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::workflow(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::schedule_registration_ref(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.RecordRef {
  self.schedule_registration_ref
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::schedule_ref(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.RecordRef {
  self.schedule_ref
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::schedule_digest(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.ContentDigest {
  self.schedule_digest
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::lease_claimed_ref(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.RecordRef {
  self.lease_claimed_ref
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::lease_claimed_digest(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.ContentDigest {
  self.lease_claimed_digest
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::lease_state_ref(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.RecordRef {
  self.lease_state_ref
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::lease_state_digest(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.ContentDigest {
  self.lease_state_digest
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::owner(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::observed_at(
  self : CommittedLeaseAuthorityReceiptV2,
) -> Int64 {
  self.observed_at
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::expires_at(
  self : CommittedLeaseAuthorityReceiptV2,
) -> Int64 {
  self.expires_at
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::epoch(
  self : CommittedLeaseAuthorityReceiptV2,
) -> Int64 {
  self.epoch
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::fencing_token(
  self : CommittedLeaseAuthorityReceiptV2,
) -> Int64 {
  self.fencing_token
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::committed_event_ref(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.RecordRef {
  self.committed_event_ref
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::committed_event_digest(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.ContentDigest {
  self.committed_event_digest
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::projection_sequence(
  self : CommittedLeaseAuthorityReceiptV2,
) -> Int64 {
  self.projection_sequence
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::projection_revision(
  self : CommittedLeaseAuthorityReceiptV2,
) -> Int64 {
  self.projection_revision
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::projection_head_digest(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.ContentDigest {
  self.projection_head_digest
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::semantic_projection_digest(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.ContentDigest {
  self.semantic_projection_digest
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::canonical_bytes(
  self : CommittedLeaseAuthorityReceiptV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedLeaseAuthorityReceiptV2::digest(
  self : CommittedLeaseAuthorityReceiptV2,
) -> @contracts.ContentDigest {
  self.digest
}
