///|
priv struct FinalLearningMaterialV1 {
  kind : FinalLearningRecordKindV1
  primary_ref : @contracts.RecordRef
  primary_bytes : Bytes
  source_refs : Array[@contracts.RecordRef]
  previous_lineage_ref : @contracts.RecordRef?
  snapshot_ref : @contracts.RecordRef?
  snapshot_bytes : Bytes?
  state_tag : String
  ordinal : Int64
  limit : Int64
  evidence : Array[@contracts.EvidenceRef]
  occurred_at : Int64
}

///|
pub struct FinalLearningPreparedCommitV1 {
  entry : FinalLearningDurableRecordV1
  event : @storage.WorkflowEvent
  request : @storage.CommitRequest
  guarded_request : @storage.GuardedCommitRequest
}

///|
pub fn FinalLearningPreparedCommitV1::record(
  self : FinalLearningPreparedCommitV1,
) -> FinalLearningDurableRecordV1 {
  self.entry
}

///|
pub fn FinalLearningPreparedCommitV1::event(
  self : FinalLearningPreparedCommitV1,
) -> @storage.WorkflowEvent {
  self.event
}

///|
pub fn FinalLearningPreparedCommitV1::request(
  self : FinalLearningPreparedCommitV1,
) -> @storage.CommitRequest {
  self.request
}

///|
pub fn FinalLearningPreparedCommitV1::guarded_request(
  self : FinalLearningPreparedCommitV1,
) -> @storage.GuardedCommitRequest {
  self.guarded_request
}

///|
fn final_learning_guard_from_replay_v1(
  replay : @storage.ReplayResult,
) -> @storage.WorkflowHeadGuard raise {
  @storage.WorkflowHeadGuard::new(
    replay.workflow(),
    replay.head().revision(),
    replay.head().last_event_digest(),
    replay.replay_digest(),
  )
}

///|
fn final_learning_event_v1(
  binding : FinalLearningStreamBindingV1,
  entry : FinalLearningDurableRecordV1,
) -> @storage.WorkflowEvent raise {
  let evidence = [ for value in entry.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    orchestration_contract_id,
    orchestration_record_version,
    entry.event_id,
    final_learning_event_kind_v1,
    entry.primary_ref,
    orchestration_schema(final_learning_event_kind_v1),
    entry.canonical,
    orchestration_producer_id,
    orchestration_record_version,
    [],
    evidence,
    run_ref=binding.stream_workflow,
    correlation_ref=binding.stream_workflow.id(),
    causation_ref=entry.primary_ref.id(),
    idempotency_ref=entry.durable_ref.id(),
    previous_digest?=entry.expected_head_digest,
  )
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    binding.stream_workflow,
    entry.event_id,
    entry.expected_revision + 1L,
    entry.expected_revision + 1L,
    entry.durable_ref.id(),
    envelope,
    evidence,
    previous_event_digest?=entry.expected_head_digest,
  )
}

///|
fn prepare_final_learning_commit_v1(
  binding : FinalLearningStreamBindingV1,
  stream_replay : @storage.ReplayResult,
  source_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
  material : FinalLearningMaterialV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPreparedCommitV1 raise {
  let current = fold_final_learning_stream_v1(
    binding, stream_replay, source_replay, governance_replay,
  )
  let entry = make_final_learning_durable_record_v1(
    binding,
    material.kind,
    material.primary_ref,
    material.primary_bytes,
    material.source_refs,
    material.previous_lineage_ref,
    material.snapshot_ref,
    material.snapshot_bytes,
    material.state_tag,
    material.ordinal,
    material.limit,
    material.evidence,
    material.occurred_at,
    stream_replay,
    event_id,
    command_idempotency_key,
  )
  validate_final_learning_transition_v1(current.entries, entry)
  let event = final_learning_event_v1(binding, entry)
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    binding.stream_workflow,
    entry.expected_revision,
    command_idempotency_key,
    [event],
    [],
  )
  let guarded_request = @storage.GuardedCommitRequest::new(request, [
    final_learning_guard_from_replay_v1(source_replay),
    final_learning_guard_from_replay_v1(governance_replay),
  ])
  { entry, event, request, guarded_request }
}

///|
fn[S : @storage.RegistryBoundGuardedStoragePort] require_final_learning_selected_profile_v1(
  store : S,
  expected_profile_id : String,
  binding : FinalLearningStreamBindingV1,
) -> Unit raise {
  let profile = store.selected_guard_profile()
  let workflows = profile.guard_workflows()
  if profile.profile_id() != expected_profile_id ||
    workflows.length() != 2 ||
    workflows[0] != binding.source_workflow ||
    workflows[1] != binding.governance_workflow {
    raise RecoveryViolation(field="final_learning_selected_profile_v1")
  }
}

///|
pub struct FinalLearningCommitReceiptV1 {
  receipt_ref : @contracts.RecordRef
  durable_record_ref : @contracts.RecordRef
  primary_ref : @contracts.RecordRef
  event_ref : @contracts.RecordRef
  command_idempotency_key : String
  batch_digest : @contracts.ContentDigest
  workflow_revision : Int64
  workflow_head_digest : @contracts.ContentDigest
  replay_digest : @contracts.ContentDigest
  state_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn mint_final_learning_commit_receipt_v1(
  current : CurrentFinalLearningProjectionV1,
  entry : FinalLearningDurableRecordV1,
) -> FinalLearningCommitReceiptV1 raise OrchestrationError {
  guard current.entries.any(value => {
    value.durable_ref == entry.durable_ref && value.canonical == entry.canonical
  }) else {
    raise ReplayBindingViolation(field="final_learning_receipt_entry_v1")
  }
  let events = current.replay
    .events()
    .filter(event => {
      event.payload().idempotency_ref() == Some(entry.durable_ref.id())
    })
  if events.length() != 1 {
    raise ReplayBindingViolation(field="final_learning_receipt_event_v1")
  }
  let event = events[0]
  let batches = current.replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref()
    })
  if batches.length() != 1 {
    raise ReplayBindingViolation(field="final_learning_receipt_batch_v1")
  }
  guard current.replay.head().last_event_digest() is Some(head_digest) else {
    raise ReplayBindingViolation(field="final_learning_receipt_head_v1")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/FINAL-LEARNING-COMMIT-RECEIPT-V1/1.0.0")
  writer.string("1.0.0")
  write_ref(writer, entry.durable_ref)
  write_ref(writer, entry.primary_ref)
  write_ref(writer, event.event_ref())
  writer.string(entry.command_idempotency_key)
  writer.string(batches[0].batch_digest().text())
  writer.int64(current.replay.head().revision())
  writer.string(head_digest.text())
  writer.string(current.replay.replay_digest().text())
  writer.string(current.state_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref(
      "orchestration-final-learning-commit-receipt-v1",
      entry.durable_ref.id(),
      digest,
    ),
    durable_record_ref: entry.durable_ref,
    primary_ref: entry.primary_ref,
    event_ref: event.event_ref(),
    command_idempotency_key: entry.command_idempotency_key,
    batch_digest: batches[0].batch_digest(),
    workflow_revision: current.replay.head().revision(),
    workflow_head_digest: head_digest,
    replay_digest: current.replay.replay_digest(),
    state_digest: current.state_digest,
    canonical,
    digest,
  }
}

///|
pub fn FinalLearningCommitReceiptV1::validate_current(
  self : FinalLearningCommitReceiptV1,
  current : CurrentFinalLearningProjectionV1,
) -> Unit raise OrchestrationError {
  if current.replay.head().revision() != self.workflow_revision ||
    current.replay.head().last_event_digest() != Some(self.workflow_head_digest) ||
    current.replay.replay_digest() != self.replay_digest ||
    current.state_digest != self.state_digest {
    raise ReplayBindingViolation(field="final_learning_receipt_current_v1")
  }
  guard current.entries.any(entry => {
    entry.durable_ref == self.durable_record_ref &&
    entry.primary_ref == self.primary_ref
  }) else {
    raise ReplayBindingViolation(field="final_learning_receipt_record_v1")
  }
  let batches = current.replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == self.event_ref
    })
  if batches.length() != 1 ||
    batches[0].command_idempotency_key() != self.command_idempotency_key ||
    batches[0].batch_digest() != self.batch_digest ||
    @contracts.sha256_digest(self.canonical) != self.digest ||
    self.receipt_ref.digest() != self.digest {
    raise ReplayBindingViolation(field="final_learning_receipt_integrity_v1")
  }
}

///|
pub fn FinalLearningCommitReceiptV1::record_ref(
  self : FinalLearningCommitReceiptV1,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn FinalLearningCommitReceiptV1::durable_record_ref(
  self : FinalLearningCommitReceiptV1,
) -> @contracts.RecordRef {
  self.durable_record_ref
}

///|
pub fn FinalLearningCommitReceiptV1::primary_ref(
  self : FinalLearningCommitReceiptV1,
) -> @contracts.RecordRef {
  self.primary_ref
}

///|
pub fn FinalLearningCommitReceiptV1::canonical_bytes(
  self : FinalLearningCommitReceiptV1,
) -> Bytes {
  self.canonical
}

///|
pub fn FinalLearningCommitReceiptV1::digest(
  self : FinalLearningCommitReceiptV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum FinalLearningPersistenceResultV1 {
  FinalLearningFreshlyPersistedV1(FinalLearningCommitReceiptV1)
  FinalLearningAlreadyPersistedV1(FinalLearningCommitReceiptV1)
  FinalLearningRaceLostV1
  FinalLearningGuardStaleV1(@storage.GuardConflictReceipt)
}

///|
fn same_record_identity_v1(
  left : @contracts.RecordRef,
  right : @contracts.RecordRef,
) -> Bool {
  left.kind() == right.kind() &&
  left.id() == right.id() &&
  left.version() == right.version()
}

///|
fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_final_learning_material_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  material : FinalLearningMaterialV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  let expected_profile_id = final_learning_profile_for_kind_v1(material.kind)
  require_final_learning_selected_profile_v1(
    store, expected_profile_id, binding,
  )
  let stream_replay = store.replay(binding.stream_workflow)
  let source_replay = store.replay_registered_guard(binding.source_workflow)
  let governance_replay = store.replay_registered_guard(
    binding.governance_workflow,
  )
  let current = fold_final_learning_stream_v1(
    binding, stream_replay, source_replay, governance_replay,
  )
  for existing in current.entries {
    if same_record_identity_v1(existing.primary_ref, material.primary_ref) {
      if existing.primary_ref != material.primary_ref ||
        existing.primary_bytes != material.primary_bytes ||
        existing.kind != material.kind {
        raise IdentityMismatch(field="final_learning_immutable_primary_v1")
      }
      return FinalLearningAlreadyPersistedV1(
        mint_final_learning_commit_receipt_v1(current, existing),
      )
    }
    if existing.command_idempotency_key == command_idempotency_key {
      raise IdempotencyConflict(key=command_idempotency_key)
    }
  }
  let prepared = prepare_final_learning_commit_v1(
    binding, stream_replay, source_replay, governance_replay, material, event_id,
    command_idempotency_key,
  )
  try {
    match store.classified_guarded_commit(prepared.guarded_request) {
      @storage.FreshlyApplied(_) => {
        let replayed_stream = store.replay(binding.stream_workflow)
        let replayed_source = store.replay_registered_guard(
          binding.source_workflow,
        )
        let replayed_governance = store.replay_registered_guard(
          binding.governance_workflow,
        )
        let replayed = fold_final_learning_stream_v1(
          binding, replayed_stream, replayed_source, replayed_governance,
        )
        guard final_learning_entry_by_primary_v1(
            replayed.entries,
            material.primary_ref,
          )
          is Some(entry) else {
          raise ReplayBindingViolation(field="final_learning_commit_replay_v1")
        }
        FinalLearningFreshlyPersistedV1(
          mint_final_learning_commit_receipt_v1(replayed, entry),
        )
      }
      @storage.AlreadyCommitted(_) => {
        let replayed = fold_final_learning_stream_v1(
          binding,
          store.replay(binding.stream_workflow),
          store.replay_registered_guard(binding.source_workflow),
          store.replay_registered_guard(binding.governance_workflow),
        )
        guard final_learning_entry_by_primary_v1(
            replayed.entries,
            material.primary_ref,
          )
          is Some(entry) else {
          raise ReplayBindingViolation(field="final_learning_commit_replay_v1")
        }
        FinalLearningAlreadyPersistedV1(
          mint_final_learning_commit_receipt_v1(replayed, entry),
        )
      }
      @storage.GuardRejected(receipt) => FinalLearningGuardStaleV1(receipt)
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) => FinalLearningRaceLostV1
    error => raise error
  }
}

///|
fn candidate_material_v1(
  binding : FinalLearningStreamBindingV1,
  candidate : FinalDeliverableCandidateV1,
) -> FinalLearningMaterialV1 raise OrchestrationError {
  if candidate.workflow() != binding.source_workflow {
    raise WorkflowMismatch(field="durable_candidate_source_workflow_v1")
  }
  {
    kind: DurableDeliverableCandidateV1,
    primary_ref: candidate.record_ref(),
    primary_bytes: candidate.canonical_bytes(),
    source_refs: [
      candidate.terminal_receipt_ref(),
      candidate.ability_ref(),
      candidate.intake_authority_ref(),
    ],
    previous_lineage_ref: None,
    snapshot_ref: None,
    snapshot_bytes: None,
    state_tag: "candidate",
    ordinal: 0L,
    limit: 0L,
    evidence: [
      for value in candidate.evidence() => value
    ],
    occurred_at: candidate.submitted_at(),
  }
}

///|
fn decision_material_v1(
  decision : FinalDeliverableDecisionV1,
) -> FinalLearningMaterialV1 {
  {
    kind: DurableDeliverableDecisionV1,
    primary_ref: decision.record_ref(),
    primary_bytes: decision.canonical_bytes(),
    source_refs: [
      decision.candidate_ref(),
      decision.ability_ref(),
      decision.authority_ref(),
      decision.review_request_ref(),
      decision.review_decision_ref(),
      decision.human_reviewer_ref(),
    ],
    previous_lineage_ref: Some(decision.candidate_ref()),
    snapshot_ref: None,
    snapshot_bytes: None,
    state_tag: decision.disposition().wire(),
    ordinal: 0L,
    limit: 0L,
    evidence: [
      for value in decision.evidence() => value
    ],
    occurred_at: decision.decided_at(),
  }
}

///|
fn artifact_material_v1(
  artifact : DeliverableArtifactRevisionV1,
) -> FinalLearningMaterialV1 {
  {
    kind: DurableArtifactRevisionV1,
    primary_ref: artifact.record_ref(),
    primary_bytes: artifact.canonical_bytes(),
    source_refs: [
      artifact.candidate_ref(),
      artifact.finalization_decision_ref(),
      artifact.artifact().record(),
      artifact.lineage_root_ref(),
    ],
    previous_lineage_ref: artifact.previous_revision_ref(),
    snapshot_ref: None,
    snapshot_bytes: None,
    state_tag: "artifact-revision",
    ordinal: artifact.revision_ordinal(),
    limit: 0L,
    evidence: [
      for value in artifact.evidence() => value
    ],
    occurred_at: artifact.created_at(),
  }
}

///|
fn delivery_material_v1(
  delivery : GovernedDeliveryReceiptV1,
) -> FinalLearningMaterialV1 {
  {
    kind: DurableDeliveryReceiptV1,
    primary_ref: delivery.record_ref(),
    primary_bytes: delivery.canonical_bytes(),
    source_refs: [
      delivery.candidate_ref(),
      delivery.finalization_decision_ref(),
      delivery.artifact_revision_ref(),
      delivery.artifact_ref(),
      delivery.destination_ref(),
      delivery.authority_ref(),
      delivery.review_request_ref(),
      delivery.review_decision_ref(),
      delivery.human_reviewer_ref(),
    ],
    previous_lineage_ref: Some(delivery.artifact_revision_ref()),
    snapshot_ref: None,
    snapshot_bytes: None,
    state_tag: "delivered",
    ordinal: 0L,
    limit: 0L,
    evidence: [
      for value in delivery.evidence() => value
    ],
    occurred_at: delivery.delivered_at(),
  }
}

///|
fn observation_material_v1(
  history : OutcomeHistoryV1,
  observation : OutcomeObservationV1,
) -> FinalLearningMaterialV1 raise OrchestrationError {
  if history.head_ref() != Some(observation.record_ref()) ||
    history.delivery_receipt_ref() != observation.delivery_receipt_ref() {
    raise IdentityMismatch(field="durable_outcome_history_head_v1")
  }
  let sources : Array[@contracts.RecordRef] = [
    observation.delivery_receipt_ref(),
  ]
  match observation.late_for_ref() {
    Some(value) => sources.push(value)
    None => ()
  }
  match observation.correction_of_ref() {
    Some(value) => sources.push(value)
    None => ()
  }
  for value in observation.conflicts_with() {
    if !sources.any(existing => existing == value) {
      sources.push(value)
    }
  }
  {
    kind: DurableOutcomeObservationV1,
    primary_ref: observation.record_ref(),
    primary_bytes: observation.canonical_bytes(),
    source_refs: sources,
    previous_lineage_ref: observation.previous_observation_ref(),
    snapshot_ref: Some(history.record_ref()),
    snapshot_bytes: Some(history.canonical_bytes()),
    state_tag: observation.kind().wire(),
    ordinal: observation.sequence(),
    limit: 0L,
    evidence: [
      for value in observation.evidence() => value
    ],
    occurred_at: observation.recorded_at(),
  }
}

///|
fn assessment_material_v1(
  assessment : OpaqueThreeGapAssessmentV1,
) -> FinalLearningMaterialV1 {
  {
    kind: DurableGapAssessmentV1,
    primary_ref: assessment.record_ref(),
    primary_bytes: assessment.canonical_bytes(),
    source_refs: [
      assessment.delivery_receipt_ref(),
      assessment.outcome_history_ref(),
      assessment.assessment_method_ref(),
      assessment.assessor_ability_ref(),
    ],
    previous_lineage_ref: Some(assessment.outcome_history_ref()),
    snapshot_ref: None,
    snapshot_bytes: None,
    state_tag: "opaque-assessment",
    ordinal: 0L,
    limit: 0L,
    evidence: [
      for value in assessment.evidence() => value
    ],
    occurred_at: assessment.assessed_at(),
  }
}

///|
fn proposal_material_v1(
  proposal : BoundedImprovementProposalV1,
) -> FinalLearningMaterialV1 {
  {
    kind: DurableImprovementProposalV1,
    primary_ref: proposal.record_ref(),
    primary_bytes: proposal.canonical_bytes(),
    source_refs: [
      proposal.assessment_ref(),
      proposal.old_version_ref(),
      proposal.new_version_ref(),
    ],
    previous_lineage_ref: Some(proposal.assessment_ref()),
    snapshot_ref: None,
    snapshot_bytes: None,
    state_tag: proposal.route().wire(),
    ordinal: 0L,
    limit: proposal.max_offline_evaluations(),
    evidence: [
      for value in proposal.evidence() => value
    ],
    occurred_at: proposal.proposed_at(),
  }
}

///|
fn evaluation_material_v1(
  ledger : OfflineEvaluationLedgerV1,
  evaluation : OfflineProposalEvaluationV1,
) -> FinalLearningMaterialV1 raise OrchestrationError {
  if ledger.proposal_ref() != evaluation.proposal_ref() ||
    ledger.evaluations().last().map(value => value.record_ref()) !=
    Some(evaluation.record_ref()) {
    raise IdentityMismatch(field="durable_evaluation_ledger_head_v1")
  }
  let previous = if ledger.evaluations().length() <= 1 {
    None
  } else {
    Some(ledger.evaluations()[ledger.evaluations().length() - 2].record_ref())
  }
  {
    kind: DurableOfflineEvaluationV1,
    primary_ref: evaluation.record_ref(),
    primary_bytes: evaluation.canonical_bytes(),
    source_refs: [
      evaluation.proposal_ref(),
      evaluation.evaluator_ability_ref(),
      evaluation.dataset_snapshot_ref(),
      evaluation.harness_version_ref(),
    ],
    previous_lineage_ref: previous,
    snapshot_ref: Some(ledger.record_ref()),
    snapshot_bytes: Some(ledger.canonical_bytes()),
    state_tag: evaluation.outcome().wire(),
    ordinal: evaluation.evaluation_ordinal(),
    limit: ledger.maximum_evaluations,
    evidence: [
      for value in evaluation.evidence() => value
    ],
    occurred_at: evaluation.evaluated_at(),
  }
}

///|
fn human_decision_material_v1(
  decision : HumanVersionDecisionV1,
) -> FinalLearningMaterialV1 {
  {
    kind: DurableHumanVersionDecisionV1,
    primary_ref: decision.record_ref(),
    primary_bytes: decision.canonical_bytes(),
    source_refs: [
      decision.proposal_ref(),
      decision.evaluation_ref(),
      decision.old_version_ref(),
      decision.new_version_ref(),
      decision.named_human_ref(),
      decision.authority_ref(),
      decision.review_decision_ref(),
    ],
    previous_lineage_ref: Some(decision.proposal_ref()),
    snapshot_ref: None,
    snapshot_bytes: None,
    state_tag: decision.outcome().wire(),
    ordinal: 0L,
    limit: 0L,
    evidence: [
      for value in decision.evidence() => value
    ],
    occurred_at: decision.decided_at(),
  }
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_final_deliverable_candidate_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  candidate : FinalDeliverableCandidateV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  persist_final_learning_material_v1(
    store,
    binding,
    candidate_material_v1(binding, candidate),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_final_deliverable_decision_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  decision : FinalDeliverableDecisionV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  persist_final_learning_material_v1(
    store,
    binding,
    decision_material_v1(decision),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_deliverable_artifact_revision_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  artifact : DeliverableArtifactRevisionV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  persist_final_learning_material_v1(
    store,
    binding,
    artifact_material_v1(artifact),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_governed_delivery_receipt_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  delivery : GovernedDeliveryReceiptV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  persist_final_learning_material_v1(
    store,
    binding,
    delivery_material_v1(delivery),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_outcome_observation_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  history : OutcomeHistoryV1,
  observation : OutcomeObservationV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  persist_final_learning_material_v1(
    store,
    binding,
    observation_material_v1(history, observation),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_opaque_three_gap_assessment_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  assessment : OpaqueThreeGapAssessmentV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  persist_final_learning_material_v1(
    store,
    binding,
    assessment_material_v1(assessment),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_bounded_improvement_proposal_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  proposal : BoundedImprovementProposalV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  persist_final_learning_material_v1(
    store,
    binding,
    proposal_material_v1(proposal),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_offline_proposal_evaluation_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  ledger : OfflineEvaluationLedgerV1,
  evaluation : OfflineProposalEvaluationV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  persist_final_learning_material_v1(
    store,
    binding,
    evaluation_material_v1(ledger, evaluation),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_human_version_decision_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
  decision : HumanVersionDecisionV1,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningPersistenceResultV1 raise {
  persist_final_learning_material_v1(
    store,
    binding,
    human_decision_material_v1(decision),
    event_id,
    command_idempotency_key,
  )
}

///|
pub fn[S : @storage.RegistryBoundGuardedStoragePort] replay_current_final_learning_v1(
  store : S,
  binding : FinalLearningStreamBindingV1,
) -> CurrentFinalLearningProjectionV1 raise {
  fold_final_learning_stream_v1(
    binding,
    store.replay(binding.stream_workflow),
    store.replay_registered_guard(binding.source_workflow),
    store.replay_registered_guard(binding.governance_workflow),
  )
}
