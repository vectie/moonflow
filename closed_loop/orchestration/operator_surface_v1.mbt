///|
let operator_surface_contract_id_v1 = "moonflow.operator-surface.v1"

///|
let operator_projection_relative_path_v1 = "operator-projection.json"

///|
fn operator_optional_string_json_v1(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn operator_optional_int64_json_v1(value : Int64?) -> Json {
  match value {
    Some(number) => Json::string(number.to_string())
    None => Json::null()
  }
}

///|
fn operator_record_ref_text_v1(value : @contracts.RecordRef) -> String {
  "\{value.kind()}:\{value.id()}:\{value.version().text()}:\{value.digest().text()}"
}

///|
fn operator_evidence_ref_text_v1(value : @contracts.EvidenceRef) -> String {
  operator_record_ref_text_v1(value.record())
}

///|
fn operator_string_array_json_v1(values : Array[String]) -> Json {
  Json::array(values.map(value => Json::string(value)))
}

///|
fn operator_evidence_json_v1(
  values : ReadOnlyArray[@contracts.EvidenceRef],
) -> Json {
  Json::array(
    [
      for value in values => Json::string(operator_evidence_ref_text_v1(value))
    ],
  )
}

///|
fn operator_recovery_state_wire_v1(
  value : @effects.EffectRecoveryStateV3,
) -> String {
  match value {
    @effects.RecoveryDispatchEligibleV3 => "dispatch_eligible_v3"
    @effects.RecoveryDispatchClaimedV3 => "dispatch_claimed_v3"
    @effects.RecoveryDispatchAttemptedV3 => "dispatch_attempted_v3"
    @effects.RecoveryKnownSuccessV3 => "known_success_v3"
    @effects.RecoveryKnownFailureV3 => "known_failure_v3"
    @effects.RecoveryUnknownRequiresReconciliationV3 =>
      "unknown_requires_reconciliation_v3"
    @effects.RecoveryReconciliationClaimedV3 => "reconciliation_claimed_v3"
    @effects.RecoveryReconciledSuccessV3 => "reconciled_success_v3"
    @effects.RecoveryReconciledFailureV3 => "reconciled_failure_v3"
    @effects.RecoveryConfirmedNotAppliedRetryEligibleV3 =>
      "confirmed_not_applied_retry_eligible_v3"
    @effects.RecoveryBackoffPendingV3 => "backoff_pending_v3"
    @effects.RecoveryExhaustedV3 => "exhausted_v3"
    @effects.RecoveryManualInterventionV3 => "manual_intervention_v3"
  }
}

///|
fn operator_callback_quarantine_reason_v1(
  value : RecoveryCallbackDispositionV3,
) -> String {
  match value {
    CallbackEvidenceAcceptedV3 | CallbackEvidenceExactDuplicateV3 => ""
    CallbackEvidenceChangedBodyConflictV3 => "changed callback body"
    CallbackEvidenceStaleFenceV3 => "stale callback fence"
    CallbackEvidenceContradictoryOutcomeV3 => "contradictory callback outcome"
    CallbackEvidenceManualHoldV3 => "manual hold"
  }
}

///|
fn operator_manual_action_wire_v1(value : ManualInterventionActionV3) -> String {
  match value {
    ManualInterventionHeldV3 => "open"
    ManualInterventionResumedV3 => "resolved"
  }
}

///|
fn operator_due_state_v1(
  due_at : Int64,
  deadline : Int64?,
  committed_now : Int64,
) -> (String, Bool) {
  match deadline {
    Some(value) if committed_now > value => ("overdue", true)
    _ if committed_now >= due_at => ("due", false)
    _ => ("waiting", false)
  }
}

///|
/// Opaque Phase-4/5 projection entry. MoonFlow validates identities and
/// bindings but does not interpret finalization or learning payloads.
pub struct OperatorOpaqueEntryV1 {
  entry_id : String
  state : String
  summary : String
  subject_ref : @contracts.RecordRef
  authority_ref : @contracts.RecordRef
  review_ref : @contracts.RecordRef?
  expected_head_digest : @contracts.ContentDigest
  expected_replay_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  recorded_at : Int64
  extension : @contracts.WireEnvelope?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn OperatorOpaqueEntryV1::new(
  entry_id : String,
  state : String,
  summary : String,
  subject_ref : @contracts.RecordRef,
  authority_ref : @contracts.RecordRef,
  review_ref : @contracts.RecordRef?,
  expected_head_digest : @contracts.ContentDigest,
  expected_replay_digest : @contracts.ContentDigest,
  evidence : Array[@contracts.EvidenceRef],
  recorded_at : Int64,
  extension : @contracts.WireEnvelope?,
) -> OperatorOpaqueEntryV1 raise OrchestrationError {
  require_text(entry_id, "operator_opaque_entry_id_v1")
  require_text(state, "operator_opaque_entry_state_v1")
  if recorded_at < 0L || evidence.is_empty() {
    raise MalformedInput(field="operator_opaque_entry_binding_v1")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/OPERATOR-OPAQUE-ENTRY-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(entry_id)
  writer.string(state)
  writer.string(summary)
  write_ref(writer, subject_ref)
  write_ref(writer, authority_ref)
  match review_ref {
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
    None => writer.byte(0)
  }
  writer.string(expected_head_digest.text())
  writer.string(expected_replay_digest.text())
  write_evidence(writer, evidence)
  writer.int64(recorded_at)
  match extension {
    Some(value) => {
      writer.byte(1)
      writer.bytes(@contracts.encode_wire_envelope(value))
    }
    None => writer.byte(0)
  }
  let canonical = writer.finish()
  {
    entry_id,
    state,
    summary,
    subject_ref,
    authority_ref,
    review_ref,
    expected_head_digest,
    expected_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    recorded_at,
    extension,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
fn operator_opaque_entry_json_v1(
  value : OperatorOpaqueEntryV1,
  identity_key : String,
) -> Json {
  let fields : Map[String, Json] = {}
  fields[identity_key] = Json::string(value.entry_id)
  fields["state"] = Json::string(value.state)
  fields["summary"] = Json::string(value.summary)
  fields["subject_ref"] = Json::string(
    operator_record_ref_text_v1(value.subject_ref),
  )
  fields["authority_ref"] = Json::string(
    operator_record_ref_text_v1(value.authority_ref),
  )
  fields["review_ref"] = match value.review_ref {
    Some(reference) => Json::string(operator_record_ref_text_v1(reference))
    None => Json::null()
  }
  fields["expected_head_digest"] = Json::string(
    value.expected_head_digest.text(),
  )
  fields["expected_replay_digest"] = Json::string(
    value.expected_replay_digest.text(),
  )
  fields["evidence_refs"] = operator_evidence_json_v1(value.evidence)
  fields["recorded_at"] = Json::string(value.recorded_at.to_string())
  fields["extension_digest"] = match value.extension {
    Some(extension) =>
      Json::string(
        @contracts.sha256_digest(@contracts.encode_wire_envelope(extension)).text(),
      )
    None => Json::null()
  }
  Json::object(fields)
}

///|
fn operator_opaque_collection_json_v1(
  values : ArrayView[OperatorOpaqueEntryV1],
  identity_key : String,
) -> Json {
  Json::array(
    [
      for value in values => operator_opaque_entry_json_v1(value, identity_key)
    ],
  )
}

///|
fn operator_due_action_json_v1(
  value : RecoveryDueActionV3,
  committed_now : Int64,
) -> Json {
  let (state, overdue) = operator_due_state_v1(
    value.due_at(),
    value.deadline(),
    committed_now,
  )
  {
    "action_id": value.record_ref().id(),
    "kind": value.kind().wire(),
    "state": state,
    "due_at": value.due_at().to_string(),
    "deadline": operator_optional_int64_json_v1(value.deadline()),
    "overdue": overdue,
    "authority_ref": null,
    "source_ref": operator_record_ref_text_v1(value.source_ref()),
    "evidence_refs": [value.digest().text()],
  }
}

///|
fn operator_callback_json_v1(entry : RecoveryCallbackProjectionEntryV3) -> Json {
  let record = entry.record()
  {
    "callback_id": record.record_ref().id(),
    "state": recovery_callback_disposition_wire_v3(entry.disposition()),
    "provider_event_id": record.provider_event_id(),
    "disposition": recovery_callback_disposition_wire_v3(entry.disposition()),
    "source_at": record.source_at().to_string(),
    "received_at": record.retrieved_at().to_string(),
    "reason": operator_callback_quarantine_reason_v1(entry.disposition()),
    "evidence_refs": operator_evidence_json_v1(record.evidence()),
  }
}

///|
fn operator_quarantine_json_v1(
  entry : RecoveryCallbackProjectionEntryV3,
  disposition : QuarantineDispositionRecordV1?,
) -> Json {
  let record = entry.record()
  let fields : Map[String, Json] = {}
  fields["quarantine_id"] = Json::string(entry.digest().text())
  fields["state"] = Json::string(
    disposition
    .map(value => value.disposition().wire())
    .unwrap_or("quarantined"),
  )
  fields["callback_ref"] = Json::string(
    operator_record_ref_text_v1(record.record_ref()),
  )
  fields["reason"] = Json::string(
    disposition
    .map(value => value.reason())
    .unwrap_or(operator_callback_quarantine_reason_v1(entry.disposition())),
  )
  fields["quarantined_at"] = Json::string(record.retrieved_at().to_string())
  fields["disposition_ref"] = match disposition {
    Some(value) => Json::string(operator_record_ref_text_v1(value.record_ref()))
    None => Json::null()
  }
  fields["authority_ref"] = match disposition {
    Some(value) =>
      Json::string(operator_record_ref_text_v1(value.authority_ref()))
    None => Json::null()
  }
  fields["review_ref"] = match disposition {
    Some(value) => Json::string(operator_record_ref_text_v1(value.review_ref()))
    None => Json::null()
  }
  fields["decided_at"] = match disposition {
    Some(value) => Json::string(value.decided_at().to_string())
    None => Json::null()
  }
  fields["evidence_refs"] = match disposition {
    Some(value) => operator_evidence_json_v1(value.evidence())
    None => operator_evidence_json_v1(record.evidence())
  }
  Json::object(fields)
}

///|
fn operator_manual_json_v1(
  value : ManualInterventionRecordV3,
  active : Bool,
) -> Json {
  {
    "intervention_id": value.record_ref().id(),
    "state": if active {
      "open"
    } else {
      operator_manual_action_wire_v1(value.action())
    },
    "reason": value.reason(),
    "required_action": if active {
      "named operator resolution required"
    } else {
      ""
    },
    "owner": operator_record_ref_text_v1(value.authority().operator_ref()),
    "opened_at": value.authored_at().to_string(),
    "resolved_at": if active {
      null
    } else {
      Json::string(value.authored_at().to_string())
    },
    "authority_ref": operator_record_ref_text_v1(
      value.authority().authority_ref(),
    ),
    "evidence_refs": operator_evidence_json_v1(value.evidence()),
  }
}

///|
fn operator_latest_callback_for_intent_v1(
  evidence : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> RecoveryCallbackProjectionEntryV3? {
  evidence
  .entries()
  .filter(entry => entry.record().intent_ref() == intent_ref)
  .last()
}

///|
fn operator_recovery_item_json_v1(
  recovery : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  manual : CurrentManualInterventionProjectionV3,
  due_actions : ReadOnlyArray[RecoveryDueActionV3],
  intent_ref : @contracts.RecordRef,
  committed_now : Int64,
) -> Json raise OrchestrationError {
  let state = recovery.state_for_with_manual_intervention_v3(
    evidence, manual, intent_ref,
  )
  let dispatch = recovery.current_claim(intent_ref)
  let reconciliation = recovery.current_reconciliation_claim_v3(intent_ref)
  let owner = match reconciliation {
    Some(value) => Some(operator_record_ref_text_v1(value.owner()))
    None => dispatch.map(value => operator_record_ref_text_v1(value.owner()))
  }
  let claim_id = match reconciliation {
    Some(value) => Some(value.record_ref().id())
    None => dispatch.map(value => value.record_ref().id())
  }
  let epoch = dispatch.map(value => value.lease_epoch())
  let fence = match reconciliation {
    Some(value) => Some(value.fencing_token())
    None => dispatch.map(value => value.fencing_token())
  }
  let expires_at = match reconciliation {
    Some(value) => Some(value.expires_at())
    None => dispatch.map(value => value.expires_at())
  }
  let matching_due = due_actions.filter(value => {
    value.intent_ref() == Some(intent_ref)
  })
  let next_due_at = if matching_due.is_empty() {
    None
  } else {
    Some(matching_due[0].due_at())
  }
  let deadline = if matching_due.is_empty() {
    None
  } else {
    matching_due[0].deadline()
  }
  let unknown_since = match
    operator_latest_callback_for_intent_v1(evidence, intent_ref) {
    Some(entry) => Some(entry.record().retrieved_at())
    None =>
      match recovery.current_reconciliation_result_v3(intent_ref) {
        Some(value) => Some(value.observed_at())
        None => dispatch.map(value => value.claimed_at())
      }
  }
  let observation_digest = match
    operator_latest_callback_for_intent_v1(evidence, intent_ref) {
    Some(entry) => Some(entry.record().body_digest().text())
    None =>
      match recovery.current_reconciliation_result_v3(intent_ref) {
        Some(value) =>
          value.provider_evidence().map(item => item.body_digest().text())
        None => None
      }
  }
  let dispatch_attempt_count = match dispatch {
    Some(_) => 1
    None => 0
  }
  let attempt_count = recovery
    .reconciliation_claims_v3()
    .filter(value => value.intent_ref() == intent_ref)
    .length() +
    dispatch_attempt_count
  let fields : Map[String, Json] = {}
  fields["intent_ref"] = Json::string(operator_record_ref_text_v1(intent_ref))
  fields["state"] = Json::string(operator_recovery_state_wire_v1(state))
  fields["owner"] = operator_optional_string_json_v1(owner)
  fields["claim_id"] = operator_optional_string_json_v1(claim_id)
  fields["epoch"] = operator_optional_int64_json_v1(epoch)
  fields["fence"] = operator_optional_int64_json_v1(fence)
  fields["expires_at"] = operator_optional_int64_json_v1(expires_at)
  fields["next_due_at"] = operator_optional_int64_json_v1(next_due_at)
  fields["deadline"] = operator_optional_int64_json_v1(deadline)
  fields["attempt_count"] = Json::string(attempt_count.to_string())
  fields["unknown_since"] = operator_optional_int64_json_v1(unknown_since)
  fields["reconciliation_age_seconds"] = match unknown_since {
    Some(value) if committed_now >= value =>
      Json::string(((committed_now - value) / 1000L).to_string())
    _ => Json::null()
  }
  fields["last_provider_observation_digest"] = operator_optional_string_json_v1(
    observation_digest,
  )
  fields["manual_intervention"] = Json::boolean(
    manual.active_hold(intent_ref) is Some(_),
  )
  fields["blocker"] = Json::string("")
  fields["evidence_refs"] = operator_string_array_json_v1([
    recovery.state_digest().text(),
    evidence.state_digest().text(),
  ])
  fields["recorded_at"] = Json::string(committed_now.to_string())
  Json::object(fields)
}

///|
pub struct MoonFlowOperatorSurfaceV1 {
  run_id : String
  recorded_at : Int64
  work_head_digest : @contracts.ContentDigest?
  work_replay_digest : @contracts.ContentDigest
  recovery_state_digest : @contracts.ContentDigest
  evidence_state_digest : @contracts.ContentDigest
  final_learning_head_digest : @contracts.ContentDigest?
  final_learning_replay_digest : @contracts.ContentDigest?
  final_learning_state_digest : @contracts.ContentDigest?
  json : Json
  canonical_json : String
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
/// Build the complete read-only operator projection from exact Phase-2 replay
/// and a Phase-3 committed-time host facade. Opaque collections are supplied
/// by later durable streams without importing their implementation types.
fn moonflow_operator_surface_from_projections_v1(
  run_id : String,
  recovery : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  time : TimeEvidenceProjectionV3,
  final_deliverables : Array[OperatorOpaqueEntryV1],
  artifacts : Array[OperatorOpaqueEntryV1],
  deliveries : Array[OperatorOpaqueEntryV1],
  outcomes : Array[OperatorOpaqueEntryV1],
  proposals : Array[OperatorOpaqueEntryV1],
  evaluations : Array[OperatorOpaqueEntryV1],
  human_adoptions : Array[OperatorOpaqueEntryV1],
) -> MoonFlowOperatorSurfaceV1 raise OrchestrationError {
  require_text(run_id, "operator_surface_run_id_v1")
  if evidence.bound_workflow() != recovery.work_replay.workflow() ||
    evidence.bound_work_replay_digest() != recovery.work_replay.replay_digest() {
    raise ReplayBindingViolation(field="operator_surface_recovery_binding_v1")
  }
  let committed_now = phase3_committed_now_v3(time)
  let due_actions = recovery.recovery_due_actions_with_committed_evidence_time_v3(
    evidence, time,
  )
  let manual = fold_manual_intervention_v3(recovery.work_replay)
  let quarantine = fold_quarantine_dispositions_v1(recovery, evidence)
  let recovery_items : Array[Json] = []
  for intent_ref in recovery.v3_owned_intent_refs() {
    recovery_items.push(
      operator_recovery_item_json_v1(
        recovery, evidence, manual, due_actions, intent_ref, committed_now,
      ),
    )
  }
  let recovery_summary : Json = if recovery_items.is_empty() {
    {
      "state": "not_applicable",
      "manual_intervention": false,
      "recorded_at": committed_now.to_string(),
      "evidence_refs": [recovery.state_digest().text()],
    }
  } else if recovery_items.length() == 1 {
    recovery_items[0]
  } else {
    {
      "state": "mixed",
      "manual_intervention": manual.active_holds().length() > 0,
      "recorded_at": committed_now.to_string(),
      "evidence_refs": [
        recovery.state_digest().text(),
        evidence.state_digest().text(),
      ],
    }
  }
  let callback_values = [
    for entry in evidence.entries() => operator_callback_json_v1(entry)
  ]
  let quarantine_values = [
    for entry in evidence.quarantined_entries() => {
      operator_quarantine_json_v1(
        entry,
        quarantine.current_for(entry.record().record_ref()),
      )
    }
  ]
  let manual_values = [
    for value in manual.entries() => {
      operator_manual_json_v1(
        value,
        manual
        .active_holds()
        .any(active => active.record_ref() == value.record_ref()),
      )
    }
  ]
  let fields : Map[String, Json] = {}
  fields["contract_id"] = Json::string(operator_surface_contract_id_v1)
  fields["run_id"] = Json::string(run_id)
  fields["available"] = Json::boolean(true)
  fields["status"] = Json::string("published")
  fields["recorded_at"] = Json::string(committed_now.to_string())
  fields["work_head_digest"] = match
    recovery.work_replay.head().last_event_digest() {
    Some(value) => Json::string(value.text())
    None => Json::null()
  }
  fields["work_replay_digest"] = Json::string(
    recovery.work_replay.replay_digest().text(),
  )
  fields["recovery_state_digest"] = Json::string(recovery.state_digest().text())
  fields["evidence_state_digest"] = Json::string(evidence.state_digest().text())
  fields["quarantine_state_digest"] = Json::string(
    quarantine.state_digest().text(),
  )
  fields["recovery"] = recovery_summary
  fields["recovery_items"] = Json::array(recovery_items)
  fields["due_actions"] = Json::array(
    [
      for value in due_actions => {
        operator_due_action_json_v1(value, committed_now)
      }
    ],
  )
  fields["callbacks"] = Json::array(callback_values)
  fields["quarantine"] = Json::array(quarantine_values)
  fields["manual_interventions"] = Json::array(manual_values)
  fields["final_deliverables"] = operator_opaque_collection_json_v1(
    final_deliverables, "candidate_id",
  )
  fields["artifacts"] = operator_opaque_collection_json_v1(
    artifacts, "artifact_id",
  )
  fields["deliveries"] = operator_opaque_collection_json_v1(
    deliveries, "delivery_id",
  )
  fields["outcomes"] = operator_opaque_collection_json_v1(
    outcomes, "observation_id",
  )
  fields["proposals"] = operator_opaque_collection_json_v1(
    proposals, "proposal_id",
  )
  fields["evaluations"] = operator_opaque_collection_json_v1(
    evaluations, "evaluation_id",
  )
  fields["human_adoptions"] = operator_opaque_collection_json_v1(
    human_adoptions, "decision_id",
  )
  let json = Json::object(fields)
  let canonical_json = json.stringify()
  let canonical = @utf8.encode(canonical_json)
  {
    run_id,
    recorded_at: committed_now,
    work_head_digest: recovery.work_replay.head().last_event_digest(),
    work_replay_digest: recovery.work_replay.replay_digest(),
    recovery_state_digest: recovery.state_digest(),
    evidence_state_digest: evidence.state_digest(),
    final_learning_head_digest: None,
    final_learning_replay_digest: None,
    final_learning_state_digest: None,
    json,
    canonical_json,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
/// Build the complete read-only operator projection from exact Phase-2 replay
/// and a Phase-3 committed-time host facade. Opaque collections are supplied
/// by later durable streams without importing their implementation types.
pub fn MoonFlowOperatorSurfaceV1::from_replay(
  run_id : String,
  recovery : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  time : Phase3HostFacadeV3,
  final_deliverables : Array[OperatorOpaqueEntryV1],
  artifacts : Array[OperatorOpaqueEntryV1],
  deliveries : Array[OperatorOpaqueEntryV1],
  outcomes : Array[OperatorOpaqueEntryV1],
  proposals : Array[OperatorOpaqueEntryV1],
  evaluations : Array[OperatorOpaqueEntryV1],
  human_adoptions : Array[OperatorOpaqueEntryV1],
) -> MoonFlowOperatorSurfaceV1 raise OrchestrationError {
  moonflow_operator_surface_from_projections_v1(
    run_id,
    recovery,
    evidence,
    time.time_projection(),
    final_deliverables,
    artifacts,
    deliveries,
    outcomes,
    proposals,
    evaluations,
    human_adoptions,
  )
}

///|
fn operator_durable_record_json_v1(
  value : FinalLearningDurableRecordV1,
  identity_key : String,
) -> Json {
  let fields : Map[String, Json] = {}
  fields[identity_key] = Json::string(value.primary_ref().id())
  fields["state"] = Json::string(value.state_tag())
  fields["summary"] = Json::string(value.kind().wire())
  fields["subject_ref"] = Json::string(
    operator_record_ref_text_v1(value.primary_ref()),
  )
  fields["durable_record_ref"] = Json::string(
    operator_record_ref_text_v1(value.record_ref()),
  )
  fields["source_refs"] = operator_string_array_json_v1(
    [
      for reference in value.source_refs() => {
        operator_record_ref_text_v1(reference)
      }
    ],
  )
  fields["snapshot_ref"] = match value.snapshot_ref() {
    Some(reference) => Json::string(operator_record_ref_text_v1(reference))
    None => Json::null()
  }
  fields["recorded_at"] = Json::string(value.occurred_at.to_string())
  fields["evidence_refs"] = operator_evidence_json_v1(value.evidence)
  fields["record_digest"] = Json::string(value.digest().text())
  Json::object(fields)
}

///|
fn operator_durable_collection_json_v1(
  values : ReadOnlyArray[FinalLearningDurableRecordV1],
  identity_key : String,
) -> Json {
  Json::array(
    [
      for value in values => {
        operator_durable_record_json_v1(value, identity_key)
      }
    ],
  )
}

///|
/// Complete Phase-2 through Phase-5 projection. The final-learning projection
/// is already replay-validated against its source and governance heads, so the
/// operator export only projects those immutable durable entries.
pub fn MoonFlowOperatorSurfaceV1::from_complete_replay(
  run_id : String,
  recovery : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  time : Phase3HostFacadeV3,
  final_learning : CurrentFinalLearningProjectionV1,
) -> MoonFlowOperatorSurfaceV1 raise OrchestrationError {
  MoonFlowOperatorSurfaceV1::from_complete_projections_v1(
    run_id,
    recovery,
    evidence,
    time.time_projection(),
    final_learning,
  )
}

///|
/// Build the complete Phase-2 through Phase-5 operator projection from
/// projections already replayed by an application host. This keeps committed
/// time explicit without forcing the host to append a new clock observation.
pub fn MoonFlowOperatorSurfaceV1::from_complete_projections_v1(
  run_id : String,
  recovery : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  time : TimeEvidenceProjectionV3,
  final_learning : CurrentFinalLearningProjectionV1,
) -> MoonFlowOperatorSurfaceV1 raise OrchestrationError {
  let base = moonflow_operator_surface_from_projections_v1(
    run_id,
    recovery,
    evidence,
    time,
    [],
    [],
    [],
    [],
    [],
    [],
    [],
  )
  let fields : Map[String, Json] = {}
  match base.json {
    Object(values) =>
      for key, value in values {
        fields[key] = value
      }
    _ => raise ReplayBindingViolation(field="operator_surface_json_v1")
  }
  let finalization : Array[Json] = []
  for value in final_learning.candidates() {
    finalization.push(operator_durable_record_json_v1(value, "candidate_id"))
  }
  for value in final_learning.decisions() {
    finalization.push(operator_durable_record_json_v1(value, "candidate_id"))
  }
  fields["final_deliverables"] = Json::array(finalization)
  fields["artifacts"] = operator_durable_collection_json_v1(
    final_learning.artifact_revisions(),
    "artifact_id",
  )
  fields["deliveries"] = operator_durable_collection_json_v1(
    final_learning.deliveries(),
    "delivery_id",
  )
  fields["outcomes"] = operator_durable_collection_json_v1(
    final_learning.observations(),
    "observation_id",
  )
  fields["gap_assessments"] = operator_durable_collection_json_v1(
    final_learning.assessments(),
    "assessment_id",
  )
  fields["proposals"] = operator_durable_collection_json_v1(
    final_learning.proposals(),
    "proposal_id",
  )
  fields["evaluations"] = operator_durable_collection_json_v1(
    final_learning.evaluations(),
    "evaluation_id",
  )
  fields["human_adoptions"] = operator_durable_collection_json_v1(
    final_learning.human_decisions(),
    "decision_id",
  )
  fields["final_learning_state_digest"] = Json::string(
    final_learning.state_digest().text(),
  )
  fields["final_learning_head_digest"] = match
    final_learning.replay.head().last_event_digest() {
    Some(value) => Json::string(value.text())
    None => Json::null()
  }
  fields["final_learning_replay_digest"] = Json::string(
    final_learning.replay.replay_digest().text(),
  )
  let json = Json::object(fields)
  let canonical_json = json.stringify()
  let canonical = @utf8.encode(canonical_json)
  {
    ..base,
    json,
    canonical_json,
    canonical,
    final_learning_head_digest: final_learning.replay.head().last_event_digest(),
    final_learning_replay_digest: Some(final_learning.replay.replay_digest()),
    final_learning_state_digest: Some(final_learning.state_digest()),
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn MoonFlowOperatorSurfaceV1::json(
  self : MoonFlowOperatorSurfaceV1,
) -> Json {
  self.json
}

///|
pub fn MoonFlowOperatorSurfaceV1::canonical_json(
  self : MoonFlowOperatorSurfaceV1,
) -> String {
  self.canonical_json
}

///|
pub fn MoonFlowOperatorSurfaceV1::canonical_bytes(
  self : MoonFlowOperatorSurfaceV1,
) -> Bytes {
  self.canonical
}

///|
pub fn MoonFlowOperatorSurfaceV1::digest(
  self : MoonFlowOperatorSurfaceV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Exact safe inputs for a native host's atomic replace operation. MoonFlow
/// does not select an absolute path or perform an unguarded filesystem write.
pub struct OperatorProjectionMaterializationV1 {
  relative_path : String
  bytes : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn MoonFlowOperatorSurfaceV1::materialization(
  self : MoonFlowOperatorSurfaceV1,
) -> OperatorProjectionMaterializationV1 {
  {
    relative_path: operator_projection_relative_path_v1,
    bytes: self.canonical,
    digest: self.digest,
  }
}

///|
pub fn OperatorProjectionMaterializationV1::relative_path(
  self : OperatorProjectionMaterializationV1,
) -> String {
  self.relative_path
}

///|
pub fn OperatorProjectionMaterializationV1::bytes(
  self : OperatorProjectionMaterializationV1,
) -> Bytes {
  self.bytes
}

///|
pub fn OperatorProjectionMaterializationV1::digest(
  self : OperatorProjectionMaterializationV1,
) -> @contracts.ContentDigest {
  self.digest
}
