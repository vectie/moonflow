///|
/// Authoritative three-stream recovery settlement. This view is the only V3
/// terminal preparation surface that derives callback settlement from replayed
/// evidence instead of accepting caller-supplied settlement bytes.
pub struct CurrentThreeStreamRecoverySettlementV3 {
  governed : CurrentGovernedRecoveryProjectionV3
  evidence : CurrentRecoveryEvidenceProjectionV3
  settlements : RecoverySettlementSetV3
  evidence_head : RecoveryEvidenceHeadV3
  state_digest : @contracts.ContentDigest
}

///|
pub fn join_three_stream_recovery_settlement_v3(
  governed : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
) -> CurrentThreeStreamRecoverySettlementV3 raise OrchestrationError {
  if evidence.bound_workflow() != governed.current.root_binding.workflow ||
    evidence.bound_work_replay_digest() != governed.work_replay.replay_digest() {
    raise ReplayBindingViolation(field="three_stream_recovery_work_binding_v3")
  }
  let manual = fold_manual_intervention_v3(governed.work_replay)
  require_no_active_manual_intervention_v3(
    manual,
    governed.v3_owned_intent_refs(),
  )
  let settlements = governed.recovery_settlement_set_with_callbacks_v3(evidence)
  let evidence_head = evidence.recovery_evidence_head_v3()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CURRENT-THREE-STREAM-RECOVERY-SETTLEMENT-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(governed.state_digest.text())
  writer.string(evidence.state_digest().text())
  writer.bytes(settlements.canonical)
  writer.bytes(evidence_head.canonical)
  {
    governed,
    evidence,
    settlements,
    evidence_head,
    state_digest: @contracts.sha256_digest(writer.finish()),
  }
}

///|
pub fn CurrentThreeStreamRecoverySettlementV3::workflow(
  self : CurrentThreeStreamRecoverySettlementV3,
) -> @contracts.RecordRef {
  self.governed.current.root_binding.workflow
}

///|
pub fn CurrentThreeStreamRecoverySettlementV3::settlement_set(
  self : CurrentThreeStreamRecoverySettlementV3,
) -> RecoverySettlementSetV3 {
  self.settlements
}

///|
pub fn CurrentThreeStreamRecoverySettlementV3::evidence_head(
  self : CurrentThreeStreamRecoverySettlementV3,
) -> RecoveryEvidenceHeadV3 {
  self.evidence_head
}

///|
pub fn CurrentThreeStreamRecoverySettlementV3::state_digest(
  self : CurrentThreeStreamRecoverySettlementV3,
) -> @contracts.ContentDigest {
  self.state_digest
}

///|
pub fn CurrentThreeStreamRecoverySettlementV3::prepare_succeeded_terminal(
  self : CurrentThreeStreamRecoverySettlementV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  prepare_recovery_lifecycle_terminal_candidate_v3(
    self.governed,
    self.settlements,
    self.evidence_head,
    RecoveryWorkSucceededV3,
  )
}

///|
pub fn CurrentThreeStreamRecoverySettlementV3::prepare_failed_terminal(
  self : CurrentThreeStreamRecoverySettlementV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  prepare_recovery_lifecycle_terminal_candidate_v3(
    self.governed,
    self.settlements,
    self.evidence_head,
    RecoveryWorkFailedV3,
  )
}

///|
pub fn CurrentThreeStreamRecoverySettlementV3::prepare_cancelled_terminal(
  self : CurrentThreeStreamRecoverySettlementV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  prepare_recovery_lifecycle_terminal_candidate_v3(
    self.governed,
    self.settlements,
    self.evidence_head,
    RecoveryWorkCancelledAfterConfirmedNotAppliedV3,
  )
}

///|
fn decode_recovery_evidence_head_v3(
  bytes : Bytes,
) -> RecoveryEvidenceHeadV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/RECOVERY-EVIDENCE-HEAD-V3/3.0.0" {
    raise MalformedInput(field="three_stream_evidence_head_magic_v3")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="three_stream_evidence_head_v3", version~)
  }
  let value = make_recovery_evidence_head_v3(
    reader.read_ref(),
    reader.read_ref(),
    reader.read_int64(),
    reader.read_optional_digest(),
    reader.read_digest(),
    reader.read_digest(),
  )
  reader.require_end()
  if value.canonical != bytes {
    raise ReplayBindingViolation(
      field="three_stream_evidence_head_canonical_v3",
    )
  }
  value
}

///|
pub struct ThreeStreamRecoveryTerminalReceiptV3 {
  receipt_ref : @contracts.RecordRef
  terminal_ref : @contracts.RecordRef
  outcome : RecoveryWorkTerminalOutcomeV3
  settlement_set_ref : @contracts.RecordRef
  work_prefix_revision : Int64
  governance_revision : Int64
  evidence_revision : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn expected_three_stream_terminal_candidate_v3(
  current : CurrentThreeStreamRecoverySettlementV3,
  outcome : RecoveryWorkTerminalOutcomeV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  match outcome {
    RecoveryWorkSucceededV3 => current.prepare_succeeded_terminal()
    RecoveryWorkFailedV3 => current.prepare_failed_terminal()
    RecoveryWorkCancelledAfterConfirmedNotAppliedV3 =>
      current.prepare_cancelled_terminal()
  }
}

///|
/// Replays all three exact historical prefixes and regenerates the expected
/// terminal candidate. Embedded settlement bytes are compared only after the
/// independently replayed callback evidence has produced a fresh settlement.
pub fn validate_three_stream_recovery_terminal_v3(
  empty : @effects.EffectsProjection,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
  evidence_binding : RecoveryEvidenceStreamBindingV3,
  evidence_replay : @storage.ReplayResult,
  terminal_event_ref : @contracts.RecordRef,
) -> ThreeStreamRecoveryTerminalReceiptV3 raise OrchestrationError {
  let terminal_events = work_replay
    .events()
    .filter(event => {
      event.event_ref() == terminal_event_ref &&
      event.payload().envelope_kind() == recovery_work_terminal_event_kind_v3
    })
  if terminal_events.length() != 1 {
    raise ReplayBindingViolation(field="three_stream_terminal_event_v3")
  }
  let terminal_event = terminal_events[0]
  let terminal = decode_recovery_work_terminal_v3(
    terminal_event.payload().payload(),
  )
  let stored_evidence_head = decode_recovery_evidence_head_v3(
    terminal.evidence_head_bytes,
  )
  let work_prefix = verified_prefix_v3(
    work_replay,
    terminal.prefix_revision,
    "three_stream_terminal_work_prefix_v3",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    terminal.governance_revision,
    "three_stream_terminal_governance_prefix_v3",
  )
  let evidence_prefix = verified_prefix_v3(
    evidence_replay,
    stored_evidence_head.revision,
    "three_stream_terminal_evidence_prefix_v3",
  )
  if work_prefix.head().last_event_digest() != Some(terminal.prefix_head_digest) ||
    work_prefix.replay_digest() != terminal.prefix_replay_digest ||
    governance_prefix.workflow() != terminal.governance_workflow ||
    governance_prefix.head().last_event_digest() !=
    terminal.governance_head_digest ||
    governance_prefix.replay_digest() != terminal.governance_replay_digest ||
    evidence_prefix.workflow() != stored_evidence_head.evidence_workflow ||
    evidence_prefix.head().last_event_digest() !=
    stored_evidence_head.head_digest ||
    evidence_prefix.replay_digest() != stored_evidence_head.replay_digest {
    raise ReplayBindingViolation(field="three_stream_terminal_exact_heads_v3")
  }
  let governed = fold_governed_recovery_v3(
    empty, work_prefix, governance_prefix,
  )
  let evidence = fold_recovery_evidence_stream_v3(
    evidence_binding, evidence_prefix, work_prefix,
  )
  if evidence.state_digest() != stored_evidence_head.state_digest {
    raise ReplayBindingViolation(
      field="three_stream_terminal_evidence_state_v3",
    )
  }
  let current = join_three_stream_recovery_settlement_v3(governed, evidence)
  let expected = expected_three_stream_terminal_candidate_v3(
    current,
    terminal.outcome,
  )
  if expected.event.event_ref() != terminal_event.event_ref() ||
    expected.event.canonical_bytes() != terminal_event.canonical_bytes() ||
    expected.settlement_set.set_ref != terminal.settlement_set_ref ||
    expected.settlement_set.digest != terminal.settlement_set_digest ||
    expected.settlement_set.canonical != terminal.settlement_set_bytes ||
    expected.evidence_head.canonical != terminal.evidence_head_bytes {
    raise ReplayBindingViolation(
      field="three_stream_terminal_reconstruction_v3",
    )
  }
  ignore(recovery_terminal_event_consumption_v3(terminal_event, work_replay))
  let terminal_batches = work_replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == terminal_event.event_ref()
    })
  let terminal_digest = @contracts.sha256_digest(
    terminal_event.payload().payload(),
  )
  if terminal_batches.length() != 1 ||
    terminal_batches[0].command_idempotency_key() !=
    "recovery-terminal-command:\{terminal_digest.text()}" ||
    terminal_batches[0].guards().length() != 2 {
    raise ReplayBindingViolation(field="three_stream_terminal_batch_v3")
  }
  let evidence_guard = terminal_batches[0].guards()[1]
  if evidence_guard.workflow() != stored_evidence_head.evidence_workflow ||
    evidence_guard.expected_revision() != stored_evidence_head.revision ||
    evidence_guard.expected_head_digest() != stored_evidence_head.head_digest ||
    evidence_guard.expected_replay_digest() !=
    stored_evidence_head.replay_digest {
    raise ReplayBindingViolation(
      field="three_stream_terminal_evidence_guard_v3",
    )
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/THREE-STREAM-RECOVERY-TERMINAL-RECEIPT-V3/3.0.0")
  writer.string("3.0.0")
  write_ref(writer, terminal_event.event_ref())
  writer.string(terminal.outcome.wire())
  write_ref(writer, expected.settlement_set.set_ref)
  writer.int64(terminal.prefix_revision)
  writer.int64(terminal.governance_revision)
  writer.int64(stored_evidence_head.revision)
  writer.string(current.state_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref_v3(
      "orchestration-three-stream-terminal-receipt-v3",
      terminal_event.event_ref().id(),
      digest,
    ),
    terminal_ref: terminal_event.event_ref(),
    outcome: terminal.outcome,
    settlement_set_ref: expected.settlement_set.set_ref,
    work_prefix_revision: terminal.prefix_revision,
    governance_revision: terminal.governance_revision,
    evidence_revision: stored_evidence_head.revision,
    canonical,
    digest,
  }
}

///|
pub fn ThreeStreamRecoveryTerminalReceiptV3::record_ref(
  self : ThreeStreamRecoveryTerminalReceiptV3,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn ThreeStreamRecoveryTerminalReceiptV3::terminal_ref(
  self : ThreeStreamRecoveryTerminalReceiptV3,
) -> @contracts.RecordRef {
  self.terminal_ref
}

///|
pub fn ThreeStreamRecoveryTerminalReceiptV3::outcome(
  self : ThreeStreamRecoveryTerminalReceiptV3,
) -> RecoveryWorkTerminalOutcomeV3 {
  self.outcome
}

///|
pub fn ThreeStreamRecoveryTerminalReceiptV3::settlement_set_ref(
  self : ThreeStreamRecoveryTerminalReceiptV3,
) -> @contracts.RecordRef {
  self.settlement_set_ref
}

///|
pub fn ThreeStreamRecoveryTerminalReceiptV3::canonical_bytes(
  self : ThreeStreamRecoveryTerminalReceiptV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ThreeStreamRecoveryTerminalReceiptV3::digest(
  self : ThreeStreamRecoveryTerminalReceiptV3,
) -> @contracts.ContentDigest {
  self.digest
}
