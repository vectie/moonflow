///|
/// Opaque proposed clock evidence. It is not a committed `ClockInput` and owns
/// no due, persistence, lease, or acceptance transition.
pub struct ClockProposal {
  record_version : @contracts.Version
  proposal_ref : @contracts.RecordRef
  observation : @contracts.WireEnvelope
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn ClockProposal::new(
  proposal_ref : @contracts.RecordRef,
  observation : @contracts.WireEnvelope,
) -> ClockProposal {
  let writer = OrchestrationWriter::new()
  try! writer.bytes(b"MF7ACLOCKPORT1")
  try! write_ref(writer, proposal_ref)
  try! writer.bytes(@contracts.encode_wire_envelope(observation))
  let canonical = writer.finish()
  {
    record_version: orchestration_version(),
    proposal_ref,
    observation,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn ClockProposal::proposal_ref(
  self : ClockProposal,
) -> @contracts.RecordRef {
  self.proposal_ref
}

///|
pub fn ClockProposal::observation(
  self : ClockProposal,
) -> @contracts.WireEnvelope {
  self.observation
}

///|
pub fn ClockProposal::binding_digest(
  self : ClockProposal,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// A narrow observation boundary only. FLOW-7A contains no implementation or
/// call site, and the result cannot become a committed clock without ordinary
/// authoritative event construction and storage.
pub(open) trait ClockObservationPort {
  fn propose_clock(Self, @contracts.RecordRef, @contracts.RecordRef) -> ClockProposal raise
}

///|
/// Opaque capability/health evidence. It is not ownership, a claim, fencing,
/// an effect observation, an outcome, reconciliation, or retry authority.
pub struct WorkerCapabilityEvidence {
  record_version : @contracts.Version
  capability_ref : @contracts.RecordRef
  evidence : @contracts.WireEnvelope
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn WorkerCapabilityEvidence::new(
  capability_ref : @contracts.RecordRef,
  evidence : @contracts.WireEnvelope,
) -> WorkerCapabilityEvidence {
  let writer = OrchestrationWriter::new()
  try! writer.bytes(b"MF7AWORKERPORT1")
  try! write_ref(writer, capability_ref)
  try! writer.bytes(@contracts.encode_wire_envelope(evidence))
  let canonical = writer.finish()
  {
    record_version: orchestration_version(),
    capability_ref,
    evidence,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn WorkerCapabilityEvidence::capability_ref(
  self : WorkerCapabilityEvidence,
) -> @contracts.RecordRef {
  self.capability_ref
}

///|
pub fn WorkerCapabilityEvidence::evidence(
  self : WorkerCapabilityEvidence,
) -> @contracts.WireEnvelope {
  self.evidence
}

///|
pub fn WorkerCapabilityEvidence::binding_digest(
  self : WorkerCapabilityEvidence,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// A narrow observation boundary only. It cannot create or mutate scheduler,
/// governance, effect, outcome, reconciliation, or terminal state.
pub(open) trait WorkerObservationPort {
  fn sample_due_capability(Self, DueProof) -> WorkerCapabilityEvidence raise
  fn sample_claimed_capability(Self, ClaimedProof) -> WorkerCapabilityEvidence raise
}

///|
/// Public ownership remains in the accepted governance package.
pub type AcceptedGovernancePolicy = @governance.GovernancePolicy
