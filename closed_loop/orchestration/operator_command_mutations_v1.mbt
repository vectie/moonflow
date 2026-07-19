///|
fn require_operator_work_request_v1(
  surface : MoonFlowOperatorSurfaceV1,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  request : OperatorCommandRequestV1,
  expected_kind : OperatorCommandKindV1,
  subject_ref : @contracts.RecordRef,
  authority_ref : @contracts.RecordRef?,
  review_ref : @contracts.RecordRef?,
  evidence : ArrayView[@contracts.EvidenceRef],
  occurred_at : Int64,
) -> Unit raise OrchestrationError {
  if !operator_request_current_v1(surface, request) ||
    request.kind != expected_kind ||
    request.head_scope != OperatorWorkHeadV1 ||
    request.subject_ref != subject_ref ||
    request.authority_ref != authority_ref ||
    request.review_ref != review_ref ||
    request.expected_head_digest !=
    current.work_replay.head().last_event_digest() ||
    request.expected_replay_digest != current.work_replay.replay_digest() ||
    request.expected_state_digest != current.state_digest() ||
    request.requested_at != occurred_at ||
    evidence_projection.bound_workflow() != current.work_replay.workflow() ||
    evidence_projection.bound_work_replay_digest() !=
    current.work_replay.replay_digest() ||
    !same_evidence(request.evidence, evidence) {
    raise ReplayBindingViolation(field="operator_work_request_v1")
  }
}

///|
fn operator_manual_commit_receipt_v1(
  request : OperatorCommandRequestV1,
  record_ref : @contracts.RecordRef,
  result : ManualInterventionCommitResultV3,
) -> OperatorCommandReceiptV1 {
  match result {
    ManualInterventionFreshV3 =>
      make_operator_command_receipt_v1(
        request,
        OperatorFreshlyPersistedV1,
        true,
        Some(record_ref),
      )
    ManualInterventionAlreadyCommittedV3 =>
      make_operator_command_receipt_v1(
        request,
        OperatorAlreadyPersistedV1,
        true,
        Some(record_ref),
      )
    ManualInterventionRaceLostV3 =>
      make_operator_command_receipt_v1(
        request,
        OperatorRaceLostNonExecutedV1,
        false,
        None,
      )
    ManualInterventionGuardStaleV3 =>
      make_operator_command_receipt_v1(
        request,
        OperatorGuardStaleNonExecutedV1,
        false,
        None,
      )
  }
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_operator_manual_hold_v1(
  store : S,
  surface : MoonFlowOperatorSurfaceV1,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  request : OperatorCommandRequestV1,
  intent_ref : @contracts.RecordRef,
  authority : ManualInterventionAuthorityV3,
  reason : String,
) -> OperatorCommandReceiptV1 raise {
  require_operator_work_request_v1(
    surface,
    current,
    evidence_projection,
    request,
    OperatorManualInterventionResolutionV1,
    intent_ref,
    Some(authority.authority_ref()),
    request.review_ref,
    request.evidence,
    request.requested_at,
  )
  if authority.scope() != ManualInterventionHoldAuthorityV3 {
    raise ReplayBindingViolation(field="operator_manual_hold_authority_v1")
  }
  let candidate = prepare_manual_intervention_hold_v3(
    current,
    evidence_projection,
    "\{request.command_ref.id()}:hold",
    intent_ref,
    authority,
    reason,
    [
      for value in request.evidence => value
    ],
    request.requested_at,
  )
  operator_manual_commit_receipt_v1(
    request,
    candidate.record().record_ref(),
    commit_manual_intervention_v3(store, candidate),
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_operator_manual_resume_v1(
  store : S,
  surface : MoonFlowOperatorSurfaceV1,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  request : OperatorCommandRequestV1,
  intent_ref : @contracts.RecordRef,
  authority : ManualInterventionAuthorityV3,
  reason : String,
) -> OperatorCommandReceiptV1 raise {
  require_operator_work_request_v1(
    surface,
    current,
    evidence_projection,
    request,
    OperatorManualInterventionResolutionV1,
    intent_ref,
    Some(authority.authority_ref()),
    request.review_ref,
    request.evidence,
    request.requested_at,
  )
  if authority.scope() != ManualInterventionResumeAuthorityV3 {
    raise ReplayBindingViolation(field="operator_manual_resume_authority_v1")
  }
  let candidate = prepare_manual_intervention_resume_v3(
    current,
    evidence_projection,
    "\{request.command_ref.id()}:resume",
    intent_ref,
    authority,
    reason,
    [
      for value in request.evidence => value
    ],
    request.requested_at,
  )
  operator_manual_commit_receipt_v1(
    request,
    candidate.record().record_ref(),
    commit_manual_intervention_v3(store, candidate),
  )
}

///|
fn operator_retry_commit_receipt_v1(
  request : OperatorCommandRequestV1,
  record_ref : @contracts.RecordRef,
  result : RecoveryRetryCommitResultV3,
) -> OperatorCommandReceiptV1 {
  match result {
    RecoveryRetryFreshV3 =>
      make_operator_command_receipt_v1(
        request,
        OperatorFreshlyPersistedV1,
        true,
        Some(record_ref),
      )
    RecoveryRetryAlreadyCommittedV3 =>
      make_operator_command_receipt_v1(
        request,
        OperatorAlreadyPersistedV1,
        true,
        Some(record_ref),
      )
    RecoveryRetryRaceLostV3 =>
      make_operator_command_receipt_v1(
        request,
        OperatorRaceLostNonExecutedV1,
        false,
        None,
      )
    RecoveryRetryStaleGovernanceV3 =>
      make_operator_command_receipt_v1(
        request,
        OperatorGuardStaleNonExecutedV1,
        false,
        None,
      )
  }
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_operator_recovery_retry_v1(
  store : S,
  surface : MoonFlowOperatorSurfaceV1,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  request : OperatorCommandRequestV1,
  source : RecoverySettlementSourceV3,
) -> OperatorCommandReceiptV1 raise {
  guard request.authority_ref is Some(authority_ref) else {
    raise ReplayBindingViolation(field="operator_retry_authority_v1")
  }
  require_operator_work_request_v1(
    surface,
    current,
    evidence_projection,
    request,
    OperatorRecoveryRetryV1,
    source.governed_subject,
    Some(authority_ref),
    request.review_ref,
    source.evidence,
    request.requested_at,
  )
  if request.payload.subject() != source.governed_subject {
    raise ReplayBindingViolation(field="operator_retry_payload_v1")
  }
  guard request.payload.idempotency_ref() is Some(external_key) else {
    raise MalformedInput(field="operator_retry_external_idempotency_v1")
  }
  let command_id = request.command_ref.id()
  let candidate = prepare_recovery_retry_candidate_v3(
    current,
    source,
    request.payload,
    "\{command_id}:retry-intent",
    "\{command_id}:retry-schedule",
    "\{command_id}:retry-intent-event",
    "\{command_id}:retry-schedule-event",
    "\{command_id}:retry-outbox",
    "operator-recovery-retry:\{request.digest.text()}",
    external_key,
    request.requested_at,
  )
  operator_retry_commit_receipt_v1(
    request,
    candidate.schedule().record_ref(),
    commit_recovery_retry_v3(store, candidate),
  )
}

///|
fn operator_quarantine_commit_receipt_v1(
  request : OperatorCommandRequestV1,
  record_ref : @contracts.RecordRef,
  result : QuarantineDispositionCommitResultV1,
) -> OperatorCommandReceiptV1 {
  match result {
    QuarantineDispositionFreshV1 =>
      make_operator_command_receipt_v1(
        request,
        OperatorFreshlyPersistedV1,
        true,
        Some(record_ref),
      )
    QuarantineDispositionAlreadyCommittedV1 =>
      make_operator_command_receipt_v1(
        request,
        OperatorAlreadyPersistedV1,
        true,
        Some(record_ref),
      )
    QuarantineDispositionRaceLostV1 =>
      make_operator_command_receipt_v1(
        request,
        OperatorRaceLostNonExecutedV1,
        false,
        None,
      )
    QuarantineDispositionGuardStaleV1 =>
      make_operator_command_receipt_v1(
        request,
        OperatorGuardStaleNonExecutedV1,
        false,
        None,
      )
  }
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_operator_quarantine_disposition_v1(
  store : S,
  surface : MoonFlowOperatorSurfaceV1,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  request : OperatorCommandRequestV1,
  disposition : QuarantineDispositionKindV1,
  reason : String,
) -> OperatorCommandReceiptV1 raise {
  guard request.authority_ref is Some(authority_ref) else {
    raise ReplayBindingViolation(field="operator_quarantine_authority_v1")
  }
  guard request.review_ref is Some(review_ref) else {
    raise ReplayBindingViolation(field="operator_quarantine_review_v1")
  }
  require_operator_work_request_v1(
    surface,
    current,
    evidence_projection,
    request,
    OperatorQuarantineResolutionV1,
    request.subject_ref,
    Some(authority_ref),
    Some(review_ref),
    request.evidence,
    request.requested_at,
  )
  guard first(evidence_projection.quarantined_entries(), value => {
      value.record().record_ref() == request.subject_ref
    })
    is Some(_) else {
    raise ReplayBindingViolation(field="operator_quarantine_subject_v1")
  }
  let candidate = prepare_quarantine_disposition_v1(
    current,
    evidence_projection,
    "\{request.command_ref.id()}:quarantine",
    request.subject_ref,
    disposition,
    authority_ref,
    review_ref,
    reason,
    [
      for value in request.evidence => value
    ],
    request.requested_at,
  )
  operator_quarantine_commit_receipt_v1(
    request,
    candidate.record().record_ref(),
    commit_quarantine_disposition_v1(store, candidate),
  )
}
