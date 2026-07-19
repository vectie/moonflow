///|
let recovery_work_terminal_event_kind_v3 = "work.recovery-terminal.v3"

///|
let recovery_settlement_source_magic_v3 = b"FLOW7/RECOVERY-SETTLEMENT-SOURCE-V3/3.0.0"

///|
let recovery_settlement_set_magic_v3 = b"FLOW7/RECOVERY-SETTLEMENT-SET-V3/3.0.0"

///|
let recovery_work_terminal_magic_v3 = b"FLOW7/RECOVERY-WORK-TERMINAL-V3/3.0.0"

///|
let recovery_lifecycle_candidate_magic_v3 = b"FLOW7/RECOVERY-LIFECYCLE-CANDIDATE-V3/3.0.0"

///|
pub(all) enum RecoverySettlementKindV3 {
  RecoverySettlementKnownSuccessV3
  RecoverySettlementKnownFailureV3
  RecoverySettlementReconciledSuccessV3
  RecoverySettlementReconciledFailureV3
  RecoverySettlementConfirmedNotAppliedV3
} derive(Eq, Debug)

///|
fn RecoverySettlementKindV3::wire(self : RecoverySettlementKindV3) -> String {
  match self {
    RecoverySettlementKnownSuccessV3 => "known_success_v3"
    RecoverySettlementKnownFailureV3 => "known_failure_v3"
    RecoverySettlementReconciledSuccessV3 => "reconciled_success_v3"
    RecoverySettlementReconciledFailureV3 => "reconciled_failure_v3"
    RecoverySettlementConfirmedNotAppliedV3 => "confirmed_not_applied_v3"
  }
}

///|
fn recovery_settlement_kind_from_state_v3(
  state : @effects.EffectRecoveryStateV3,
) -> RecoverySettlementKindV3 raise OrchestrationError {
  match state {
    @effects.RecoveryKnownSuccessV3 => RecoverySettlementKnownSuccessV3
    @effects.RecoveryKnownFailureV3 => RecoverySettlementKnownFailureV3
    @effects.RecoveryReconciledSuccessV3 =>
      RecoverySettlementReconciledSuccessV3
    @effects.RecoveryReconciledFailureV3 =>
      RecoverySettlementReconciledFailureV3
    @effects.RecoveryConfirmedNotAppliedRetryEligibleV3 =>
      RecoverySettlementConfirmedNotAppliedV3
    @effects.RecoveryDispatchEligibleV3
    | @effects.RecoveryDispatchClaimedV3
    | @effects.RecoveryDispatchAttemptedV3
    | @effects.RecoveryUnknownRequiresReconciliationV3
    | @effects.RecoveryReconciliationClaimedV3
    | @effects.RecoveryBackoffPendingV3
    | @effects.RecoveryExhaustedV3
    | @effects.RecoveryManualInterventionV3 =>
      raise RecoveryViolation(field="recovery_settlement_v3_unresolved")
  }
}

///|
fn recovery_settlement_is_success_v3(kind : RecoverySettlementKindV3) -> Bool {
  kind == RecoverySettlementKnownSuccessV3 ||
  kind == RecoverySettlementReconciledSuccessV3
}

///|
fn recovery_settlement_is_failure_v3(kind : RecoverySettlementKindV3) -> Bool {
  kind == RecoverySettlementKnownFailureV3 ||
  kind == RecoverySettlementReconciledFailureV3
}

///|
/// Opaque proof minted only from an exact joint work/governance recovery
/// replay. It is evidence of the replayed outcome, never call authority.
pub struct RecoverySettlementSourceV3 {
  source_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  dispatch_claim_ref : @contracts.RecordRef
  dispatch_claim_digest : @contracts.ContentDigest
  origin_ref : @contracts.RecordRef
  origin_digest : @contracts.ContentDigest
  origin_bytes : Bytes
  kind : RecoverySettlementKindV3
  settled_at : Int64
  recovery_evidence_head : RecoveryEvidenceHeadV3?
  recovery_state_digest : @contracts.ContentDigest
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  governance_workflow : @contracts.RecordRef
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  governance_replay_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn recovery_settlement_source_signing_bytes_v3(
  source_id : String,
  current : CurrentGovernedRecoveryProjectionV3,
  claim : DispatchClaimRecordV3,
  origin_ref : @contracts.RecordRef,
  origin_digest : @contracts.ContentDigest,
  origin_bytes : Bytes,
  kind : RecoverySettlementKindV3,
  settled_at : Int64,
  recovery_state_digest : @contracts.ContentDigest,
  recovery_evidence_head : RecoveryEvidenceHeadV3?,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_settlement_source_magic_v3)
  writer.string("3.0.0")
  writer.string(source_id)
  write_ref(writer, claim.workflow)
  write_ref(writer, claim.governed_subject)
  write_ref(writer, claim.intent_ref)
  write_ref(writer, claim.claim_ref)
  writer.string(claim.digest.text())
  write_ref(writer, origin_ref)
  writer.string(origin_digest.text())
  writer.bytes(origin_bytes)
  writer.string(kind.wire())
  writer.int64(settled_at)
  writer.string(recovery_state_digest.text())
  writer.int64(current.current.work_revision)
  writer.string(current.current.work_head_digest.text())
  writer.string(current.current.work_replay_digest.text())
  write_ref(writer, current.governance_replay.workflow())
  writer.int64(current.current.governance_revision)
  writer.optional_digest(current.current.governance_head_digest)
  writer.string(current.current.governance_replay_digest.text())
  match recovery_evidence_head {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical)
    }
  }
  write_evidence(writer, claim.evidence)
  writer.finish()
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_settlement_source_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> RecoverySettlementSourceV3 raise OrchestrationError {
  if self.current.work.work_terminal is Some(_) {
    raise RecoveryViolation(field="recovery_settlement_v3_after_terminal")
  }
  guard self.current_claim(intent_ref) is Some(claim) else {
    raise RecoveryViolation(field="recovery_settlement_v3_dispatch_claim")
  }
  let kind = recovery_settlement_kind_from_state_v3(self.state_for(intent_ref))
  let (origin_ref, origin_digest, origin_bytes, settled_at) = match kind {
    RecoverySettlementKnownSuccessV3 | RecoverySettlementKnownFailureV3 =>
      match first(self.observations, value => value.intent_ref == intent_ref) {
        Some(value) =>
          (
            value.observation_ref,
            value.digest,
            value.canonical,
            value.observed_at,
          )
        None =>
          raise ReplayBindingViolation(field="recovery_settlement_v3_fact")
      }
    RecoverySettlementReconciledSuccessV3
    | RecoverySettlementReconciledFailureV3
    | RecoverySettlementConfirmedNotAppliedV3 =>
      match self.current_reconciliation_result_v3(intent_ref) {
        Some(value) =>
          (value.result_ref, value.digest, value.canonical, value.observed_at)
        None =>
          raise ReplayBindingViolation(field="recovery_settlement_v3_fact")
      }
  }
  let source_id = "\{intent_ref.id()}:\{kind.wire()}:\{self.current.work_replay_digest.text()}"
  let canonical = recovery_settlement_source_signing_bytes_v3(
    source_id,
    self,
    claim,
    origin_ref,
    origin_digest,
    origin_bytes,
    kind,
    settled_at,
    self.state_digest,
    None,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    source_ref: self_ref_v3(
      "orchestration-recovery-settlement-source-v3", source_id, digest,
    ),
    workflow: claim.workflow,
    governed_subject: claim.governed_subject,
    intent_ref: claim.intent_ref,
    dispatch_claim_ref: claim.claim_ref,
    dispatch_claim_digest: claim.digest,
    origin_ref,
    origin_digest,
    origin_bytes,
    kind,
    settled_at,
    recovery_evidence_head: None,
    recovery_state_digest: self.state_digest,
    work_revision: self.current.work_revision,
    work_head_digest: self.current.work_head_digest,
    work_replay_digest: self.current.work_replay_digest,
    governance_workflow: self.governance_replay.workflow(),
    governance_revision: self.current.governance_revision,
    governance_head_digest: self.current.governance_head_digest,
    governance_replay_digest: self.current.governance_replay_digest,
    evidence: claim.evidence,
    canonical,
    digest,
  }
}

///|
fn RecoverySettlementSourceV3::validate_current_v3(
  self : RecoverySettlementSourceV3,
  current : CurrentGovernedRecoveryProjectionV3,
) -> Unit raise OrchestrationError {
  match self.recovery_evidence_head {
    Some(_) => {
      guard current.current_claim(self.intent_ref) is Some(claim) else {
        raise ReplayBindingViolation(field="recovery_settlement_v3_not_current")
      }
      if current.current.work_revision != self.work_revision ||
        current.current.work_head_digest != self.work_head_digest ||
        current.current.work_replay_digest != self.work_replay_digest ||
        claim.claim_ref != self.dispatch_claim_ref ||
        claim.digest != self.dispatch_claim_digest {
        raise ReplayBindingViolation(field="recovery_settlement_v3_not_current")
      }
      return
    }
    None => ()
  }
  let replayed = current.recovery_settlement_source_v3(self.intent_ref)
  if replayed.source_ref != self.source_ref ||
    replayed.canonical != self.canonical ||
    replayed.digest != self.digest {
    raise ReplayBindingViolation(field="recovery_settlement_v3_not_current")
  }
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::callback_recovery_settlement_source_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> RecoverySettlementSourceV3 raise OrchestrationError {
  if self.current.work.work_terminal is Some(_) ||
    evidence_projection.bound_workflow() != self.current.root_binding.workflow {
    raise RecoveryViolation(field="callback_settlement_v3_current")
  }
  guard latest_settlement_eligible_callback_v3(evidence_projection, intent_ref)
    is Some(integration) else {
    raise RecoveryViolation(field="callback_settlement_v3_unresolved")
  }
  guard self.current_claim(intent_ref) is Some(claim) else {
    raise RecoveryViolation(field="callback_settlement_v3_dispatch_claim")
  }
  let kind = match integration.outcome() {
    @effects.RecoveryKnownSucceededV3 => RecoverySettlementReconciledSuccessV3
    @effects.RecoveryKnownFailedV3 => RecoverySettlementReconciledFailureV3
    @effects.RecoveryConfirmedNotAppliedV3 =>
      RecoverySettlementConfirmedNotAppliedV3
    @effects.RecoveryStillUnknownV3 =>
      raise RecoveryViolation(field="callback_settlement_v3_unresolved")
  }
  let head = evidence_projection.recovery_evidence_head_v3()
  let state_writer = OrchestrationWriter::new()
  state_writer.bytes(b"FLOW7/CALLBACK-SETTLEMENT-STATE-V3/3.0.0")
  state_writer.string(self.state_digest.text())
  state_writer.string(evidence_projection.state_digest().text())
  let state_digest = @contracts.sha256_digest(state_writer.finish())
  let source_id = "\{intent_ref.id()}:\{kind.wire()}:\{integration.digest().text()}"
  let canonical = recovery_settlement_source_signing_bytes_v3(
    source_id,
    self,
    claim,
    integration.record_ref(),
    integration.digest(),
    integration.canonical_bytes(),
    kind,
    integration.retrieved_at(),
    state_digest,
    Some(head),
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    source_ref: self_ref_v3(
      "orchestration-recovery-settlement-source-v3", source_id, digest,
    ),
    workflow: claim.workflow,
    governed_subject: claim.governed_subject,
    intent_ref: claim.intent_ref,
    dispatch_claim_ref: claim.claim_ref,
    dispatch_claim_digest: claim.digest,
    origin_ref: integration.record_ref(),
    origin_digest: integration.digest(),
    origin_bytes: integration.canonical_bytes(),
    kind,
    settled_at: integration.retrieved_at(),
    recovery_evidence_head: Some(head),
    recovery_state_digest: state_digest,
    work_revision: self.current.work_revision,
    work_head_digest: self.current.work_head_digest,
    work_replay_digest: self.current.work_replay_digest,
    governance_workflow: self.governance_replay.workflow(),
    governance_revision: self.current.governance_revision,
    governance_head_digest: self.current.governance_head_digest,
    governance_replay_digest: self.current.governance_replay_digest,
    evidence: claim.evidence,
    canonical,
    digest,
  }
}

///|
pub fn RecoverySettlementSourceV3::record_ref(
  self : RecoverySettlementSourceV3,
) -> @contracts.RecordRef {
  self.source_ref
}

///|
pub fn RecoverySettlementSourceV3::intent_ref(
  self : RecoverySettlementSourceV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn RecoverySettlementSourceV3::kind(
  self : RecoverySettlementSourceV3,
) -> RecoverySettlementKindV3 {
  self.kind
}

///|
pub fn RecoverySettlementSourceV3::origin_ref(
  self : RecoverySettlementSourceV3,
) -> @contracts.RecordRef {
  self.origin_ref
}

///|
pub fn RecoverySettlementSourceV3::from_callback_evidence(
  self : RecoverySettlementSourceV3,
) -> Bool {
  self.recovery_evidence_head is Some(_)
}

///|
pub fn RecoverySettlementSourceV3::work_revision(
  self : RecoverySettlementSourceV3,
) -> Int64 {
  self.work_revision
}

///|
pub fn RecoverySettlementSourceV3::settled_at(
  self : RecoverySettlementSourceV3,
) -> Int64 {
  self.settled_at
}

///|
pub fn RecoverySettlementSourceV3::canonical_bytes(
  self : RecoverySettlementSourceV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoverySettlementSourceV3::digest(
  self : RecoverySettlementSourceV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Complete one-per-owned-intent settlement set. Terminal preparation accepts
/// this set rather than a caller-selected individual outcome.
pub struct RecoverySettlementSetV3 {
  set_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  sources : ReadOnlyArray[RecoverySettlementSourceV3]
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  recovery_state_digest : @contracts.ContentDigest
  recovery_evidence_head : RecoveryEvidenceHeadV3?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_settlement_set_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> RecoverySettlementSetV3 raise OrchestrationError {
  let owned = self.v3_owned_intent_refs()
  if owned.is_empty() {
    raise RecoveryViolation(field="recovery_settlement_v3_empty")
  }
  let sources = [
    for intent_ref in owned => self.recovery_settlement_source_v3(intent_ref)
  ]
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_settlement_set_magic_v3)
  writer.string("3.0.0")
  write_ref(writer, self.current.root_binding.workflow)
  writer.int64(self.current.work_revision)
  writer.string(self.current.work_head_digest.text())
  writer.string(self.current.work_replay_digest.text())
  writer.string(self.state_digest.text())
  writer.byte(0)
  writer.count(sources.length())
  for source in sources {
    writer.bytes(source.canonical)
  }
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    set_ref: self_ref_v3(
      "orchestration-recovery-settlement-set-v3",
      "\{self.current.root_binding.workflow.id()}:\{self.current.work_revision}",
      digest,
    ),
    workflow: self.current.root_binding.workflow,
    sources: ReadOnlyArray::from_array(sources),
    work_revision: self.current.work_revision,
    work_head_digest: self.current.work_head_digest,
    work_replay_digest: self.current.work_replay_digest,
    recovery_state_digest: self.state_digest,
    recovery_evidence_head: None,
    canonical,
    digest,
  }
}

///|
fn RecoverySettlementSetV3::validate_current_v3(
  self : RecoverySettlementSetV3,
  current : CurrentGovernedRecoveryProjectionV3,
) -> Unit raise OrchestrationError {
  if self.recovery_evidence_head is Some(_) {
    if current.current.root_binding.workflow != self.workflow ||
      current.current.work_revision != self.work_revision ||
      current.current.work_head_digest != self.work_head_digest ||
      current.current.work_replay_digest != self.work_replay_digest {
      raise ReplayBindingViolation(
        field="recovery_settlement_set_v3_not_current",
      )
    }
    for source in self.sources {
      source.validate_current_v3(current)
    }
    return
  }
  let replayed = current.recovery_settlement_set_v3()
  if replayed.set_ref != self.set_ref ||
    replayed.canonical != self.canonical ||
    replayed.digest != self.digest {
    raise ReplayBindingViolation(field="recovery_settlement_set_v3_not_current")
  }
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_settlement_set_with_callbacks_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
) -> RecoverySettlementSetV3 raise OrchestrationError {
  if evidence_projection.bound_workflow() != self.current.root_binding.workflow {
    raise ReplayBindingViolation(field="callback_settlement_set_v3_workflow")
  }
  let owned = self.v3_owned_intent_refs()
  if owned.is_empty() {
    raise RecoveryViolation(field="recovery_settlement_v3_empty")
  }
  let sources : Array[RecoverySettlementSourceV3] = []
  for intent_ref in owned {
    match callback_recovery_state_v3(evidence_projection, intent_ref) {
      Some(@effects.RecoveryReconciledSuccessV3)
      | Some(@effects.RecoveryReconciledFailureV3)
      | Some(@effects.RecoveryConfirmedNotAppliedRetryEligibleV3) =>
        sources.push(
          self.callback_recovery_settlement_source_v3(
            evidence_projection, intent_ref,
          ),
        )
      Some(@effects.RecoveryManualInterventionV3)
      | Some(@effects.RecoveryUnknownRequiresReconciliationV3)
      | Some(@effects.RecoveryDispatchEligibleV3)
      | Some(@effects.RecoveryDispatchClaimedV3)
      | Some(@effects.RecoveryDispatchAttemptedV3)
      | Some(@effects.RecoveryKnownSuccessV3)
      | Some(@effects.RecoveryKnownFailureV3)
      | Some(@effects.RecoveryReconciliationClaimedV3)
      | Some(@effects.RecoveryBackoffPendingV3)
      | Some(@effects.RecoveryExhaustedV3) =>
        raise RecoveryViolation(field="callback_settlement_set_v3_unresolved")
      None => sources.push(self.recovery_settlement_source_v3(intent_ref))
    }
  }
  let head = evidence_projection.recovery_evidence_head_v3()
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_settlement_set_magic_v3)
  writer.string("3.0.0")
  write_ref(writer, self.current.root_binding.workflow)
  writer.int64(self.current.work_revision)
  writer.string(self.current.work_head_digest.text())
  writer.string(self.current.work_replay_digest.text())
  writer.string(self.state_digest.text())
  writer.byte(1)
  writer.bytes(head.canonical)
  writer.count(sources.length())
  for source in sources {
    writer.bytes(source.canonical)
  }
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    set_ref: self_ref_v3(
      "orchestration-recovery-settlement-set-v3",
      "\{self.current.root_binding.workflow.id()}:\{self.current.work_revision}:\{head.digest.text()}",
      digest,
    ),
    workflow: self.current.root_binding.workflow,
    sources: ReadOnlyArray::from_array(sources),
    work_revision: self.current.work_revision,
    work_head_digest: self.current.work_head_digest,
    work_replay_digest: self.current.work_replay_digest,
    recovery_state_digest: self.state_digest,
    recovery_evidence_head: Some(head),
    canonical,
    digest,
  }
}

///|
pub fn RecoverySettlementSetV3::record_ref(
  self : RecoverySettlementSetV3,
) -> @contracts.RecordRef {
  self.set_ref
}

///|
pub fn RecoverySettlementSetV3::sources(
  self : RecoverySettlementSetV3,
) -> ReadOnlyArray[RecoverySettlementSourceV3] {
  self.sources
}

///|
pub fn RecoverySettlementSetV3::canonical_bytes(
  self : RecoverySettlementSetV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoverySettlementSetV3::digest(
  self : RecoverySettlementSetV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Opaque current head of the separately registered recovery-evidence stream.
/// The callback projection mints this package-locally; terminal candidates
/// guard it so accepted late evidence cannot race final publication.
pub struct RecoveryEvidenceHeadV3 {
  evidence_workflow : @contracts.RecordRef
  bound_workflow : @contracts.RecordRef
  revision : Int64
  head_digest : @contracts.ContentDigest?
  replay_digest : @contracts.ContentDigest
  state_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_recovery_evidence_head_v3(
  evidence_workflow : @contracts.RecordRef,
  bound_workflow : @contracts.RecordRef,
  revision : Int64,
  head_digest : @contracts.ContentDigest?,
  replay_digest : @contracts.ContentDigest,
  state_digest : @contracts.ContentDigest,
) -> RecoveryEvidenceHeadV3 raise OrchestrationError {
  if evidence_workflow == bound_workflow || revision < 0L {
    raise ReplayBindingViolation(field="recovery_evidence_head_v3")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/RECOVERY-EVIDENCE-HEAD-V3/3.0.0")
  writer.string("3.0.0")
  write_ref(writer, evidence_workflow)
  write_ref(writer, bound_workflow)
  writer.int64(revision)
  writer.optional_digest(head_digest)
  writer.string(replay_digest.text())
  writer.string(state_digest.text())
  let canonical = writer.finish()
  {
    evidence_workflow,
    bound_workflow,
    revision,
    head_digest,
    replay_digest,
    state_digest,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn RecoveryEvidenceHeadV3::workflow(
  self : RecoveryEvidenceHeadV3,
) -> @contracts.RecordRef {
  self.evidence_workflow
}

///|
pub fn RecoveryEvidenceHeadV3::revision(self : RecoveryEvidenceHeadV3) -> Int64 {
  self.revision
}

///|
pub fn RecoveryEvidenceHeadV3::state_digest(
  self : RecoveryEvidenceHeadV3,
) -> @contracts.ContentDigest {
  self.state_digest
}

///|
pub fn RecoveryEvidenceHeadV3::canonical_bytes(
  self : RecoveryEvidenceHeadV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryEvidenceHeadV3::digest(
  self : RecoveryEvidenceHeadV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum RecoveryWorkTerminalOutcomeV3 {
  RecoveryWorkSucceededV3
  RecoveryWorkFailedV3
  RecoveryWorkCancelledAfterConfirmedNotAppliedV3
} derive(Eq, Debug)

///|
fn RecoveryWorkTerminalOutcomeV3::wire(
  self : RecoveryWorkTerminalOutcomeV3,
) -> String {
  match self {
    RecoveryWorkSucceededV3 => "succeeded_v3"
    RecoveryWorkFailedV3 => "failed_v3"
    RecoveryWorkCancelledAfterConfirmedNotAppliedV3 =>
      "cancelled_after_confirmed_not_applied_v3"
  }
}

///|
fn recovery_work_terminal_outcome_from_wire_v3(
  value : String,
) -> RecoveryWorkTerminalOutcomeV3 raise OrchestrationError {
  match value {
    "succeeded_v3" => RecoveryWorkSucceededV3
    "failed_v3" => RecoveryWorkFailedV3
    "cancelled_after_confirmed_not_applied_v3" =>
      RecoveryWorkCancelledAfterConfirmedNotAppliedV3
    _ => raise MalformedInput(field="recovery_terminal_v3_outcome")
  }
}

///|
priv struct DecodedRecoveryWorkTerminalV3 {
  outcome : RecoveryWorkTerminalOutcomeV3
  workflow : @contracts.RecordRef
  settlement_set_ref : @contracts.RecordRef
  settlement_set_digest : @contracts.ContentDigest
  settlement_set_bytes : Bytes
  cancellation_request_ref : @contracts.RecordRef?
  cancellation_request_digest : @contracts.ContentDigest?
  cancellation_request_bytes : Bytes?
  prefix_revision : Int64
  prefix_head_digest : @contracts.ContentDigest
  prefix_replay_digest : @contracts.ContentDigest
  governance_workflow : @contracts.RecordRef
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  governance_replay_digest : @contracts.ContentDigest
  evidence_head_bytes : Bytes
}

///|
fn decode_recovery_work_terminal_v3(
  bytes : Bytes,
) -> DecodedRecoveryWorkTerminalV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_work_terminal_magic_v3 {
    raise MalformedInput(field="recovery_terminal_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="recovery_terminal_v3", version~)
  }
  let outcome = recovery_work_terminal_outcome_from_wire_v3(
    reader.read_string(),
  )
  let workflow = reader.read_ref()
  let settlement_set_ref = reader.read_ref()
  let settlement_set_digest = reader.read_digest()
  let settlement_set_bytes = reader.read_bytes()
  let (
    cancellation_request_ref,
    cancellation_request_digest,
    cancellation_request_bytes,
  ) = match reader.read_byte() {
    0 => (None, None, None)
    1 =>
      (
        Some(reader.read_ref()),
        Some(reader.read_digest()),
        Some(reader.read_bytes()),
      )
    _ => raise MalformedInput(field="recovery_terminal_v3_cancellation")
  }
  let prefix_revision = reader.read_int64()
  let prefix_head_digest = reader.read_digest()
  let prefix_replay_digest = reader.read_digest()
  let governance_workflow = reader.read_ref()
  let governance_revision = reader.read_int64()
  let governance_head_digest = reader.read_optional_digest()
  let governance_replay_digest = reader.read_digest()
  let evidence_head_bytes = reader.read_bytes()
  reader.require_end()
  if prefix_revision < 0L ||
    governance_revision < 0L ||
    settlement_set_ref.digest() != settlement_set_digest ||
    @contracts.sha256_digest(settlement_set_bytes) != settlement_set_digest {
    raise ReplayBindingViolation(field="recovery_terminal_v3_source")
  }
  match
    (
      cancellation_request_ref, cancellation_request_digest, cancellation_request_bytes,
    ) {
    (None, None, None) => ()
    (Some(record), Some(digest), Some(value)) =>
      if record.digest() != digest || @contracts.sha256_digest(value) != digest {
        raise ReplayBindingViolation(field="recovery_terminal_v3_cancellation")
      }
    _ => raise ReplayBindingViolation(field="recovery_terminal_v3_cancellation")
  }
  {
    outcome,
    workflow,
    settlement_set_ref,
    settlement_set_digest,
    settlement_set_bytes,
    cancellation_request_ref,
    cancellation_request_digest,
    cancellation_request_bytes,
    prefix_revision,
    prefix_head_digest,
    prefix_replay_digest,
    governance_workflow,
    governance_revision,
    governance_head_digest,
    governance_replay_digest,
    evidence_head_bytes,
  }
}

///|
pub struct RecoveryLifecycleTerminalCandidateV3 {
  candidate_ref : @contracts.RecordRef
  outcome : RecoveryWorkTerminalOutcomeV3
  settlement_set : RecoverySettlementSetV3
  event : @storage.WorkflowEvent
  guarded_request : @storage.GuardedCommitRequest
  evidence_head : RecoveryEvidenceHeadV3
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn require_recovery_terminal_outcome_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  settlement_set : RecoverySettlementSetV3,
  outcome : RecoveryWorkTerminalOutcomeV3,
) -> Unit raise OrchestrationError {
  settlement_set.validate_current_v3(current)
  let sources = settlement_set.sources
  match outcome {
    RecoveryWorkSucceededV3 =>
      if sources.any(source => !recovery_settlement_is_success_v3(source.kind)) {
        raise RecoveryViolation(field="recovery_terminal_v3_outcome")
      }
    RecoveryWorkFailedV3 =>
      if !sources.any(source => recovery_settlement_is_failure_v3(source.kind)) ||
        sources.any(source => {
          source.kind == RecoverySettlementConfirmedNotAppliedV3
        }) {
        raise RecoveryViolation(field="recovery_terminal_v3_outcome")
      }
    RecoveryWorkCancelledAfterConfirmedNotAppliedV3 =>
      if current.current.work.cancellation is None ||
        sources.any(source => {
          source.kind != RecoverySettlementConfirmedNotAppliedV3
        }) {
        raise CancellationPrecedenceViolation(
          field="recovery_terminal_v3_cancellation",
        )
      }
  }
}

///|
fn prepare_recovery_lifecycle_terminal_candidate_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  settlement_set : RecoverySettlementSetV3,
  evidence_head : RecoveryEvidenceHeadV3,
  outcome : RecoveryWorkTerminalOutcomeV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  if current.current.work.work_terminal is Some(_) ||
    evidence_head.bound_workflow != current.current.root_binding.workflow ||
    evidence_head.evidence_workflow == current.governance_replay.workflow() {
    raise RecoveryViolation(field="recovery_terminal_v3_current")
  }
  match settlement_set.recovery_evidence_head {
    Some(bound) if bound.canonical != evidence_head.canonical ||
      bound.digest != evidence_head.digest =>
      raise ReplayBindingViolation(field="recovery_terminal_v3_evidence_head")
    _ => ()
  }
  require_recovery_terminal_outcome_v3(current, settlement_set, outcome)
  let cancellation = current.current.work.cancellation
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_work_terminal_magic_v3)
  writer.string("3.0.0")
  writer.string(outcome.wire())
  write_ref(writer, current.current.root_binding.workflow)
  write_ref(writer, settlement_set.set_ref)
  writer.string(settlement_set.digest.text())
  writer.bytes(settlement_set.canonical)
  match cancellation {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value.request_ref)
      writer.string(value.digest.text())
      writer.bytes(value.canonical)
    }
  }
  writer.int64(current.current.work_revision)
  writer.string(current.current.work_head_digest.text())
  writer.string(current.current.work_replay_digest.text())
  write_ref(writer, current.governance_replay.workflow())
  writer.int64(current.current.governance_revision)
  writer.optional_digest(current.current.governance_head_digest)
  writer.string(current.current.governance_replay_digest.text())
  writer.bytes(evidence_head.canonical)
  let terminal_canonical = writer.finish()
  let terminal_digest = @contracts.sha256_digest(terminal_canonical)
  let terminal_ref = self_ref_v3(
    "orchestration-recovery-work-terminal-v3",
    "\{settlement_set.set_ref.id()}:\{outcome.wire()}",
    terminal_digest,
  )
  let evidence : Array[@contracts.EvidenceRef] = []
  for source in settlement_set.sources {
    for item in source.evidence {
      if !evidence.any(prior => prior == item) {
        evidence.push(item)
      }
    }
  }
  let event_key = "recovery-terminal-event:\{terminal_digest.text()}"
  let command_key = "recovery-terminal-command:\{terminal_digest.text()}"
  let event = prepare_phase1b_work_event_v22(
    current.current.root_binding.workflow,
    current.current.work_sequence + 1L,
    current.current.work_revision + 1L,
    current.current.work_head_digest,
    terminal_ref.id(),
    recovery_work_terminal_event_kind_v3,
    terminal_ref,
    terminal_canonical,
    settlement_set.sources[0].governed_subject,
    evidence,
    settlement_set.set_ref,
    event_key,
  )
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    current.current.root_binding.workflow,
    current.current.work_revision,
    command_key,
    [event],
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="recovery_terminal_v3_batch")
  }
  let guarded = @storage.GuardedCommitRequest::new(request, [
    @storage.WorkflowHeadGuard::new(
      current.governance_replay.workflow(),
      current.current.governance_revision,
      current.current.governance_head_digest,
      current.current.governance_replay_digest,
    ),
    @storage.WorkflowHeadGuard::new(
      evidence_head.evidence_workflow,
      evidence_head.revision,
      evidence_head.head_digest,
      evidence_head.replay_digest,
    ),
  ]) catch {
    _ => raise ReplayBindingViolation(field="recovery_terminal_v3_guards")
  }
  let candidate_writer = OrchestrationWriter::new()
  candidate_writer.bytes(recovery_lifecycle_candidate_magic_v3)
  candidate_writer.string("3.0.0")
  candidate_writer.string(outcome.wire())
  candidate_writer.bytes(settlement_set.canonical)
  candidate_writer.bytes(evidence_head.canonical)
  candidate_writer.bytes(guarded.canonical_bytes())
  let canonical = candidate_writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    candidate_ref: self_ref_v3(
      "orchestration-recovery-lifecycle-candidate-v3", command_key, digest,
    ),
    outcome,
    settlement_set,
    event,
    guarded_request: guarded,
    evidence_head,
    canonical,
    digest,
  }
}

///|
pub fn prepare_recovery_succeeded_terminal_candidate_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  settlement_set : RecoverySettlementSetV3,
  evidence_head : RecoveryEvidenceHeadV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  prepare_recovery_lifecycle_terminal_candidate_v3(
    current,
    settlement_set,
    evidence_head,
    RecoveryWorkSucceededV3,
  )
}

///|
pub fn prepare_recovery_failed_terminal_candidate_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  settlement_set : RecoverySettlementSetV3,
  evidence_head : RecoveryEvidenceHeadV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  prepare_recovery_lifecycle_terminal_candidate_v3(
    current,
    settlement_set,
    evidence_head,
    RecoveryWorkFailedV3,
  )
}

///|
pub fn prepare_recovery_cancelled_terminal_candidate_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  settlement_set : RecoverySettlementSetV3,
  evidence_head : RecoveryEvidenceHeadV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  prepare_recovery_lifecycle_terminal_candidate_v3(
    current,
    settlement_set,
    evidence_head,
    RecoveryWorkCancelledAfterConfirmedNotAppliedV3,
  )
}

///|
pub(all) enum RecoveryLifecycleTerminalCommitResultV3 {
  RecoveryLifecycleTerminalFreshV3
  RecoveryLifecycleTerminalAlreadyCommittedV3
  RecoveryLifecycleTerminalRaceLostV3
  RecoveryLifecycleTerminalGuardStaleV3
} derive(Eq, Debug)

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_recovery_lifecycle_terminal_v3(
  store : S,
  candidate : RecoveryLifecycleTerminalCandidateV3,
) -> RecoveryLifecycleTerminalCommitResultV3 raise {
  require_phase2_recovery_evidence_guard_profile_v3(
    store,
    candidate.guarded_request,
  )
  try {
    match store.classified_guarded_commit(candidate.guarded_request) {
      @storage.FreshlyApplied(_) => RecoveryLifecycleTerminalFreshV3
      @storage.AlreadyCommitted(_) =>
        RecoveryLifecycleTerminalAlreadyCommittedV3
      @storage.GuardRejected(_) => RecoveryLifecycleTerminalGuardStaleV3
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) =>
      RecoveryLifecycleTerminalRaceLostV3
    error => raise error
  }
}

///|
pub fn RecoveryLifecycleTerminalCandidateV3::record_ref(
  self : RecoveryLifecycleTerminalCandidateV3,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn RecoveryLifecycleTerminalCandidateV3::outcome(
  self : RecoveryLifecycleTerminalCandidateV3,
) -> RecoveryWorkTerminalOutcomeV3 {
  self.outcome
}

///|
pub fn RecoveryLifecycleTerminalCandidateV3::settlements(
  self : RecoveryLifecycleTerminalCandidateV3,
) -> ReadOnlyArray[RecoverySettlementSourceV3] {
  self.settlement_set.sources
}

///|
pub fn RecoveryLifecycleTerminalCandidateV3::canonical_bytes(
  self : RecoveryLifecycleTerminalCandidateV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryLifecycleTerminalCandidateV3::digest(
  self : RecoveryLifecycleTerminalCandidateV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Package-local integration hook for the shared replay fold. It recognizes
/// only the exact one-event/zero-intent V3 terminal transaction.
fn recovery_terminal_event_consumption_v3(
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Int raise OrchestrationError {
  if event.payload().envelope_kind() != recovery_work_terminal_event_kind_v3 {
    return 0
  }
  let bytes = event.payload().payload()
  let terminal = decode_recovery_work_terminal_v3(bytes)
  let digest = @contracts.sha256_digest(bytes)
  if event.payload().subject().kind() !=
    "orchestration-recovery-work-terminal-v3" ||
    event.payload().subject().digest() != digest ||
    event.payload().run_ref() != Some(event.workflow()) ||
    terminal.workflow != event.workflow() ||
    event.revision() != terminal.prefix_revision + 1L ||
    event.previous_event_digest() != Some(terminal.prefix_head_digest) {
    raise ReplayBindingViolation(field="recovery_terminal_v3_transport")
  }
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref() &&
      batch.intent_refs().is_empty()
    })
  if batches.length() != 1 || batches[0].guards().length() != 2 {
    raise ReplayBindingViolation(field="recovery_terminal_v3_batch")
  }
  if batches[0].expected_revision() != terminal.prefix_revision ||
    batches[0].guards()[0].workflow() != terminal.governance_workflow ||
    batches[0].guards()[0].expected_revision() != terminal.governance_revision ||
    batches[0].guards()[0].expected_head_digest() !=
    terminal.governance_head_digest ||
    batches[0].guards()[0].expected_replay_digest() !=
    terminal.governance_replay_digest {
    raise ReplayBindingViolation(field="recovery_terminal_v3_guards")
  }
  1
}

///|
/// Package-local allowlist hook used by the pending-cancellation fold. A V3
/// terminal is legal only after exact settlement preparation; dispatch claim
/// and invocation-start wrappers are deliberately absent from this list.
fn recovery_fact_allowed_after_pending_cancellation_v3(
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Bool raise OrchestrationError {
  let kind = event.payload().envelope_kind()
  kind == reconciliation_claim_event_kind_v3 ||
  kind == reconciliation_query_started_event_kind_v3 ||
  kind == reconciliation_result_event_kind_v3 ||
  kind == recovery_backoff_event_kind_v3 ||
  kind == recovery_automation_stopped_event_kind_v3 ||
  (
    kind == recovery_work_terminal_event_kind_v3 &&
    recovery_terminal_event_consumption_v3(event, replay) == 1
  )
}
