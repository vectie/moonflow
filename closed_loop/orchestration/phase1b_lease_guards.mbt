///|
/// Aggregate-current lease proof. Component replay may still reconstruct an
/// inert historical receipt, but cancellation makes it unavailable here.
pub fn CurrentGovernedClosedLoopProjectionV2::committed_lease_authority_receipt_v2(
  self : CurrentGovernedClosedLoopProjectionV2,
) -> CommittedLeaseAuthorityReceiptV2? raise OrchestrationError {
  if !self.cancellation_authoritative {
    raise ReplayBindingViolation(
      field="cancellation_committed_governance_receipt_required",
    )
  }
  if self.work.cancellation is Some(_) || self.work.work_terminal is Some(_) {
    return None
  }
  self.work.orchestration.committed_lease_authority_receipt()
}

///|
/// Validate an inert component receipt against the aggregate governed head.
pub fn CommittedLeaseAuthorityReceiptV2::validate_governed_current_v2(
  self : CommittedLeaseAuthorityReceiptV2,
  current : CurrentGovernedClosedLoopProjectionV2,
  now : Int64,
) -> Unit raise OrchestrationError {
  guard current.committed_lease_authority_receipt_v2() is Some(replayed) else {
    raise CancellationPrecedenceViolation(
      field="lease_authority_v2_not_governed_current",
    )
  }
  if replayed.receipt_ref() != self.receipt_ref() ||
    replayed.digest() != self.digest() ||
    replayed.canonical_bytes() != self.canonical_bytes() {
    raise CancellationPrecedenceViolation(
      field="lease_authority_v2_not_governed_current",
    )
  }
  self.validate_current(current.work.orchestration, now)
}

///|
pub fn prepare_guarded_lease_claimed_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  authorization : OpenWorkOperationAuthorizationV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  claimed : LeaseClaimedV2,
) -> @storage.CommitRequest raise {
  authorization.require_current_scope(
    current,
    open,
    "lease.claim",
    claimed.record_ref(),
  )
  prepare_lease_claimed_v2(
    current.work.orchestration,
    event_id,
    event_idempotency_key,
    command_idempotency_key,
    claimed,
  )
}

///|
pub fn prepare_guarded_lease_renewed_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  authorization : OpenWorkOperationAuthorizationV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  renewal : LeaseRenewalV2,
) -> @storage.CommitRequest raise {
  authorization.require_current_scope(
    current,
    open,
    "lease.renew",
    renewal.record_ref(),
  )
  prepare_lease_renewed_v2(
    current.work.orchestration,
    event_id,
    event_idempotency_key,
    command_idempotency_key,
    renewal,
  )
}

///|
pub fn prepare_guarded_lease_reclaimed_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  authorization : OpenWorkOperationAuthorizationV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  reclaim : LeaseReclaimV2,
) -> @storage.CommitRequest raise {
  authorization.require_current_scope(
    current,
    open,
    "lease.reclaim",
    reclaim.record_ref(),
  )
  prepare_lease_reclaimed_v2(
    current.work.orchestration,
    event_id,
    event_idempotency_key,
    command_idempotency_key,
    reclaim,
  )
}

///|
let lease_settlement_authority_kind_v22 = "orchestration-lease-settlement-authorization-v2"

///|
/// Exact release/expiry bookkeeping authority, including while cancellation is pending.
pub struct LeaseSettlementAuthorizationV2 {
  authorization_ref : @contracts.RecordRef
  scope : String
  target_ref : @contracts.RecordRef
  lease_receipt_ref : @contracts.RecordRef
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn CurrentGovernedClosedLoopProjectionV2::authorize_lease_settlement_v2(
  self : CurrentGovernedClosedLoopProjectionV2,
  scope : String,
  target_ref : @contracts.RecordRef,
) -> LeaseSettlementAuthorizationV2 raise OrchestrationError {
  if !self.cancellation_authoritative {
    raise ReplayBindingViolation(
      field="cancellation_committed_governance_receipt_required",
    )
  }
  if scope != "lease.release" && scope != "lease.expire" {
    raise CancellationPrecedenceViolation(field="lease_settlement_scope")
  }
  if self.work.work_terminal is Some(_) {
    raise CancellationPrecedenceViolation(field="lease_settlement_terminal")
  }
  guard self.work.orchestration.committed_lease_authority_receipt()
    is Some(receipt) else {
    raise ScheduleStateViolation(field="lease_settlement_no_active")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LEASE-SETTLEMENT-AUTHORIZATION-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  write_current_governed_binding_v22(writer, self)
  writer.string(scope)
  write_ref(writer, target_ref)
  write_ref(writer, receipt.receipt_ref())
  writer.bytes(receipt.canonical_bytes())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  let id = "\{scope}:\{target_ref.id()}:\{self.work_revision}"
  {
    authorization_ref: self_ref_v22(
      lease_settlement_authority_kind_v22, id, digest,
    ),
    scope,
    target_ref,
    lease_receipt_ref: receipt.receipt_ref(),
    work_revision: self.work_revision,
    work_head_digest: self.work_head_digest,
    governance_revision: self.governance_revision,
    governance_head_digest: self.governance_head_digest,
    canonical,
    digest,
  }
}

///|
fn LeaseSettlementAuthorizationV2::require_current(
  self : LeaseSettlementAuthorizationV2,
  current : CurrentGovernedClosedLoopProjectionV2,
  scope : String,
  target_ref : @contracts.RecordRef,
) -> Unit raise OrchestrationError {
  let replayed = current.authorize_lease_settlement_v2(scope, target_ref)
  if replayed.authorization_ref != self.authorization_ref ||
    replayed.scope != self.scope ||
    replayed.target_ref != self.target_ref ||
    replayed.lease_receipt_ref != self.lease_receipt_ref ||
    replayed.work_revision != self.work_revision ||
    replayed.work_head_digest != self.work_head_digest ||
    replayed.governance_revision != self.governance_revision ||
    replayed.governance_head_digest != self.governance_head_digest ||
    replayed.canonical != self.canonical ||
    replayed.digest != self.digest {
    raise CancellationPrecedenceViolation(
      field="lease_settlement_authority_not_current",
    )
  }
}

///|
pub fn prepare_guarded_lease_released_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : LeaseSettlementAuthorizationV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  release : LeaseReleaseV2,
) -> @storage.CommitRequest raise {
  authorization.require_current(current, "lease.release", release.record_ref())
  prepare_lease_released_v2(
    current.work.orchestration,
    event_id,
    event_idempotency_key,
    command_idempotency_key,
    release,
  )
}

///|
pub fn prepare_guarded_lease_expired_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : LeaseSettlementAuthorizationV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  expiry : LeaseExpiryV2,
) -> @storage.CommitRequest raise {
  authorization.require_current(current, "lease.expire", expiry.record_ref())
  prepare_lease_expired_v2(
    current.work.orchestration,
    event_id,
    event_idempotency_key,
    command_idempotency_key,
    expiry,
  )
}
