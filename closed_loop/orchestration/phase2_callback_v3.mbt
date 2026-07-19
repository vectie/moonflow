///|
priv struct RecoveryCallbackCandidateV3 {
  record : RecoveryCallbackRecordV3
  event : @storage.WorkflowEvent
  guarded : @storage.GuardedCommitRequest
  proposed_disposition : RecoveryCallbackDispositionV3
}

///|
fn latest_reconciliation_claim_for_callback_v3(
  work_replay : @storage.ReplayResult,
  intent_ref : @contracts.RecordRef,
) -> ReconciliationClaimRecordV3? raise OrchestrationError {
  let mut latest : ReconciliationClaimRecordV3? = None
  for event in work_replay.events() {
    if event.payload().envelope_kind() == reconciliation_claim_event_kind_v3 {
      let claim = decode_reconciliation_claim_record_v3(
        event.payload().payload(),
      )
      require_reconciliation_claim_event_binding_v3(claim, event)
      require_reconciliation_claim_transaction_v3(claim, event, work_replay)
      if claim.intent_ref == intent_ref {
        match latest {
          None => latest = Some(claim)
          Some(prior) if claim.reconciliation_ordinal >
            prior.reconciliation_ordinal => latest = Some(claim)
          Some(_) => ()
        }
      }
    }
  }
  latest
}

///|
fn dispatch_claim_for_callback_v3(
  work_replay : @storage.ReplayResult,
  intent_ref : @contracts.RecordRef,
) -> DispatchClaimRecordV3 raise OrchestrationError {
  let matches : Array[@storage.WorkflowEvent] = []
  for event in work_replay.events() {
    if event.payload().envelope_kind() == dispatch_claim_event_kind_v3 {
      let claim = decode_dispatch_claim_record_v3(event.payload().payload())
      if claim.intent_ref == intent_ref {
        matches.push(event)
      }
    }
  }
  if matches.length() != 1 {
    raise RecoveryViolation(field="recovery_callback_dispatch_source_v3")
  }
  let event = matches[0]
  let claim = decode_dispatch_claim_record_v3(event.payload().payload())
  require_dispatch_claim_event_binding_v3(claim, event)
  require_dispatch_claim_transaction_v3(claim, event, work_replay)
  claim
}

///|
fn make_recovery_callback_record_v3(
  binding : RecoveryEvidenceStreamBindingV3,
  evidence_replay : @storage.ReplayResult,
  work_replay : @storage.ReplayResult,
  intent_ref : @contracts.RecordRef,
  callback_id : String,
  event_id : String,
  command_idempotency_key : String,
  callback : ProviderCallbackEvidenceV3,
) -> RecoveryCallbackRecordV3 raise OrchestrationError {
  require_text(callback_id, "recovery_callback_id_v3")
  require_text(event_id, "recovery_callback_event_id_v3")
  require_text(command_idempotency_key, "recovery_callback_command_key_v3")
  if evidence_replay.workflow() != binding.evidence_workflow ||
    work_replay.workflow() != binding.work_workflow {
    raise WorkflowMismatch(field="recovery_callback_stream_binding_v3")
  }
  guard work_replay.head().last_event_digest() is Some(work_head_digest) else {
    raise RecoveryViolation(field="recovery_callback_empty_work_v3")
  }
  let dispatch_claim = dispatch_claim_for_callback_v3(work_replay, intent_ref)
  let reconciliation_claim = latest_reconciliation_claim_for_callback_v3(
    work_replay, intent_ref,
  )
  if callback.external_idempotency_key !=
    dispatch_claim.external_idempotency_key ||
    callback.provider_profile_digest != dispatch_claim.provider_profile_digest {
    raise RecoveryViolation(field="recovery_callback_provider_binding_v3")
  }
  let reconciliation_claim_ref = reconciliation_claim.map(claim => {
    claim.reconciliation_claim_ref
  })
  let reconciliation_claim_digest = reconciliation_claim.map(claim => {
    claim.digest
  })
  let reconciliation_fence = reconciliation_claim.map(claim => {
    claim.fencing_token
  })
  let canonical = recovery_callback_record_signing_bytes_v3(
    callback_id,
    binding,
    intent_ref,
    dispatch_claim.governed_subject,
    dispatch_claim.claim_ref,
    dispatch_claim.digest,
    reconciliation_claim_ref,
    reconciliation_claim_digest,
    dispatch_claim.external_idempotency_key,
    dispatch_claim.fencing_token,
    reconciliation_fence,
    dispatch_claim.provider_profile_digest,
    callback,
    event_id,
    command_idempotency_key,
    evidence_replay.head().revision(),
    evidence_replay.head().last_event_digest(),
    evidence_replay.replay_digest(),
    work_replay.head().revision(),
    work_head_digest,
    work_replay.replay_digest(),
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    callback_ref: self_ref_v3(
      "orchestration-recovery-callback-v3", callback_id, digest,
    ),
    binding_ref: binding.binding_ref,
    binding_digest: binding.digest,
    evidence_workflow: binding.evidence_workflow,
    work_workflow: binding.work_workflow,
    intent_ref,
    governed_subject: dispatch_claim.governed_subject,
    dispatch_claim_ref: dispatch_claim.claim_ref,
    dispatch_claim_digest: dispatch_claim.digest,
    reconciliation_claim_ref,
    reconciliation_claim_digest,
    external_idempotency_key: dispatch_claim.external_idempotency_key,
    dispatch_fence: dispatch_claim.fencing_token,
    reconciliation_fence,
    provider_profile_digest: dispatch_claim.provider_profile_digest,
    callback,
    event_id,
    command_idempotency_key,
    expected_evidence_revision: evidence_replay.head().revision(),
    expected_evidence_head_digest: evidence_replay.head().last_event_digest(),
    expected_evidence_replay_digest: evidence_replay.replay_digest(),
    expected_work_revision: work_replay.head().revision(),
    expected_work_head_digest: work_head_digest,
    expected_work_replay_digest: work_replay.replay_digest(),
    canonical,
    digest,
  }
}

///|
fn recovery_callback_event_v3(
  record : RecoveryCallbackRecordV3,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let evidence = [ for value in record.callback.evidence => value ]
  let causation = record.reconciliation_claim_ref.unwrap_or(
    record.dispatch_claim_ref,
  )
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    record.event_id,
    recovery_callback_evidence_event_kind_v3,
    record.governed_subject,
    phase1b_effect_schema_v22(recovery_callback_evidence_event_kind_v3),
    record.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=record.evidence_workflow,
    correlation_ref=record.work_workflow.id(),
    causation_ref=causation.id(),
    idempotency_ref=record.callback_ref.id(),
    previous_digest?=record.expected_evidence_head_digest,
  ) catch {
    _ => raise MalformedInput(field="recovery_callback_envelope_v3")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    record.evidence_workflow,
    record.event_id,
    record.expected_evidence_revision + 1L,
    record.expected_evidence_revision + 1L,
    record.callback_ref.id(),
    envelope,
    evidence,
    previous_event_digest?=record.expected_evidence_head_digest,
  ) catch {
    _ => raise MalformedInput(field="recovery_callback_event_v3")
  }
}

///|
fn prepare_recovery_callback_candidate_v3(
  binding : RecoveryEvidenceStreamBindingV3,
  projection : CurrentRecoveryEvidenceProjectionV3,
  work_replay : @storage.ReplayResult,
  intent_ref : @contracts.RecordRef,
  callback_id : String,
  event_id : String,
  command_idempotency_key : String,
  callback : ProviderCallbackEvidenceV3,
) -> RecoveryCallbackCandidateV3 raise OrchestrationError {
  let record = make_recovery_callback_record_v3(
    binding,
    projection.replay,
    work_replay,
    intent_ref,
    callback_id,
    event_id,
    command_idempotency_key,
    callback,
  )
  let source = recovery_callback_work_source_v3(record, work_replay)
  let proposed_disposition = derive_recovery_callback_disposition_v3(
    record,
    source,
    projection.entries,
  )
  let event = recovery_callback_event_v3(record)
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    record.evidence_workflow,
    record.expected_evidence_revision,
    record.command_idempotency_key,
    [event],
    [],
  ) catch {
    _ => raise MalformedInput(field="recovery_callback_commit_request_v3")
  }
  let guarded = @storage.GuardedCommitRequest::new(request, [
    @storage.WorkflowHeadGuard::new(
      record.work_workflow,
      record.expected_work_revision,
      Some(record.expected_work_head_digest),
      record.expected_work_replay_digest,
    ),
  ]) catch {
    _ => raise MalformedInput(field="recovery_callback_guarded_request_v3")
  }
  { record, event, guarded, proposed_disposition }
}

///|
pub(all) enum RecoveryCallbackIntakeStatusV3 {
  RecoveryCallbackPersistedV3
  RecoveryCallbackExactDuplicateV3
  RecoveryCallbackAlreadyCommittedV3
  RecoveryCallbackRaceLostV3
  RecoveryCallbackStaleWorkHeadV3
} derive(Eq, Debug)

///|
pub struct RecoveryCallbackIntakeResultV3 {
  status : RecoveryCallbackIntakeStatusV3
  disposition : RecoveryCallbackDispositionV3
  record_ref : @contracts.RecordRef?
  evidence_state_digest : @contracts.ContentDigest
  persisted : Bool
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_recovery_callback_intake_result_v3(
  status : RecoveryCallbackIntakeStatusV3,
  disposition : RecoveryCallbackDispositionV3,
  record_ref : @contracts.RecordRef?,
  evidence_state_digest : @contracts.ContentDigest,
  persisted : Bool,
) -> RecoveryCallbackIntakeResultV3 {
  let writer = OrchestrationWriter::new()
  try! writer.bytes(b"FLOW7/RECOVERY-CALLBACK-INTAKE-RESULT-V3/3.0.0")
  try! writer.string("3.0.0")
  try! writer.string(
    match status {
      RecoveryCallbackPersistedV3 => "persisted"
      RecoveryCallbackExactDuplicateV3 => "exact_duplicate"
      RecoveryCallbackAlreadyCommittedV3 => "already_committed"
      RecoveryCallbackRaceLostV3 => "race_lost"
      RecoveryCallbackStaleWorkHeadV3 => "stale_work_head"
    },
  )
  try! writer.string(recovery_callback_disposition_wire_v3(disposition))
  try! write_optional_ref(writer, record_ref)
  try! writer.string(evidence_state_digest.text())
  writer.byte(if persisted { 1 } else { 0 })
  let canonical = writer.finish()
  {
    status,
    disposition,
    record_ref,
    evidence_state_digest,
    persisted,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn RecoveryCallbackIntakeResultV3::status(
  self : RecoveryCallbackIntakeResultV3,
) -> RecoveryCallbackIntakeStatusV3 {
  self.status
}

///|
pub fn RecoveryCallbackIntakeResultV3::disposition(
  self : RecoveryCallbackIntakeResultV3,
) -> RecoveryCallbackDispositionV3 {
  self.disposition
}

///|
pub fn RecoveryCallbackIntakeResultV3::record_ref(
  self : RecoveryCallbackIntakeResultV3,
) -> @contracts.RecordRef? {
  self.record_ref
}

///|
pub fn RecoveryCallbackIntakeResultV3::evidence_state_digest(
  self : RecoveryCallbackIntakeResultV3,
) -> @contracts.ContentDigest {
  self.evidence_state_digest
}

///|
pub fn RecoveryCallbackIntakeResultV3::persisted(
  self : RecoveryCallbackIntakeResultV3,
) -> Bool {
  self.persisted
}

///|
pub fn RecoveryCallbackIntakeResultV3::canonical_bytes(
  self : RecoveryCallbackIntakeResultV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryCallbackIntakeResultV3::digest(
  self : RecoveryCallbackIntakeResultV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
fn duplicate_callback_entry_v3(
  projection : CurrentRecoveryEvidenceProjectionV3,
  candidate : RecoveryCallbackCandidateV3,
) -> RecoveryCallbackProjectionEntryV3? {
  first(projection.entries, entry => {
    recovery_callback_same_identity_v3(entry.record, candidate.record) &&
    recovery_callback_same_bound_body_v3(entry.record, candidate.record)
  })
}

///|
fn callback_entry_by_ref_v3(
  projection : CurrentRecoveryEvidenceProjectionV3,
  record_ref : @contracts.RecordRef,
) -> RecoveryCallbackProjectionEntryV3? {
  first(projection.entries, entry => entry.record.callback_ref == record_ref)
}

///|
/// Durable callback intake for the separately registered recovery-evidence
/// stream. The only external effect is the guarded evidence append; this
/// operation never invokes create or query provider ports.
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] intake_recovery_callback_v3(
  store : S,
  binding : RecoveryEvidenceStreamBindingV3,
  intent_ref : @contracts.RecordRef,
  callback_id : String,
  event_id : String,
  command_idempotency_key : String,
  callback : ProviderCallbackEvidenceV3,
) -> RecoveryCallbackIntakeResultV3 raise {
  let evidence_replay = store.replay(binding.evidence_workflow)
  let work_replay = store.replay_registered_guard(binding.work_workflow)
  let projection = fold_recovery_evidence_stream_v3(
    binding, evidence_replay, work_replay,
  )
  let candidate = prepare_recovery_callback_candidate_v3(
    binding, projection, work_replay, intent_ref, callback_id, event_id, command_idempotency_key,
    callback,
  )
  if candidate.proposed_disposition == CallbackEvidenceExactDuplicateV3 {
    guard duplicate_callback_entry_v3(projection, candidate) is Some(existing) else {
      raise RecoveryViolation(field="recovery_callback_duplicate_history_v3")
    }
    return make_recovery_callback_intake_result_v3(
      RecoveryCallbackExactDuplicateV3,
      CallbackEvidenceExactDuplicateV3,
      Some(existing.record.callback_ref),
      projection.state_digest,
      false,
    )
  }
  let outcome = store.classified_guarded_commit(candidate.guarded) catch {
    @storage.OptimisticRevisionConflict(..) =>
      return make_recovery_callback_intake_result_v3(
        RecoveryCallbackRaceLostV3,
        candidate.proposed_disposition,
        None,
        projection.state_digest,
        false,
      )
    error => raise error
  }
  match outcome {
    @storage.GuardRejected(_) =>
      make_recovery_callback_intake_result_v3(
        RecoveryCallbackStaleWorkHeadV3,
        candidate.proposed_disposition,
        None,
        projection.state_digest,
        false,
      )
    @storage.FreshlyApplied(_) | @storage.AlreadyCommitted(_) => {
      let current_evidence = store.replay(binding.evidence_workflow)
      let current_work = store.replay_registered_guard(binding.work_workflow)
      let current = fold_recovery_evidence_stream_v3(
        binding, current_evidence, current_work,
      )
      guard callback_entry_by_ref_v3(current, candidate.record.callback_ref)
        is Some(entry) else {
        raise RecoveryViolation(field="recovery_callback_commit_missing_v3")
      }
      make_recovery_callback_intake_result_v3(
        match outcome {
          @storage.FreshlyApplied(_) => RecoveryCallbackPersistedV3
          @storage.AlreadyCommitted(_) => RecoveryCallbackAlreadyCommittedV3
          @storage.GuardRejected(_) => RecoveryCallbackStaleWorkHeadV3
        },
        entry.disposition,
        Some(entry.record.callback_ref),
        current.state_digest,
        outcome is @storage.FreshlyApplied(_),
      )
    }
  }
}

///|
pub struct CallbackRecoveryIntegrationV3 {
  record_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  disposition : RecoveryCallbackDispositionV3
  outcome : @effects.ExternalRecoveryOutcomeV3
  settlement_eligible : Bool
  manual_intervention : Bool
  authoritative_reconciliation : Bool
  source_at : Int64
  retrieved_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_callback_recovery_integration_v3(
  projection : CurrentRecoveryEvidenceProjectionV3,
  entry : RecoveryCallbackProjectionEntryV3,
) -> CallbackRecoveryIntegrationV3 raise OrchestrationError {
  let work_prefix = verified_prefix_v3(
    projection.bound_work_replay,
    entry.record.expected_work_revision,
    "callback_integration_work_prefix_v3",
  )
  let source = recovery_callback_work_source_v3(entry.record, work_prefix)
  let authoritative = recovery_callback_is_authoritative_v3(
    entry.record,
    source,
  )
  let manual = entry.disposition == CallbackEvidenceChangedBodyConflictV3 ||
    entry.disposition == CallbackEvidenceContradictoryOutcomeV3 ||
    entry.disposition == CallbackEvidenceManualHoldV3
  let settlement_eligible = entry.disposition == CallbackEvidenceAcceptedV3 &&
    authoritative &&
    !manual
  let authoritative_reconciliation = !manual &&
    (
      entry.disposition == CallbackEvidenceStaleFenceV3 ||
      (entry.disposition == CallbackEvidenceAcceptedV3 && !authoritative)
    )
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CALLBACK-RECOVERY-INTEGRATION-V3/3.0.0")
  writer.string("3.0.0")
  write_ref(writer, entry.record.callback_ref)
  write_ref(writer, entry.record.intent_ref)
  writer.string(recovery_callback_disposition_wire_v3(entry.disposition))
  writer.bytes(
    @effects.encode_external_recovery_outcome_v3(entry.record.callback.outcome),
  )
  writer.byte(if settlement_eligible { 1 } else { 0 })
  writer.byte(if manual { 1 } else { 0 })
  writer.byte(if authoritative_reconciliation { 1 } else { 0 })
  writer.int64(entry.record.callback.source_at)
  writer.int64(entry.record.callback.retrieved_at)
  let canonical = writer.finish()
  {
    record_ref: entry.record.callback_ref,
    intent_ref: entry.record.intent_ref,
    disposition: entry.disposition,
    outcome: entry.record.callback.outcome,
    settlement_eligible,
    manual_intervention: manual,
    authoritative_reconciliation,
    source_at: entry.record.callback.source_at,
    retrieved_at: entry.record.callback.retrieved_at,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn callback_recovery_integrations_v3(
  projection : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> ReadOnlyArray[CallbackRecoveryIntegrationV3] raise OrchestrationError {
  let values : Array[CallbackRecoveryIntegrationV3] = []
  for entry in projection.entries {
    if entry.record.intent_ref == intent_ref {
      values.push(make_callback_recovery_integration_v3(projection, entry))
    }
  }
  ReadOnlyArray::from_array(values)
}

///|
pub fn latest_settlement_eligible_callback_v3(
  projection : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> CallbackRecoveryIntegrationV3? raise OrchestrationError {
  let integrations = callback_recovery_integrations_v3(projection, intent_ref)
  let mut latest : CallbackRecoveryIntegrationV3? = None
  for value in integrations {
    if value.manual_intervention || value.authoritative_reconciliation {
      latest = None
    } else if value.settlement_eligible {
      latest = Some(value)
    }
  }
  latest
}

///|
fn callback_recovery_state_v3(
  projection : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> @effects.EffectRecoveryStateV3? raise OrchestrationError {
  let integrations = callback_recovery_integrations_v3(projection, intent_ref)
  if integrations.any(value => value.manual_intervention) {
    return Some(@effects.RecoveryManualInterventionV3)
  }
  let mut latest_settlement : CallbackRecoveryIntegrationV3? = None
  let mut needs_reconciliation = false
  for value in integrations {
    if value.authoritative_reconciliation {
      latest_settlement = None
      needs_reconciliation = true
    } else if value.settlement_eligible {
      latest_settlement = Some(value)
      needs_reconciliation = false
    }
  }
  match latest_settlement {
    Some(value) =>
      Some(
        match value.outcome {
          @effects.RecoveryKnownSucceededV3 =>
            @effects.RecoveryReconciledSuccessV3
          @effects.RecoveryKnownFailedV3 => @effects.RecoveryReconciledFailureV3
          @effects.RecoveryConfirmedNotAppliedV3 =>
            @effects.RecoveryConfirmedNotAppliedRetryEligibleV3
          @effects.RecoveryStillUnknownV3 =>
            @effects.RecoveryUnknownRequiresReconciliationV3
        },
      )
    None if needs_reconciliation =>
      Some(@effects.RecoveryUnknownRequiresReconciliationV3)
    None => None
  }
}

///|
pub fn CallbackRecoveryIntegrationV3::record_ref(
  self : CallbackRecoveryIntegrationV3,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn CallbackRecoveryIntegrationV3::intent_ref(
  self : CallbackRecoveryIntegrationV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn CallbackRecoveryIntegrationV3::disposition(
  self : CallbackRecoveryIntegrationV3,
) -> RecoveryCallbackDispositionV3 {
  self.disposition
}

///|
pub fn CallbackRecoveryIntegrationV3::outcome(
  self : CallbackRecoveryIntegrationV3,
) -> @effects.ExternalRecoveryOutcomeV3 {
  self.outcome
}

///|
pub fn CallbackRecoveryIntegrationV3::settlement_eligible(
  self : CallbackRecoveryIntegrationV3,
) -> Bool {
  self.settlement_eligible
}

///|
pub fn CallbackRecoveryIntegrationV3::requires_manual_intervention(
  self : CallbackRecoveryIntegrationV3,
) -> Bool {
  self.manual_intervention
}

///|
pub fn CallbackRecoveryIntegrationV3::requires_authoritative_reconciliation(
  self : CallbackRecoveryIntegrationV3,
) -> Bool {
  self.authoritative_reconciliation
}

///|
pub fn CallbackRecoveryIntegrationV3::source_at(
  self : CallbackRecoveryIntegrationV3,
) -> Int64 {
  self.source_at
}

///|
pub fn CallbackRecoveryIntegrationV3::retrieved_at(
  self : CallbackRecoveryIntegrationV3,
) -> Int64 {
  self.retrieved_at
}

///|
pub fn CallbackRecoveryIntegrationV3::canonical_bytes(
  self : CallbackRecoveryIntegrationV3,
) -> Bytes {
  self.canonical
}

///|
pub fn CallbackRecoveryIntegrationV3::digest(
  self : CallbackRecoveryIntegrationV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::recovery_evidence_head_v3(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> RecoveryEvidenceHeadV3 raise OrchestrationError {
  make_recovery_evidence_head_v3(
    self.binding.evidence_workflow,
    self.binding.work_workflow,
    self.replay.head().revision(),
    self.replay.head().last_event_digest(),
    self.replay.replay_digest(),
    self.state_digest,
  )
}
