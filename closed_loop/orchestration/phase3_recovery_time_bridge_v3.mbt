///|
fn phase3_committed_now_v3(
  time : TimeEvidenceProjectionV3,
) -> Int64 raise OrchestrationError {
  guard time.latest() is Some(observation) else {
    raise ScheduleStateViolation(field="phase3_committed_time_required_v3")
  }
  observation.effective_instant().epoch_millis()
}

///|
/// Phase-2 compatibility bridge that removes caller-supplied `now` from the
/// host path without changing the frozen recovery projection.
pub fn CurrentGovernedRecoveryProjectionV3::recovery_due_actions_from_time_evidence_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  time : TimeEvidenceProjectionV3,
) -> ReadOnlyArray[RecoveryDueActionV3] raise OrchestrationError {
  self.recovery_due_actions_v3(phase3_committed_now_v3(time))
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_due_actions_with_committed_evidence_time_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  time : TimeEvidenceProjectionV3,
) -> ReadOnlyArray[RecoveryDueActionV3] raise OrchestrationError {
  self.recovery_due_actions_with_evidence_v3(
    evidence,
    phase3_committed_now_v3(time),
  )
}

///|
pub fn CurrentThreeStreamRecoverySettlementV3::recovery_due_actions_from_time_evidence_v3(
  self : CurrentThreeStreamRecoverySettlementV3,
  time : TimeEvidenceProjectionV3,
) -> ReadOnlyArray[RecoveryDueActionV3] raise OrchestrationError {
  self.recovery_due_actions_v3(phase3_committed_now_v3(time))
}
