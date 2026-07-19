///|
pub(all) enum OperatorCommandKindV1 {
  OperatorReconcileQueryV1
  OperatorRecoveryRetryV1
  OperatorQuarantineResolutionV1
  OperatorManualInterventionResolutionV1
  OperatorFinalizationDispositionV1
  OperatorDeliveryAuthorizationV1
  OperatorOutcomeAppendV1
  OperatorOutcomeCorrectionV1
  OperatorOfflineEvaluationV1
  OperatorHumanAdoptV1
  OperatorHumanRejectV1
} derive(Eq, Debug)

///|
fn OperatorCommandKindV1::wire(self : OperatorCommandKindV1) -> String {
  match self {
    OperatorReconcileQueryV1 => "reconcile-query"
    OperatorRecoveryRetryV1 => "recovery-retry"
    OperatorQuarantineResolutionV1 => "quarantine-resolution"
    OperatorManualInterventionResolutionV1 => "manual-intervention-resolution"
    OperatorFinalizationDispositionV1 => "finalization-disposition"
    OperatorDeliveryAuthorizationV1 => "delivery-authorization"
    OperatorOutcomeAppendV1 => "outcome-append"
    OperatorOutcomeCorrectionV1 => "outcome-correction"
    OperatorOfflineEvaluationV1 => "offline-evaluation"
    OperatorHumanAdoptV1 => "human-adopt"
    OperatorHumanRejectV1 => "human-reject"
  }
}

///|
pub(all) enum OperatorHeadScopeV1 {
  OperatorWorkHeadV1
  OperatorFinalLearningHeadV1
} derive(Eq, Debug)

///|
fn OperatorHeadScopeV1::wire(self : OperatorHeadScopeV1) -> String {
  match self {
    OperatorWorkHeadV1 => "work"
    OperatorFinalLearningHeadV1 => "final-learning"
  }
}

///|
pub struct OperatorCommandRequestV1 {
  command_ref : @contracts.RecordRef
  run_id : String
  kind : OperatorCommandKindV1
  head_scope : OperatorHeadScopeV1
  subject_ref : @contracts.RecordRef
  authority_ref : @contracts.RecordRef?
  review_ref : @contracts.RecordRef?
  expected_head_digest : @contracts.ContentDigest?
  expected_replay_digest : @contracts.ContentDigest
  expected_state_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  payload : @contracts.WireEnvelope
  requested_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn OperatorCommandRequestV1::new(
  command_id : String,
  run_id : String,
  kind : OperatorCommandKindV1,
  head_scope : OperatorHeadScopeV1,
  subject_ref : @contracts.RecordRef,
  authority_ref : @contracts.RecordRef?,
  review_ref : @contracts.RecordRef?,
  expected_head_digest : @contracts.ContentDigest?,
  expected_replay_digest : @contracts.ContentDigest,
  expected_state_digest : @contracts.ContentDigest,
  evidence : Array[@contracts.EvidenceRef],
  payload : @contracts.WireEnvelope,
  requested_at : Int64,
) -> OperatorCommandRequestV1 raise OrchestrationError {
  require_text(command_id, "operator_command_id_v1")
  require_text(run_id, "operator_command_run_id_v1")
  if requested_at < 0L ||
    evidence.is_empty() ||
    payload.subject() != subject_ref {
    raise MalformedInput(field="operator_command_binding_v1")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/OPERATOR-COMMAND-REQUEST-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(command_id)
  writer.string(run_id)
  writer.string(kind.wire())
  writer.string(head_scope.wire())
  write_ref(writer, subject_ref)
  match authority_ref {
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
    None => writer.byte(0)
  }
  match review_ref {
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
    None => writer.byte(0)
  }
  writer.optional_digest(expected_head_digest)
  writer.string(expected_replay_digest.text())
  writer.string(expected_state_digest.text())
  write_evidence(writer, evidence)
  writer.bytes(@contracts.encode_wire_envelope(payload))
  writer.int64(requested_at)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    command_ref: self_ref(
      "orchestration-operator-command-request-v1", command_id, digest,
    ),
    run_id,
    kind,
    head_scope,
    subject_ref,
    authority_ref,
    review_ref,
    expected_head_digest,
    expected_replay_digest,
    expected_state_digest,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    payload,
    requested_at,
    canonical,
    digest,
  }
}

///|
pub(all) enum OperatorCommandDispositionV1 {
  OperatorPreparedForExistingCommitV1(String)
  OperatorAdapterRequiredNonExecutedV1(String)
  OperatorAuthorityRequiredNonExecutedV1
  OperatorReviewRequiredNonExecutedV1
  OperatorStaleHeadNonExecutedV1
  OperatorDurableApiUnavailableNonExecutedV1(String)
  OperatorFreshlyPersistedV1
  OperatorAlreadyPersistedV1
  OperatorRaceLostNonExecutedV1
  OperatorGuardStaleNonExecutedV1
  OperatorRejectedNonExecutedV1(String)
} derive(Eq, Debug)

///|
fn operator_disposition_wire_v1(value : OperatorCommandDispositionV1) -> String {
  match value {
    OperatorPreparedForExistingCommitV1(api) => "prepared:" + api
    OperatorAdapterRequiredNonExecutedV1(adapter) =>
      "adapter-required:" + adapter
    OperatorAuthorityRequiredNonExecutedV1 => "authority-required"
    OperatorReviewRequiredNonExecutedV1 => "review-required"
    OperatorStaleHeadNonExecutedV1 => "stale-head"
    OperatorDurableApiUnavailableNonExecutedV1(api) =>
      "durable-api-unavailable:" + api
    OperatorFreshlyPersistedV1 => "freshly-persisted"
    OperatorAlreadyPersistedV1 => "already-persisted"
    OperatorRaceLostNonExecutedV1 => "race-lost"
    OperatorGuardStaleNonExecutedV1 => "guard-stale"
    OperatorRejectedNonExecutedV1(reason) => "rejected:" + reason
  }
}

///|
pub struct OperatorCommandReceiptV1 {
  receipt_ref : @contracts.RecordRef
  command_ref : @contracts.RecordRef
  disposition : OperatorCommandDispositionV1
  effect_executed : Bool
  record_persisted : Bool
  durable_receipt_ref : @contracts.RecordRef?
  recorded_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_operator_command_receipt_v1(
  request : OperatorCommandRequestV1,
  disposition : OperatorCommandDispositionV1,
  record_persisted : Bool,
  durable_receipt_ref : @contracts.RecordRef?,
) -> OperatorCommandReceiptV1 {
  let effect_executed = false
  let writer = OrchestrationWriter::new()
  try! writer.bytes(b"FLOW7/OPERATOR-COMMAND-RECEIPT-V1/1.0.0")
  try! writer.string("1.0.0")
  try! write_ref(writer, request.command_ref)
  try! writer.string(operator_disposition_wire_v1(disposition))
  try! writer.byte(if effect_executed { 1 } else { 0 })
  try! writer.byte(if record_persisted { 1 } else { 0 })
  match durable_receipt_ref {
    Some(value) => {
      try! writer.byte(1)
      try! write_ref(writer, value)
    }
    None => try! writer.byte(0)
  }
  try! writer.int64(request.requested_at)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: try! self_ref(
      "orchestration-operator-command-receipt-v1",
      request.command_ref.id(),
      digest,
    ),
    command_ref: request.command_ref,
    disposition,
    effect_executed,
    record_persisted,
    durable_receipt_ref,
    recorded_at: request.requested_at,
    canonical,
    digest,
  }
}

///|
fn operator_command_requires_review_v1(kind : OperatorCommandKindV1) -> Bool {
  kind == OperatorQuarantineResolutionV1 ||
  kind == OperatorFinalizationDispositionV1 ||
  kind == OperatorDeliveryAuthorizationV1 ||
  kind == OperatorHumanAdoptV1 ||
  kind == OperatorHumanRejectV1
}

///|
fn operator_request_current_v1(
  surface : MoonFlowOperatorSurfaceV1,
  request : OperatorCommandRequestV1,
) -> Bool {
  if request.run_id != surface.run_id ||
    request.requested_at != surface.recorded_at {
    return false
  }
  match request.head_scope {
    OperatorWorkHeadV1 =>
      request.expected_head_digest == surface.work_head_digest &&
      request.expected_replay_digest == surface.work_replay_digest &&
      request.expected_state_digest == surface.recovery_state_digest
    OperatorFinalLearningHeadV1 =>
      request.expected_head_digest == surface.final_learning_head_digest &&
      surface.final_learning_replay_digest ==
      Some(request.expected_replay_digest) &&
      surface.final_learning_state_digest == Some(request.expected_state_digest)
  }
}

///|
/// Pure routing boundary used by hosts before constructing typed commit inputs.
/// It never performs a provider call or claims that an external effect ran.
pub fn route_operator_command_v1(
  surface : MoonFlowOperatorSurfaceV1,
  request : OperatorCommandRequestV1,
) -> OperatorCommandReceiptV1 {
  if !operator_request_current_v1(surface, request) {
    return make_operator_command_receipt_v1(
      request,
      OperatorStaleHeadNonExecutedV1,
      false,
      None,
    )
  }
  if request.authority_ref is None {
    return make_operator_command_receipt_v1(
      request,
      OperatorAuthorityRequiredNonExecutedV1,
      false,
      None,
    )
  }
  if operator_command_requires_review_v1(request.kind) &&
    request.review_ref is None {
    return make_operator_command_receipt_v1(
      request,
      OperatorReviewRequiredNonExecutedV1,
      false,
      None,
    )
  }
  let disposition = match request.kind {
    OperatorReconcileQueryV1 =>
      OperatorAdapterRequiredNonExecutedV1("GuardedRecoveryQueryPortV3")
    OperatorRecoveryRetryV1 =>
      OperatorPreparedForExistingCommitV1(
        "prepare_recovery_retry_candidate_v3+commit_recovery_retry_v3",
      )
    OperatorQuarantineResolutionV1 =>
      OperatorPreparedForExistingCommitV1(
        "prepare_quarantine_disposition_v1+commit_quarantine_disposition_v1",
      )
    OperatorManualInterventionResolutionV1 =>
      OperatorPreparedForExistingCommitV1(
        "prepare_manual_intervention_hold_v3|prepare_manual_intervention_resume_v3+commit_manual_intervention_v3",
      )
    OperatorFinalizationDispositionV1 =>
      OperatorPreparedForExistingCommitV1(
        "persist_final_deliverable_decision_v1",
      )
    OperatorDeliveryAuthorizationV1 =>
      OperatorPreparedForExistingCommitV1(
        "persist_governed_delivery_receipt_v1",
      )
    OperatorOutcomeAppendV1 | OperatorOutcomeCorrectionV1 =>
      OperatorPreparedForExistingCommitV1("persist_outcome_observation_v1")
    OperatorOfflineEvaluationV1 =>
      OperatorPreparedForExistingCommitV1(
        "persist_offline_proposal_evaluation_v1",
      )
    OperatorHumanAdoptV1 | OperatorHumanRejectV1 =>
      OperatorPreparedForExistingCommitV1("persist_human_version_decision_v1")
  }
  make_operator_command_receipt_v1(request, disposition, false, None)
}

///|
fn operator_persistence_receipt_v1(
  request : OperatorCommandRequestV1,
  result : FinalLearningPersistenceResultV1,
) -> OperatorCommandReceiptV1 {
  match result {
    FinalLearningFreshlyPersistedV1(receipt) =>
      make_operator_command_receipt_v1(
        request,
        OperatorFreshlyPersistedV1,
        true,
        Some(receipt.record_ref()),
      )
    FinalLearningAlreadyPersistedV1(receipt) =>
      make_operator_command_receipt_v1(
        request,
        OperatorAlreadyPersistedV1,
        true,
        Some(receipt.record_ref()),
      )
    FinalLearningRaceLostV1 =>
      make_operator_command_receipt_v1(
        request,
        OperatorRaceLostNonExecutedV1,
        false,
        None,
      )
    FinalLearningGuardStaleV1(_) =>
      make_operator_command_receipt_v1(
        request,
        OperatorGuardStaleNonExecutedV1,
        false,
        None,
      )
  }
}

///|
fn require_operator_final_learning_request_v1(
  current : CurrentFinalLearningProjectionV1,
  request : OperatorCommandRequestV1,
  expected_kind : OperatorCommandKindV1,
  subject_ref : @contracts.RecordRef,
  authority_ref : @contracts.RecordRef?,
  review_ref : @contracts.RecordRef?,
  evidence : ReadOnlyArray[@contracts.EvidenceRef],
  occurred_at : Int64,
) -> Unit raise OrchestrationError {
  if request.kind != expected_kind ||
    request.head_scope != OperatorFinalLearningHeadV1 ||
    request.subject_ref != subject_ref ||
    request.authority_ref != authority_ref ||
    request.review_ref != review_ref ||
    request.expected_head_digest != current.replay.head().last_event_digest() ||
    request.expected_replay_digest != current.replay.replay_digest() ||
    request.expected_state_digest != current.state_digest() ||
    request.requested_at != occurred_at ||
    !same_evidence(request.evidence, evidence) {
    raise ReplayBindingViolation(field="operator_final_learning_request_v1")
  }
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_operator_finalization_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  current : CurrentFinalLearningProjectionV1,
  request : OperatorCommandRequestV1,
  decision : FinalDeliverableDecisionV1,
  event_id : String,
  command_idempotency_key : String,
) -> OperatorCommandReceiptV1 raise {
  require_operator_final_learning_request_v1(
    current,
    request,
    OperatorFinalizationDispositionV1,
    decision.record_ref(),
    Some(decision.authority_ref()),
    Some(decision.review_decision_ref()),
    decision.evidence(),
    decision.decided_at(),
  )
  operator_persistence_receipt_v1(
    request,
    persist_final_deliverable_decision_v1(
      store, binding, decision, event_id, command_idempotency_key,
    ),
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_operator_delivery_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  current : CurrentFinalLearningProjectionV1,
  request : OperatorCommandRequestV1,
  delivery : GovernedDeliveryReceiptV1,
  event_id : String,
  command_idempotency_key : String,
) -> OperatorCommandReceiptV1 raise {
  require_operator_final_learning_request_v1(
    current,
    request,
    OperatorDeliveryAuthorizationV1,
    delivery.record_ref(),
    Some(delivery.authority_ref()),
    Some(delivery.review_decision_ref()),
    delivery.evidence(),
    delivery.delivered_at(),
  )
  operator_persistence_receipt_v1(
    request,
    persist_governed_delivery_receipt_v1(
      store, binding, delivery, event_id, command_idempotency_key,
    ),
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_operator_outcome_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  current : CurrentFinalLearningProjectionV1,
  request : OperatorCommandRequestV1,
  history : OutcomeHistoryV1,
  observation : OutcomeObservationV1,
  event_id : String,
  command_idempotency_key : String,
) -> OperatorCommandReceiptV1 raise {
  let expected_kind = if observation.kind() == OutcomeCorrectedV1 {
    OperatorOutcomeCorrectionV1
  } else {
    OperatorOutcomeAppendV1
  }
  require_operator_final_learning_request_v1(
    current,
    request,
    expected_kind,
    observation.record_ref(),
    request.authority_ref,
    request.review_ref,
    observation.evidence(),
    observation.recorded_at(),
  )
  operator_persistence_receipt_v1(
    request,
    persist_outcome_observation_v1(
      store, binding, history, observation, event_id, command_idempotency_key,
    ),
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_operator_evaluation_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  current : CurrentFinalLearningProjectionV1,
  request : OperatorCommandRequestV1,
  ledger : OfflineEvaluationLedgerV1,
  evaluation : OfflineProposalEvaluationV1,
  event_id : String,
  command_idempotency_key : String,
) -> OperatorCommandReceiptV1 raise {
  require_operator_final_learning_request_v1(
    current,
    request,
    OperatorOfflineEvaluationV1,
    evaluation.record_ref(),
    request.authority_ref,
    request.review_ref,
    evaluation.evidence(),
    evaluation.evaluated_at(),
  )
  operator_persistence_receipt_v1(
    request,
    persist_offline_proposal_evaluation_v1(
      store, binding, ledger, evaluation, event_id, command_idempotency_key,
    ),
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_operator_human_decision_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  current : CurrentFinalLearningProjectionV1,
  request : OperatorCommandRequestV1,
  decision : HumanVersionDecisionV1,
  event_id : String,
  command_idempotency_key : String,
) -> OperatorCommandReceiptV1 raise {
  let expected_kind = match decision.outcome() {
    VersionAdoptedV1 => OperatorHumanAdoptV1
    VersionRejectedV1 => OperatorHumanRejectV1
  }
  require_operator_final_learning_request_v1(
    current,
    request,
    expected_kind,
    decision.record_ref(),
    Some(decision.authority_ref()),
    Some(decision.review_decision_ref()),
    decision.evidence(),
    decision.decided_at(),
  )
  operator_persistence_receipt_v1(
    request,
    persist_human_version_decision_v1(
      store, binding, decision, event_id, command_idempotency_key,
    ),
  )
}

///|
pub fn OperatorCommandReceiptV1::disposition(
  self : OperatorCommandReceiptV1,
) -> OperatorCommandDispositionV1 {
  self.disposition
}

///|
pub fn OperatorCommandRequestV1::record_ref(
  self : OperatorCommandRequestV1,
) -> @contracts.RecordRef {
  self.command_ref
}

///|
pub fn OperatorCommandRequestV1::run_id(
  self : OperatorCommandRequestV1,
) -> String {
  self.run_id
}

///|
pub fn OperatorCommandRequestV1::kind(
  self : OperatorCommandRequestV1,
) -> OperatorCommandKindV1 {
  self.kind
}

///|
pub fn OperatorCommandRequestV1::head_scope(
  self : OperatorCommandRequestV1,
) -> OperatorHeadScopeV1 {
  self.head_scope
}

///|
pub fn OperatorCommandRequestV1::subject_ref(
  self : OperatorCommandRequestV1,
) -> @contracts.RecordRef {
  self.subject_ref
}

///|
pub fn OperatorCommandRequestV1::authority_ref(
  self : OperatorCommandRequestV1,
) -> @contracts.RecordRef? {
  self.authority_ref
}

///|
pub fn OperatorCommandRequestV1::review_ref(
  self : OperatorCommandRequestV1,
) -> @contracts.RecordRef? {
  self.review_ref
}

///|
pub fn OperatorCommandRequestV1::evidence(
  self : OperatorCommandRequestV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn OperatorCommandRequestV1::payload(
  self : OperatorCommandRequestV1,
) -> @contracts.WireEnvelope {
  self.payload
}

///|
pub fn OperatorCommandRequestV1::requested_at(
  self : OperatorCommandRequestV1,
) -> Int64 {
  self.requested_at
}

///|
pub fn OperatorCommandRequestV1::canonical_bytes(
  self : OperatorCommandRequestV1,
) -> Bytes {
  self.canonical
}

///|
pub fn OperatorCommandRequestV1::digest(
  self : OperatorCommandRequestV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn OperatorCommandReceiptV1::record_ref(
  self : OperatorCommandReceiptV1,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn OperatorCommandReceiptV1::command_ref(
  self : OperatorCommandReceiptV1,
) -> @contracts.RecordRef {
  self.command_ref
}

///|
pub fn OperatorCommandReceiptV1::durable_receipt_ref(
  self : OperatorCommandReceiptV1,
) -> @contracts.RecordRef? {
  self.durable_receipt_ref
}

///|
pub fn OperatorCommandReceiptV1::recorded_at(
  self : OperatorCommandReceiptV1,
) -> Int64 {
  self.recorded_at
}

///|
pub fn OperatorCommandReceiptV1::effect_executed(
  self : OperatorCommandReceiptV1,
) -> Bool {
  self.effect_executed
}

///|
pub fn OperatorCommandReceiptV1::record_persisted(
  self : OperatorCommandReceiptV1,
) -> Bool {
  self.record_persisted
}

///|
pub fn OperatorCommandReceiptV1::canonical_bytes(
  self : OperatorCommandReceiptV1,
) -> Bytes {
  self.canonical
}

///|
pub fn OperatorCommandReceiptV1::digest(
  self : OperatorCommandReceiptV1,
) -> @contracts.ContentDigest {
  self.digest
}
