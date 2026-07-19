///|
pub struct PackHostReceiptV1 {
  operation : String
  status : String
  effect_executed : Bool
  record_persisted : Bool
  record_ref : @contracts.RecordRef?
  unsupported_fields : ReadOnlyArray[String]
  source_digest : @contracts.ContentDigest
  json : Json
  canonical_json : String
  digest : @contracts.ContentDigest
}

///|
fn make_pack_host_receipt_v1(
  operation : String,
  status : String,
  record_persisted : Bool,
  record_ref : @contracts.RecordRef?,
  unsupported_fields : Array[String],
  source_digest : @contracts.ContentDigest,
) -> PackHostReceiptV1 {
  let json : Json = {
    "contract_id": "moonflow.pack-host-receipt.v1",
    "contract_version": "1.0.0",
    "operation": operation,
    "status": status,
    "effect_executed": false,
    "record_persisted": record_persisted,
    "record_ref": handoff_optional_ref_json_v1(record_ref),
    "unsupported_fields": unsupported_fields,
    "source_digest": source_digest.text(),
  }
  let canonical_json = json.stringify()
  {
    operation,
    status,
    effect_executed: false,
    record_persisted,
    record_ref,
    unsupported_fields: ReadOnlyArray::from_array(unsupported_fields),
    source_digest,
    json,
    canonical_json,
    digest: @contracts.sha256_digest(@utf8.encode(canonical_json)),
  }
}

///|
fn require_pack_head_current_v1(
  envelope : PackHandoffEnvelopeV1,
  role : String,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  guard envelope.head(role) is Some(head) else {
    raise MalformedInput(field="pack_handoff_missing_\{role}_head_v1")
  }
  if head.workflow != replay.workflow() ||
    head.revision != replay.head().revision() ||
    head.head_digest != replay.head().last_event_digest() ||
    head.replay_digest != replay.replay_digest() {
    raise ReplayBindingViolation(field="pack_handoff_stale_\{role}_head_v1")
  }
}

///|
fn pack_final_learning_kind_v1(
  kind : PackHandoffRecordKindV1,
) -> FinalLearningRecordKindV1 raise OrchestrationError {
  match kind {
    PackDeliverableCandidateV1 => DurableDeliverableCandidateV1
    PackDeliverableDecisionV1 => DurableDeliverableDecisionV1
    PackArtifactRevisionV1 => DurableArtifactRevisionV1
    PackDeliveryReceiptV1 => DurableDeliveryReceiptV1
    PackOutcomeObservationV1 => DurableOutcomeObservationV1
    PackGapAssessmentV1 => DurableGapAssessmentV1
    PackImprovementProposalV1 => DurableImprovementProposalV1
    PackOfflineEvaluationV1 => DurableOfflineEvaluationV1
    PackHumanVersionDecisionV1 => DurableHumanVersionDecisionV1
    _ => raise MalformedInput(field="pack_handoff_final_learning_kind_v1")
  }
}

///|
fn pack_final_learning_receipt_v1(
  envelope : PackHandoffEnvelopeV1,
  result : FinalLearningPersistenceResultV1,
) -> PackHostReceiptV1 {
  match result {
    FinalLearningFreshlyPersistedV1(receipt) =>
      make_pack_host_receipt_v1(
        "final-learning-persist",
        "freshly-persisted",
        true,
        Some(receipt.durable_record_ref()),
        [],
        envelope.digest(),
      )
    FinalLearningAlreadyPersistedV1(receipt) =>
      make_pack_host_receipt_v1(
        "final-learning-persist",
        "already-persisted",
        true,
        Some(receipt.durable_record_ref()),
        [],
        envelope.digest(),
      )
    FinalLearningRaceLostV1 =>
      make_pack_host_receipt_v1(
        "final-learning-persist",
        "race-lost",
        false,
        None,
        [],
        envelope.digest(),
      )
    FinalLearningGuardStaleV1(_) =>
      make_pack_host_receipt_v1(
        "final-learning-persist",
        "guard-stale",
        false,
        None,
        [],
        envelope.digest(),
      )
  }
}

///|
fn pack_replay_contains_ref_v1(
  replay : @storage.ReplayResult,
  reference : @contracts.RecordRef,
) -> Bool {
  replay
  .events()
  .any(event => {
    event.event_ref() == reference ||
    event.payload().subject() == reference ||
    event
    .evidence()
    .any(item => {
      item.record() == reference || item.provenance_ref() == reference
    })
  })
}

///|
/// Persists one opaque pack record through the existing Phase-4/5 durable
/// stream. Only generic lineage, evidence, and head metadata are interpreted.
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_pack_final_learning_handoff_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  envelope : PackHandoffEnvelopeV1,
  event_id : String,
  command_idempotency_key : String,
) -> PackHostReceiptV1 raise {
  let kind = pack_final_learning_kind_v1(envelope.kind)
  let stream = store.replay(binding.stream_workflow)
  let source = store.replay_registered_guard(binding.source_workflow)
  let governance = store.replay_registered_guard(binding.governance_workflow)
  require_pack_head_current_v1(envelope, "stream", stream)
  require_pack_head_current_v1(envelope, "source", source)
  require_pack_head_current_v1(envelope, "governance", governance)
  match envelope.authority_ref {
    Some(reference) if !pack_replay_contains_ref_v1(source, reference) &&
      !pack_replay_contains_ref_v1(governance, reference) =>
      raise ReplayBindingViolation(field="pack_handoff_authority_replay_v1")
    _ => ()
  }
  match envelope.review_ref {
    Some(reference) if !pack_replay_contains_ref_v1(source, reference) &&
      !pack_replay_contains_ref_v1(governance, reference) =>
      raise ReplayBindingViolation(field="pack_handoff_review_replay_v1")
    _ => ()
  }
  let material : FinalLearningMaterialV1 = {
    kind,
    primary_ref: envelope.payload_ref,
    primary_bytes: envelope.payload,
    source_refs: [
      for value in envelope.source_refs => value
    ],
    previous_lineage_ref: envelope.previous_lineage_ref,
    snapshot_ref: envelope.snapshot_ref,
    snapshot_bytes: envelope.snapshot,
    state_tag: envelope.state_tag,
    ordinal: envelope.ordinal,
    limit: envelope.limit,
    evidence: [
      for value in envelope.evidence => value
    ],
    occurred_at: envelope.occurred_at,
  }
  pack_final_learning_receipt_v1(
    envelope,
    persist_final_learning_material_v1(
      store, binding, material, event_id, command_idempotency_key,
    ),
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_pack_final_learning_json_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  input : Bytes,
  event_id : String,
  command_idempotency_key : String,
) -> PackHostReceiptV1 raise {
  commit_pack_final_learning_handoff_v1(
    store,
    binding,
    decode_pack_handoff_json_bytes_v1(input),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_pack_scheduled_action_handoff_v1(
  store : S,
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
  envelope : PackHandoffEnvelopeV1,
  registration_id : String,
  event_id : String,
  command_idempotency_key : String,
) -> PackHostReceiptV1 raise {
  let action = envelope.scheduled_action()
  require_pack_head_current_v1(envelope, "scheduler", scheduler.replay)
  require_pack_head_current_v1(envelope, "time", time.replay)
  guard time.latest() is Some(observation) else {
    raise ScheduleStateViolation(field="pack_handoff_schedule_time_v1")
  }
  if envelope.occurred_at != observation.effective_instant().epoch_millis() ||
    envelope.state_tag != action.action_kind() ||
    !envelope.source_refs.contains(action.source_ref) {
    raise ReplayBindingViolation(field="pack_handoff_schedule_metadata_v1")
  }
  let plan = prepare_scheduled_action_registration_v1(
    scheduler,
    time,
    action,
    registration_id,
    event_id,
    command_idempotency_key,
    [
      for value in envelope.evidence => value
    ],
  )
  match commit_scheduled_action_registration_v1(store, plan) {
    @storage.FreshlyApplied(_) =>
      make_pack_host_receipt_v1(
        "schedule-registration",
        "freshly-persisted",
        true,
        Some(plan.registration().record_ref()),
        [],
        envelope.digest(),
      )
    @storage.AlreadyCommitted(_) =>
      make_pack_host_receipt_v1(
        "schedule-registration",
        "already-persisted",
        true,
        Some(plan.registration().record_ref()),
        [],
        envelope.digest(),
      )
    @storage.GuardRejected(_) =>
      make_pack_host_receipt_v1(
        "schedule-registration",
        "guard-stale",
        false,
        None,
        [],
        envelope.digest(),
      )
  }
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_pack_scheduled_action_json_v1(
  store : S,
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
  input : Bytes,
  registration_id : String,
  event_id : String,
  command_idempotency_key : String,
) -> PackHostReceiptV1 raise {
  commit_pack_scheduled_action_handoff_v1(
    store,
    scheduler,
    time,
    decode_pack_handoff_json_bytes_v1(input),
    registration_id,
    event_id,
    command_idempotency_key,
  )
}

///|
/// Routes a decoded command without inventing the typed recovery/authority
/// companions required by mutation-specific APIs.
pub fn route_pack_operator_command_handoff_v1(
  surface : MoonFlowOperatorSurfaceV1,
  envelope : PackHandoffEnvelopeV1,
) -> PackHostReceiptV1 raise OrchestrationError {
  let request = envelope.operator_command()
  let routed = route_operator_command_v1(surface, request)
  match routed.disposition() {
    OperatorStaleHeadNonExecutedV1 =>
      return make_pack_host_receipt_v1(
        "operator-command",
        "stale-head",
        false,
        None,
        [],
        envelope.digest(),
      )
    OperatorAuthorityRequiredNonExecutedV1 =>
      return make_pack_host_receipt_v1(
        "operator-command",
        "authority-required",
        false,
        None,
        ["authority_ref"],
        envelope.digest(),
      )
    OperatorReviewRequiredNonExecutedV1 =>
      return make_pack_host_receipt_v1(
        "operator-command",
        "review-required",
        false,
        None,
        ["review_ref"],
        envelope.digest(),
      )
    OperatorRejectedNonExecutedV1(reason) =>
      return make_pack_host_receipt_v1(
        "operator-command",
        "rejected:\{reason}",
        false,
        None,
        [],
        envelope.digest(),
      )
    OperatorAdapterRequiredNonExecutedV1(_)
    | OperatorPreparedForExistingCommitV1(_) => ()
    OperatorDurableApiUnavailableNonExecutedV1(api) =>
      return make_pack_host_receipt_v1(
        "operator-command",
        "durable-api-unavailable",
        false,
        None,
        [api],
        envelope.digest(),
      )
    OperatorFreshlyPersistedV1
    | OperatorAlreadyPersistedV1
    | OperatorRaceLostNonExecutedV1
    | OperatorGuardStaleNonExecutedV1 =>
      return make_pack_host_receipt_v1(
        "operator-command",
        "invalid-routing-receipt",
        false,
        None,
        [],
        envelope.digest(),
      )
  }
  match request.kind() {
    OperatorReconcileQueryV1 =>
      make_pack_host_receipt_v1(
        "operator-command",
        "external-adapter-required",
        false,
        None,
        ["GuardedRecoveryQueryPortV3"],
        envelope.digest(),
      )
    OperatorRecoveryRetryV1 =>
      make_pack_host_receipt_v1(
        "operator-command",
        "missing-typed-companion",
        false,
        None,
        ["RecoverySettlementSourceV3", "authority proof bytes"],
        envelope.digest(),
      )
    OperatorManualInterventionResolutionV1 =>
      make_pack_host_receipt_v1(
        "operator-command",
        "missing-typed-companion",
        false,
        None,
        ["ManualInterventionAuthorityV3", "hold-or-resume", "reason"],
        envelope.digest(),
      )
    OperatorQuarantineResolutionV1 =>
      make_pack_host_receipt_v1(
        "operator-command",
        "missing-typed-companion",
        false,
        None,
        ["QuarantineDispositionKindV1", "reason"],
        envelope.digest(),
      )
    OperatorFinalizationDispositionV1
    | OperatorDeliveryAuthorizationV1
    | OperatorOutcomeAppendV1
    | OperatorOutcomeCorrectionV1
    | OperatorOfflineEvaluationV1
    | OperatorHumanAdoptV1
    | OperatorHumanRejectV1 =>
      make_pack_host_receipt_v1(
        "operator-command",
        "use-final-learning-handoff",
        false,
        None,
        ["matching Phase45 pack handoff record"],
        envelope.digest(),
      )
  }
}

///|
pub fn route_pack_operator_command_json_v1(
  surface : MoonFlowOperatorSurfaceV1,
  input : Bytes,
) -> PackHostReceiptV1 raise OrchestrationError {
  route_pack_operator_command_handoff_v1(
    surface,
    decode_pack_handoff_json_bytes_v1(input),
  )
}

///|
pub fn PackHostReceiptV1::to_json(self : PackHostReceiptV1) -> Json {
  self.json
}

///|
pub fn PackHostReceiptV1::canonical_json(self : PackHostReceiptV1) -> String {
  self.canonical_json
}

///|
pub fn PackHostReceiptV1::digest(
  self : PackHostReceiptV1,
) -> @contracts.ContentDigest {
  self.digest
}
