///|
/// Immutable generic concurrency fence. The numeric values must be
/// non-negative and are never acquired or renewed by this package.
pub struct FencingBinding {
  fence_ref : @contracts.RecordRef
  lease_epoch : Int64
  fencing_value : Int64
  canonical : Bytes
}

///|
pub fn FencingBinding::new(
  fence_ref : @contracts.RecordRef,
  lease_epoch : Int64,
  fencing_token : Int64,
) -> FencingBinding raise EffectsError {
  if lease_epoch < 0L {
    raise FencingViolation(field="lease_epoch")
  }
  if fencing_token < 0L {
    raise FencingViolation(field="fencing_token")
  }
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6AFNC1")
  write_ref(writer, fence_ref)
  writer.int64(lease_epoch)
  writer.int64(fencing_token)
  {
    fence_ref,
    lease_epoch,
    fencing_value: fencing_token,
    canonical: writer.finish(),
  }
}

///|
pub fn FencingBinding::fence_ref(self : FencingBinding) -> @contracts.RecordRef {
  self.fence_ref
}

///|
pub fn FencingBinding::lease_epoch(self : FencingBinding) -> Int64 {
  self.lease_epoch
}

///|
pub fn FencingBinding::fencing_token(self : FencingBinding) -> Int64 {
  self.fencing_value
}

///|
pub fn FencingBinding::canonical_bytes(self : FencingBinding) -> Bytes {
  self.canonical
}

///|
pub impl Eq for FencingBinding with fn equal(left, right) {
  left.canonical == right.canonical
}

///|
pub(all) enum ExternalOutcome {
  Succeeded
  Failed
  Unknown
} derive(Eq, Debug)

///|
fn ExternalOutcome::tag(self : ExternalOutcome) -> String {
  match self {
    Succeeded => "succeeded"
    Failed => "failed"
    Unknown => "unknown"
  }
}

///|
pub(all) enum ReconciliationResolution {
  ReconciledSucceeded
  ReconciledFailed
  ReconciledNotApplied
} derive(Eq, Debug)

///|
fn ReconciliationResolution::tag(self : ReconciliationResolution) -> String {
  match self {
    ReconciledSucceeded => "reconciled-succeeded"
    ReconciledFailed => "reconciled-failed"
    ReconciledNotApplied => "reconciled-not-applied"
  }
}

///|
pub(all) enum ReconciliationState {
  RegisteredNoIntent
  DurableIntentDispatchEligible
  DispatchObservationPending
  KnownSuccess
  KnownFailure
  UnknownOutcomeRequiresReconciliation
  ReconciliationRequestedState
  ReconciledSuccessState
  ReconciledFailureState
  ReconciledNotAppliedRetryEligible
} derive(Eq, Debug)

///|
/// Deliberately inert availability/version evidence. It owns no transition.
pub struct CapabilityReceipt {
  record_version : @contracts.Version
  capability_ref : @contracts.RecordRef
  observation : @contracts.WireEnvelope
  observed_at : Int64
  canonical : Bytes
  binding_digest : @contracts.ContentDigest
}

///|
pub fn CapabilityReceipt::new(
  capability_ref : @contracts.RecordRef,
  observation : @contracts.WireEnvelope,
  observed_at : Int64,
) -> CapabilityReceipt {
  let writer = EffectsWriter::new()
  try! writer.bytes(b"MF6ACAP1")
  try! writer.string(effects_record_version)
  try! write_ref(writer, capability_ref)
  try! writer.bytes(@contracts.encode_wire_envelope(observation))
  writer.int64(observed_at)
  let canonical = writer.finish()
  {
    record_version: effects_version(),
    capability_ref,
    observation,
    observed_at,
    canonical,
    binding_digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn CapabilityReceipt::capability_ref(
  self : CapabilityReceipt,
) -> @contracts.RecordRef {
  self.capability_ref
}

///|
pub fn CapabilityReceipt::binding_digest(
  self : CapabilityReceipt,
) -> @contracts.ContentDigest {
  self.binding_digest
}
