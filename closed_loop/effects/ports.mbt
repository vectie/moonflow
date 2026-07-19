///|
/// Opaque adapter observation. It cannot carry or construct governance state.
pub struct AttemptObservation {
  record_version : @contracts.Version
  attempt_ref : @contracts.RecordRef
  observation : @contracts.WireEnvelope
  capability_receipt : CapabilityReceipt?
}

///|
pub fn AttemptObservation::new(
  attempt_ref : @contracts.RecordRef,
  observation : @contracts.WireEnvelope,
  capability_receipt? : CapabilityReceipt,
) -> AttemptObservation {
  {
    record_version: effects_version(),
    attempt_ref,
    observation,
    capability_receipt,
  }
}

///|
pub fn AttemptObservation::attempt_ref(
  self : AttemptObservation,
) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
/// Narrow type boundary only. FLOW-6A contains no implementation or call site.
priv trait AttemptAdapterPort {
  fn observe_attempt(Self, AttemptRegistration) -> AttemptObservation raise
}

///|
/// Proof-carrying input created only by authoritative replay projection.
pub struct DispatchEligibleIntent {
  record_version : @contracts.Version
  intent : EffectIntent
  authoritative_replay_digest : @contracts.ContentDigest
}

///|
pub fn DispatchEligibleIntent::intent(
  self : DispatchEligibleIntent,
) -> EffectIntent {
  self.intent
}

///|
pub fn DispatchEligibleIntent::authoritative_replay_digest(
  self : DispatchEligibleIntent,
) -> @contracts.ContentDigest {
  self.authoritative_replay_digest
}

///|
/// Narrow type boundary only. It returns an opaque observation and owns no
/// retry, persistence, governance, or delivery transition.
priv trait EffectDispatcherPort {
  fn observe_dispatch(Self, DispatchEligibleIntent) -> DispatchObservation raise
}
