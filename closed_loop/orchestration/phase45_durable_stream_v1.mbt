///|
let final_learning_event_kind_v1 = "closed-loop.final-learning.record.v1"

///|
let final_learning_finalization_profile_id_v1 = "final-deliverable"

///|
let final_learning_learning_profile_id_v1 = "learning-loop"

///|
let final_learning_binding_magic_v1 = b"FLOW7/FINAL-LEARNING-STREAM-BINDING-V1/1.0.0"

///|
let final_learning_record_magic_v1 = b"FLOW7/FINAL-LEARNING-DURABLE-RECORD-V1/1.0.0"

///|
pub fn final_deliverable_guard_profile_id_v1() -> String {
  final_learning_finalization_profile_id_v1
}

///|
pub fn learning_loop_guard_profile_id_v1() -> String {
  final_learning_learning_profile_id_v1
}

///|
pub struct FinalLearningStreamBindingV1 {
  binding_ref : @contracts.RecordRef
  stream_workflow : @contracts.RecordRef
  source_workflow : @contracts.RecordRef
  governance_workflow : @contracts.RecordRef
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn FinalLearningStreamBindingV1::new(
  binding_id : String,
  stream_workflow : @contracts.RecordRef,
  source_workflow : @contracts.RecordRef,
  governance_workflow : @contracts.RecordRef,
) -> FinalLearningStreamBindingV1 raise OrchestrationError {
  require_text(binding_id, "final_learning_stream_binding_id_v1")
  if stream_workflow == source_workflow ||
    stream_workflow == governance_workflow ||
    source_workflow == governance_workflow {
    raise IdentityMismatch(field="final_learning_stream_roots_v1")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(final_learning_binding_magic_v1)
  writer.string("1.0.0")
  writer.string(binding_id)
  write_ref(writer, stream_workflow)
  write_ref(writer, source_workflow)
  write_ref(writer, governance_workflow)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    binding_ref: self_ref(
      "orchestration-final-learning-stream-binding-v1", binding_id, digest,
    ),
    stream_workflow,
    source_workflow,
    governance_workflow,
    canonical,
    digest,
  }
}

///|
pub fn FinalLearningStreamBindingV1::record_ref(
  self : FinalLearningStreamBindingV1,
) -> @contracts.RecordRef {
  self.binding_ref
}

///|
pub fn FinalLearningStreamBindingV1::stream_workflow(
  self : FinalLearningStreamBindingV1,
) -> @contracts.RecordRef {
  self.stream_workflow
}

///|
pub fn FinalLearningStreamBindingV1::source_workflow(
  self : FinalLearningStreamBindingV1,
) -> @contracts.RecordRef {
  self.source_workflow
}

///|
pub fn FinalLearningStreamBindingV1::governance_workflow(
  self : FinalLearningStreamBindingV1,
) -> @contracts.RecordRef {
  self.governance_workflow
}

///|
pub fn FinalLearningStreamBindingV1::canonical_bytes(
  self : FinalLearningStreamBindingV1,
) -> Bytes {
  self.canonical
}

///|
pub fn FinalLearningStreamBindingV1::digest(
  self : FinalLearningStreamBindingV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn final_deliverable_guard_profile_config_v1(
  binding : FinalLearningStreamBindingV1,
) -> @storage.GuardProfileConfig raise {
  @storage.GuardProfileConfig::new(
    final_deliverable_guard_profile_id_v1(),
    "final deliverable",
    [binding.source_workflow, binding.governance_workflow],
  )
}

///|
pub fn learning_loop_guard_profile_config_v1(
  binding : FinalLearningStreamBindingV1,
) -> @storage.GuardProfileConfig raise {
  @storage.GuardProfileConfig::new(
    learning_loop_guard_profile_id_v1(),
    "learning loop",
    [binding.source_workflow, binding.governance_workflow],
  )
}

///|
pub fn final_learning_guard_profile_configs_v1(
  binding : FinalLearningStreamBindingV1,
) -> Array[@storage.GuardProfileConfig] raise {
  [
    final_deliverable_guard_profile_config_v1(binding),
    learning_loop_guard_profile_config_v1(binding),
  ]
}

///|
pub fn activate_final_learning_memory_profiles_v1(
  store : @storage.MemoryStore,
  binding : FinalLearningStreamBindingV1,
) -> @storage.GuardedWorkflowActivationReceipt raise {
  store.activate_guarded_workflow_profiles(
    binding.stream_workflow,
    final_learning_guard_profile_configs_v1(binding),
  )
}

///|
#cfg(target="native")
pub fn activate_final_learning_filesystem_profiles_v1(
  stream_store : @storage.FileSystemStore,
  binding : FinalLearningStreamBindingV1,
  source_store : @storage.FileSystemStore,
  governance_store : @storage.FileSystemStore,
) -> @storage.GuardedWorkflowActivationReceipt raise {
  stream_store.activate_guarded_workflow_profiles(
    binding.stream_workflow,
    final_learning_guard_profile_configs_v1(binding),
    [[source_store, governance_store], [source_store, governance_store]],
  )
}

///|
pub fn bind_final_deliverable_memory_store_v1(
  store : @storage.MemoryStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.GuardedMemoryStore raise {
  @storage.GuardedMemoryStore::new_for_profile(
    store,
    receipt,
    final_deliverable_guard_profile_id_v1(),
  )
}

///|
pub fn bind_learning_loop_memory_store_v1(
  store : @storage.MemoryStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.GuardedMemoryStore raise {
  @storage.GuardedMemoryStore::new_for_profile(
    store,
    receipt,
    learning_loop_guard_profile_id_v1(),
  )
}

///|
#cfg(target="native")
pub fn bind_final_deliverable_filesystem_store_v1(
  store : @storage.FileSystemStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.RegistryBoundFileSystemStore raise {
  @storage.RegistryBoundFileSystemStore::new_for_profile(
    store,
    receipt,
    final_deliverable_guard_profile_id_v1(),
  )
}

///|
#cfg(target="native")
pub fn bind_learning_loop_filesystem_store_v1(
  store : @storage.FileSystemStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.RegistryBoundFileSystemStore raise {
  @storage.RegistryBoundFileSystemStore::new_for_profile(
    store,
    receipt,
    learning_loop_guard_profile_id_v1(),
  )
}

///|
pub(all) enum FinalLearningRecordKindV1 {
  DurableDeliverableCandidateV1
  DurableDeliverableDecisionV1
  DurableArtifactRevisionV1
  DurableDeliveryReceiptV1
  DurableOutcomeObservationV1
  DurableGapAssessmentV1
  DurableImprovementProposalV1
  DurableOfflineEvaluationV1
  DurableHumanVersionDecisionV1
} derive(Eq, Debug)

///|
fn FinalLearningRecordKindV1::wire(self : FinalLearningRecordKindV1) -> String {
  match self {
    DurableDeliverableCandidateV1 => "deliverable-candidate"
    DurableDeliverableDecisionV1 => "deliverable-decision"
    DurableArtifactRevisionV1 => "artifact-revision"
    DurableDeliveryReceiptV1 => "delivery-receipt"
    DurableOutcomeObservationV1 => "outcome-observation"
    DurableGapAssessmentV1 => "gap-assessment"
    DurableImprovementProposalV1 => "improvement-proposal"
    DurableOfflineEvaluationV1 => "offline-evaluation"
    DurableHumanVersionDecisionV1 => "human-version-decision"
  }
}

///|
fn final_learning_record_kind_from_wire_v1(
  value : String,
) -> FinalLearningRecordKindV1 raise OrchestrationError {
  match value {
    "deliverable-candidate" => DurableDeliverableCandidateV1
    "deliverable-decision" => DurableDeliverableDecisionV1
    "artifact-revision" => DurableArtifactRevisionV1
    "delivery-receipt" => DurableDeliveryReceiptV1
    "outcome-observation" => DurableOutcomeObservationV1
    "gap-assessment" => DurableGapAssessmentV1
    "improvement-proposal" => DurableImprovementProposalV1
    "offline-evaluation" => DurableOfflineEvaluationV1
    "human-version-decision" => DurableHumanVersionDecisionV1
    _ => raise MalformedInput(field="final_learning_record_kind_v1")
  }
}

///|
fn final_learning_profile_for_kind_v1(
  kind : FinalLearningRecordKindV1,
) -> String {
  match kind {
    DurableDeliverableCandidateV1
    | DurableDeliverableDecisionV1
    | DurableArtifactRevisionV1
    | DurableDeliveryReceiptV1 => final_deliverable_guard_profile_id_v1()
    DurableOutcomeObservationV1
    | DurableGapAssessmentV1
    | DurableImprovementProposalV1
    | DurableOfflineEvaluationV1
    | DurableHumanVersionDecisionV1 => learning_loop_guard_profile_id_v1()
  }
}

///|
pub struct FinalLearningDurableRecordV1 {
  durable_ref : @contracts.RecordRef
  binding_ref : @contracts.RecordRef
  binding_digest : @contracts.ContentDigest
  workflow : @contracts.RecordRef
  kind : FinalLearningRecordKindV1
  primary_ref : @contracts.RecordRef
  primary_bytes : Bytes
  source_refs : ReadOnlyArray[@contracts.RecordRef]
  previous_lineage_ref : @contracts.RecordRef?
  snapshot_ref : @contracts.RecordRef?
  snapshot_bytes : Bytes?
  state_tag : String
  ordinal : Int64
  limit : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  occurred_at : Int64
  profile_id : String
  expected_revision : Int64
  expected_head_digest : @contracts.ContentDigest?
  expected_replay_digest : @contracts.ContentDigest
  event_id : String
  command_idempotency_key : String
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn final_learning_record_signing_bytes_v1(
  binding : FinalLearningStreamBindingV1,
  kind : FinalLearningRecordKindV1,
  primary_ref : @contracts.RecordRef,
  primary_bytes : Bytes,
  source_refs : ArrayView[@contracts.RecordRef],
  previous_lineage_ref : @contracts.RecordRef?,
  snapshot_ref : @contracts.RecordRef?,
  snapshot_bytes : Bytes?,
  state_tag : String,
  ordinal : Int64,
  limit : Int64,
  evidence : ArrayView[@contracts.EvidenceRef],
  occurred_at : Int64,
  expected_revision : Int64,
  expected_head_digest : @contracts.ContentDigest?,
  expected_replay_digest : @contracts.ContentDigest,
  event_id : String,
  command_idempotency_key : String,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(final_learning_record_magic_v1)
  writer.string("1.0.0")
  write_ref(writer, binding.binding_ref)
  writer.string(binding.digest.text())
  write_ref(writer, binding.stream_workflow)
  writer.string(kind.wire())
  write_ref(writer, primary_ref)
  writer.bytes(primary_bytes)
  write_refs_v1(writer, source_refs)
  write_optional_ref(writer, previous_lineage_ref)
  write_optional_ref(writer, snapshot_ref)
  match snapshot_bytes {
    None => writer.byte(0)
    Some(bytes) => {
      writer.byte(1)
      writer.bytes(bytes)
    }
  }
  writer.string(state_tag)
  writer.int64(ordinal)
  writer.int64(limit)
  write_evidence(writer, evidence)
  writer.int64(occurred_at)
  writer.string(final_learning_profile_for_kind_v1(kind))
  writer.int64(expected_revision)
  writer.optional_digest(expected_head_digest)
  writer.string(expected_replay_digest.text())
  writer.string(event_id)
  writer.string(command_idempotency_key)
  writer.finish()
}

///|
fn make_final_learning_durable_record_v1(
  binding : FinalLearningStreamBindingV1,
  kind : FinalLearningRecordKindV1,
  primary_ref : @contracts.RecordRef,
  primary_bytes : Bytes,
  source_refs : Array[@contracts.RecordRef],
  previous_lineage_ref : @contracts.RecordRef?,
  snapshot_ref : @contracts.RecordRef?,
  snapshot_bytes : Bytes?,
  state_tag : String,
  ordinal : Int64,
  limit : Int64,
  evidence : Array[@contracts.EvidenceRef],
  occurred_at : Int64,
  replay : @storage.ReplayResult,
  event_id : String,
  command_idempotency_key : String,
) -> FinalLearningDurableRecordV1 raise OrchestrationError {
  require_text(event_id, "final_learning_event_id_v1")
  require_text(command_idempotency_key, "final_learning_command_key_v1")
  require_text(state_tag, "final_learning_state_tag_v1")
  require_non_negative(ordinal, "final_learning_ordinal_v1")
  require_non_negative(limit, "final_learning_limit_v1")
  require_non_negative(occurred_at, "final_learning_occurred_at_v1")
  if replay.workflow() != binding.stream_workflow ||
    @contracts.sha256_digest(primary_bytes) != primary_ref.digest() {
    raise ReplayBindingViolation(field="final_learning_primary_binding_v1")
  }
  match (snapshot_ref, snapshot_bytes) {
    (None, None) => ()
    (Some(reference), Some(bytes)) =>
      if @contracts.sha256_digest(bytes) != reference.digest() {
        raise DigestMismatch(field="final_learning_snapshot_v1")
      }
    _ => raise MalformedInput(field="final_learning_snapshot_shape_v1")
  }
  let evidence = copy_evidence_v1(evidence)
  let expected_revision = replay.head().revision()
  let expected_head_digest = replay.head().last_event_digest()
  let expected_replay_digest = replay.replay_digest()
  let canonical = final_learning_record_signing_bytes_v1(
    binding, kind, primary_ref, primary_bytes, source_refs, previous_lineage_ref,
    snapshot_ref, snapshot_bytes, state_tag, ordinal, limit, evidence, occurred_at,
    expected_revision, expected_head_digest, expected_replay_digest, event_id, command_idempotency_key,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    durable_ref: self_ref(
      "orchestration-final-learning-durable-record-v1", event_id, digest,
    ),
    binding_ref: binding.binding_ref,
    binding_digest: binding.digest,
    workflow: binding.stream_workflow,
    kind,
    primary_ref,
    primary_bytes,
    source_refs: ReadOnlyArray::from_array(source_refs.copy()),
    previous_lineage_ref,
    snapshot_ref,
    snapshot_bytes,
    state_tag,
    ordinal,
    limit,
    evidence,
    occurred_at,
    profile_id: final_learning_profile_for_kind_v1(kind),
    expected_revision,
    expected_head_digest,
    expected_replay_digest,
    event_id,
    command_idempotency_key,
    canonical,
    digest,
  }
}

///|
fn decode_final_learning_durable_record_v1(
  binding : FinalLearningStreamBindingV1,
  bytes : Bytes,
) -> FinalLearningDurableRecordV1 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != final_learning_record_magic_v1 ||
    reader.read_string() != "1.0.0" {
    raise MalformedInput(field="final_learning_record_magic_v1")
  }
  let binding_ref = reader.read_ref()
  let binding_digest = reader.read_digest()
  let workflow = reader.read_ref()
  let kind = final_learning_record_kind_from_wire_v1(reader.read_string())
  let primary_ref = reader.read_ref()
  let primary_bytes = reader.read_bytes()
  let source_refs : Array[@contracts.RecordRef] = []
  let source_count = reader.read_count()
  for _ in 0..<source_count {
    source_refs.push(reader.read_ref())
  }
  let previous_lineage_ref = reader.read_optional_ref()
  let snapshot_ref = reader.read_optional_ref()
  let snapshot_bytes = match reader.read_byte() {
    0 => None
    1 => Some(reader.read_bytes())
    _ => raise MalformedInput(field="final_learning_snapshot_marker_v1")
  }
  let state_tag = reader.read_string()
  let ordinal = reader.read_int64()
  let limit = reader.read_int64()
  let evidence = reader.read_evidence()
  let occurred_at = reader.read_int64()
  let profile_id = reader.read_string()
  let expected_revision = reader.read_int64()
  let expected_head_digest = reader.read_optional_digest()
  let expected_replay_digest = reader.read_digest()
  let event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  reader.require_end()
  if binding_ref != binding.binding_ref ||
    binding_digest != binding.digest ||
    workflow != binding.stream_workflow ||
    profile_id != final_learning_profile_for_kind_v1(kind) ||
    expected_revision < 0L ||
    (expected_revision == 0L) != (expected_head_digest is None) ||
    ordinal < 0L ||
    limit < 0L ||
    occurred_at < 0L ||
    @contracts.sha256_digest(primary_bytes) != primary_ref.digest() {
    raise ReplayBindingViolation(field="final_learning_record_binding_v1")
  }
  match (snapshot_ref, snapshot_bytes) {
    (None, None) => ()
    (Some(reference), Some(snapshot)) =>
      if @contracts.sha256_digest(snapshot) != reference.digest() {
        raise DigestMismatch(field="final_learning_snapshot_v1")
      }
    _ => raise MalformedInput(field="final_learning_snapshot_shape_v1")
  }
  let canonical = final_learning_record_signing_bytes_v1(
    binding, kind, primary_ref, primary_bytes, source_refs, previous_lineage_ref,
    snapshot_ref, snapshot_bytes, state_tag, ordinal, limit, evidence, occurred_at,
    expected_revision, expected_head_digest, expected_replay_digest, event_id, command_idempotency_key,
  )
  if canonical != bytes {
    raise DigestMismatch(field="final_learning_record_noncanonical_v1")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    durable_ref: self_ref(
      "orchestration-final-learning-durable-record-v1", event_id, digest,
    ),
    binding_ref,
    binding_digest,
    workflow,
    kind,
    primary_ref,
    primary_bytes,
    source_refs: ReadOnlyArray::from_array(source_refs),
    previous_lineage_ref,
    snapshot_ref,
    snapshot_bytes,
    state_tag,
    ordinal,
    limit,
    evidence: ReadOnlyArray::from_array(evidence),
    occurred_at,
    profile_id,
    expected_revision,
    expected_head_digest,
    expected_replay_digest,
    event_id,
    command_idempotency_key,
    canonical,
    digest,
  }
}

///|
pub fn FinalLearningDurableRecordV1::record_ref(
  self : FinalLearningDurableRecordV1,
) -> @contracts.RecordRef {
  self.durable_ref
}

///|
pub fn FinalLearningDurableRecordV1::kind(
  self : FinalLearningDurableRecordV1,
) -> FinalLearningRecordKindV1 {
  self.kind
}

///|
pub fn FinalLearningDurableRecordV1::primary_ref(
  self : FinalLearningDurableRecordV1,
) -> @contracts.RecordRef {
  self.primary_ref
}

///|
pub fn FinalLearningDurableRecordV1::primary_bytes(
  self : FinalLearningDurableRecordV1,
) -> Bytes {
  self.primary_bytes
}

///|
pub fn FinalLearningDurableRecordV1::source_refs(
  self : FinalLearningDurableRecordV1,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.source_refs
}

///|
pub fn FinalLearningDurableRecordV1::snapshot_ref(
  self : FinalLearningDurableRecordV1,
) -> @contracts.RecordRef? {
  self.snapshot_ref
}

///|
pub fn FinalLearningDurableRecordV1::snapshot_bytes(
  self : FinalLearningDurableRecordV1,
) -> Bytes? {
  self.snapshot_bytes
}

///|
pub fn FinalLearningDurableRecordV1::state_tag(
  self : FinalLearningDurableRecordV1,
) -> String {
  self.state_tag
}

///|
pub fn FinalLearningDurableRecordV1::canonical_bytes(
  self : FinalLearningDurableRecordV1,
) -> Bytes {
  self.canonical
}

///|
pub fn FinalLearningDurableRecordV1::digest(
  self : FinalLearningDurableRecordV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct CurrentFinalLearningProjectionV1 {
  binding : FinalLearningStreamBindingV1
  replay : @storage.ReplayResult
  entries : ReadOnlyArray[FinalLearningDurableRecordV1]
  candidates : ReadOnlyArray[FinalLearningDurableRecordV1]
  decisions : ReadOnlyArray[FinalLearningDurableRecordV1]
  artifact_revisions : ReadOnlyArray[FinalLearningDurableRecordV1]
  deliveries : ReadOnlyArray[FinalLearningDurableRecordV1]
  observations : ReadOnlyArray[FinalLearningDurableRecordV1]
  assessments : ReadOnlyArray[FinalLearningDurableRecordV1]
  proposals : ReadOnlyArray[FinalLearningDurableRecordV1]
  evaluations : ReadOnlyArray[FinalLearningDurableRecordV1]
  human_decisions : ReadOnlyArray[FinalLearningDurableRecordV1]
  latest_outcome_history_ref : @contracts.RecordRef?
  latest_evaluation_ledger_refs : ReadOnlyArray[@contracts.RecordRef]
  state_digest : @contracts.ContentDigest
}

///|
fn final_learning_entry_by_primary_v1(
  entries : ArrayView[FinalLearningDurableRecordV1],
  reference : @contracts.RecordRef,
) -> FinalLearningDurableRecordV1? {
  first(entries, value => value.primary_ref == reference)
}

///|
fn final_learning_require_internal_source_v1(
  entries : ArrayView[FinalLearningDurableRecordV1],
  reference : @contracts.RecordRef,
  kind : FinalLearningRecordKindV1,
  field : String,
) -> FinalLearningDurableRecordV1 raise OrchestrationError {
  guard final_learning_entry_by_primary_v1(entries, reference) is Some(value) else {
    raise ReplayBindingViolation(field~)
  }
  if value.kind != kind {
    raise ReplayBindingViolation(field~)
  }
  value
}

///|
fn validate_final_learning_transition_v1(
  entries : ArrayView[FinalLearningDurableRecordV1],
  entry : FinalLearningDurableRecordV1,
) -> Unit raise OrchestrationError {
  if entries.any(value => {
      value.primary_ref == entry.primary_ref ||
      value.durable_ref == entry.durable_ref ||
      value.command_idempotency_key == entry.command_idempotency_key
    }) {
    raise ReplayBindingViolation(field="final_learning_duplicate_v1")
  }
  let sources = entry.source_refs
  match entry.kind {
    DurableDeliverableCandidateV1 =>
      if sources.length() != 3 ||
        entry.previous_lineage_ref is Some(_) ||
        entry.snapshot_ref is Some(_) ||
        entry.ordinal != 0L ||
        entry.limit != 0L ||
        entry.state_tag != "candidate" {
        raise ReplayBindingViolation(field="durable_candidate_shape_v1")
      }
    DurableDeliverableDecisionV1 => {
      if sources.length() != 6 ||
        entry.previous_lineage_ref != Some(sources[0]) ||
        entry.snapshot_ref is Some(_) ||
        entry.ordinal != 0L ||
        entry.limit != 0L ||
        !(entry.state_tag == "accepted" ||
        entry.state_tag == "rejected" ||
        entry.state_tag == "revision-requested" ||
        entry.state_tag == "escalated") {
        raise ReplayBindingViolation(field="durable_decision_shape_v1")
      }
      ignore(
        final_learning_require_internal_source_v1(
          entries,
          sources[0],
          DurableDeliverableCandidateV1,
          "durable_decision_candidate_v1",
        ),
      )
      if entries.any(value => {
          value.kind == DurableDeliverableDecisionV1 &&
          value.source_refs[0] == sources[0]
        }) {
        raise ReplayBindingViolation(field="durable_decision_finality_v1")
      }
    }
    DurableArtifactRevisionV1 => {
      if sources.length() != 4 ||
        entry.snapshot_ref is Some(_) ||
        entry.ordinal <= 0L ||
        entry.limit != 0L ||
        entry.state_tag != "artifact-revision" {
        raise ReplayBindingViolation(field="durable_artifact_shape_v1")
      }
      let decision = final_learning_require_internal_source_v1(
        entries,
        sources[1],
        DurableDeliverableDecisionV1,
        "durable_artifact_decision_v1",
      )
      if decision.state_tag != "accepted" ||
        decision.source_refs[0] != sources[0] {
        raise ReplayBindingViolation(field="durable_artifact_acceptance_v1")
      }
      match entry.previous_lineage_ref {
        None =>
          if entry.ordinal != 1L || sources[3] != sources[2] {
            raise ReplayBindingViolation(field="durable_artifact_root_v1")
          }
        Some(previous_ref) => {
          let previous = final_learning_require_internal_source_v1(
            entries,
            previous_ref,
            DurableArtifactRevisionV1,
            "durable_artifact_parent_v1",
          )
          if entry.ordinal != previous.ordinal + 1L ||
            sources[0] != previous.source_refs[0] ||
            sources[3] != previous.source_refs[3] {
            raise ReplayBindingViolation(field="durable_artifact_lineage_v1")
          }
        }
      }
    }
    DurableDeliveryReceiptV1 => {
      if sources.length() != 9 ||
        entry.previous_lineage_ref != Some(sources[2]) ||
        entry.snapshot_ref is Some(_) ||
        entry.ordinal != 0L ||
        entry.limit != 0L ||
        entry.state_tag != "delivered" {
        raise ReplayBindingViolation(field="durable_delivery_shape_v1")
      }
      let decision = final_learning_require_internal_source_v1(
        entries,
        sources[1],
        DurableDeliverableDecisionV1,
        "durable_delivery_decision_v1",
      )
      let artifact = final_learning_require_internal_source_v1(
        entries,
        sources[2],
        DurableArtifactRevisionV1,
        "durable_delivery_artifact_v1",
      )
      if decision.state_tag != "accepted" ||
        decision.source_refs[0] != sources[0] ||
        artifact.source_refs[0] != sources[0] ||
        artifact.source_refs[1] != sources[1] ||
        artifact.source_refs[2] != sources[3] {
        raise ReplayBindingViolation(field="durable_delivery_lineage_v1")
      }
      if entries.any(value => {
          value.kind == DurableDeliveryReceiptV1 &&
          value.source_refs[2] == sources[2]
        }) {
        raise ReplayBindingViolation(field="durable_delivery_finality_v1")
      }
    }
    DurableOutcomeObservationV1 => {
      if sources.is_empty() ||
        entry.snapshot_ref is None ||
        entry.ordinal <= 0L ||
        entry.limit != 0L ||
        !(entry.state_tag == "observed" ||
        entry.state_tag == "missing" ||
        entry.state_tag == "late" ||
        entry.state_tag == "conflicting" ||
        entry.state_tag == "corrected") {
        raise ReplayBindingViolation(field="durable_observation_shape_v1")
      }
      ignore(
        final_learning_require_internal_source_v1(
          entries,
          sources[0],
          DurableDeliveryReceiptV1,
          "durable_observation_delivery_v1",
        ),
      )
      let prior_observations = [
        for value in entries if value.kind == DurableOutcomeObservationV1 &&
        !value.source_refs.is_empty() &&
        value.source_refs[0] == sources[0] => value
      ]
      let prior = prior_observations.last().map(value => value.primary_ref)
      if entry.previous_lineage_ref != prior ||
        entry.ordinal != prior_observations.length().to_int64() + 1L {
        raise ReplayBindingViolation(field="durable_observation_order_v1")
      }
      for index in 1..<sources.length() {
        ignore(
          final_learning_require_internal_source_v1(
            entries,
            sources[index],
            DurableOutcomeObservationV1,
            "durable_observation_related_v1",
          ),
        )
      }
    }
    DurableGapAssessmentV1 => {
      if sources.length() != 4 ||
        entry.previous_lineage_ref != Some(sources[1]) ||
        entry.snapshot_ref is Some(_) ||
        entry.ordinal != 0L ||
        entry.limit != 0L ||
        entry.state_tag != "opaque-assessment" {
        raise ReplayBindingViolation(field="durable_assessment_shape_v1")
      }
      ignore(
        final_learning_require_internal_source_v1(
          entries,
          sources[0],
          DurableDeliveryReceiptV1,
          "durable_assessment_delivery_v1",
        ),
      )
      if !entries.any(value => {
          value.kind == DurableOutcomeObservationV1 &&
          value.snapshot_ref == Some(sources[1]) &&
          !value.source_refs.is_empty() &&
          value.source_refs[0] == sources[0]
        }) {
        raise ReplayBindingViolation(field="durable_assessment_history_v1")
      }
    }
    DurableImprovementProposalV1 => {
      if sources.length() != 3 ||
        entry.previous_lineage_ref != Some(sources[0]) ||
        entry.snapshot_ref is Some(_) ||
        entry.ordinal != 0L ||
        entry.limit <= 0L ||
        !(entry.state_tag == "memory" ||
        entry.state_tag == "skill" ||
        entry.state_tag == "flow" ||
        entry.state_tag == "code" ||
        entry.state_tag == "policy") {
        raise ReplayBindingViolation(field="durable_proposal_shape_v1")
      }
      ignore(
        final_learning_require_internal_source_v1(
          entries,
          sources[0],
          DurableGapAssessmentV1,
          "durable_proposal_assessment_v1",
        ),
      )
    }
    DurableOfflineEvaluationV1 => {
      if sources.length() != 4 ||
        entry.snapshot_ref is None ||
        entry.ordinal <= 0L ||
        entry.limit <= 0L ||
        entry.ordinal > entry.limit ||
        !(entry.state_tag == "passed" ||
        entry.state_tag == "failed" ||
        entry.state_tag == "inconclusive") {
        raise ReplayBindingViolation(field="durable_evaluation_shape_v1")
      }
      let proposal = final_learning_require_internal_source_v1(
        entries,
        sources[0],
        DurableImprovementProposalV1,
        "durable_evaluation_proposal_v1",
      )
      if proposal.limit != entry.limit {
        raise ReplayBindingViolation(field="durable_evaluation_limit_v1")
      }
      let prior_values = [
        for value in entries if value.kind == DurableOfflineEvaluationV1 &&
        value.source_refs[0] == sources[0] => value
      ]
      let prior = prior_values.last().map(value => value.primary_ref)
      if entry.previous_lineage_ref != prior ||
        entry.ordinal != prior_values.length().to_int64() + 1L {
        raise ReplayBindingViolation(field="durable_evaluation_order_v1")
      }
    }
    DurableHumanVersionDecisionV1 => {
      if sources.length() != 7 ||
        entry.previous_lineage_ref != Some(sources[0]) ||
        entry.snapshot_ref is Some(_) ||
        entry.ordinal != 0L ||
        entry.limit != 0L ||
        !(entry.state_tag == "adopted" || entry.state_tag == "rejected") {
        raise ReplayBindingViolation(field="durable_human_decision_shape_v1")
      }
      let proposal = final_learning_require_internal_source_v1(
        entries,
        sources[0],
        DurableImprovementProposalV1,
        "durable_human_proposal_v1",
      )
      let evaluation = final_learning_require_internal_source_v1(
        entries,
        sources[1],
        DurableOfflineEvaluationV1,
        "durable_human_evaluation_v1",
      )
      if evaluation.source_refs[0] != sources[0] ||
        proposal.source_refs[1] != sources[2] ||
        proposal.source_refs[2] != sources[3] ||
        entries.any(value => {
          value.kind == DurableHumanVersionDecisionV1 &&
          value.source_refs[0] == sources[0]
        }) {
        raise ReplayBindingViolation(field="durable_human_decision_lineage_v1")
      }
    }
  }
}

///|
fn require_final_learning_guard_prefix_v1(
  head_guard : @storage.WorkflowHeadGuard,
  replay : @storage.ReplayResult,
  field : String,
) -> Unit raise OrchestrationError {
  if head_guard.workflow() != replay.workflow() {
    raise ReplayBindingViolation(field~)
  }
  let prefix = replay.verified_prefix(head_guard.expected_revision()) catch {
    _ => raise ReplayBindingViolation(field~)
  }
  if prefix.head().last_event_digest() != head_guard.expected_head_digest() ||
    prefix.replay_digest() != head_guard.expected_replay_digest() {
    raise ReplayBindingViolation(field~)
  }
}

///|
fn require_final_learning_event_transport_v1(
  binding : FinalLearningStreamBindingV1,
  entry : FinalLearningDurableRecordV1,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
  source_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.workflow() != binding.stream_workflow ||
    event.event_ref().id() != entry.event_id ||
    event.sequence() != entry.expected_revision + 1L ||
    event.revision() != entry.expected_revision + 1L ||
    event.previous_event_digest() != entry.expected_head_digest ||
    event.idempotency_key() != entry.durable_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != orchestration_contract_id ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != orchestration_producer_id ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != final_learning_event_kind_v1 ||
    envelope.schema() != orchestration_schema(final_learning_event_kind_v1) ||
    envelope.subject() != entry.primary_ref ||
    envelope.run_ref() != Some(binding.stream_workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) ||
    envelope.correlation_ref() != Some(binding.stream_workflow.id()) ||
    envelope.causation_ref() != Some(entry.primary_ref.id()) ||
    envelope.idempotency_ref() != Some(entry.durable_ref.id()) ||
    envelope.previous_digest() != entry.expected_head_digest ||
    envelope.payload() != entry.canonical ||
    !same_evidence(event.evidence(), entry.evidence) ||
    !same_evidence(envelope.evidence(), entry.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="final_learning_event_transport_v1")
  }
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref()
    })
  if batches.length() != 1 ||
    batches[0].expected_revision() != entry.expected_revision ||
    batches[0].command_idempotency_key() != entry.command_idempotency_key ||
    !batches[0].intent_refs().is_empty() {
    raise ReplayBindingViolation(field="final_learning_batch_v1")
  }
  let guards = batches[0].guards()
  if entry.profile_id == final_deliverable_guard_profile_id_v1() {
    if guards.length() != 2 ||
      guards[0].workflow() != binding.source_workflow ||
      guards[1].workflow() != binding.governance_workflow {
      raise ReplayBindingViolation(
        field="final_learning_finalization_guards_v1",
      )
    }
    require_final_learning_guard_prefix_v1(
      guards[0],
      source_replay,
      "final_learning_source_guard_v1",
    )
    require_final_learning_guard_prefix_v1(
      guards[1],
      governance_replay,
      "final_learning_governance_guard_v1",
    )
  } else {
    if entry.profile_id != learning_loop_guard_profile_id_v1() ||
      guards.length() != 2 ||
      guards[0].workflow() != binding.source_workflow ||
      guards[1].workflow() != binding.governance_workflow {
      raise ReplayBindingViolation(field="final_learning_learning_guards_v1")
    }
    require_final_learning_guard_prefix_v1(
      guards[0],
      source_replay,
      "final_learning_source_guard_v1",
    )
    require_final_learning_guard_prefix_v1(
      guards[1],
      governance_replay,
      "final_learning_governance_guard_v1",
    )
  }
  let prefix = replay.verified_prefix(entry.expected_revision) catch {
    _ => raise ReplayBindingViolation(field="final_learning_prefix_v1")
  }
  if prefix.head().last_event_digest() != entry.expected_head_digest ||
    prefix.replay_digest() != entry.expected_replay_digest {
    raise ReplayBindingViolation(field="final_learning_prefix_v1")
  }
}

///|
pub fn fold_final_learning_stream_v1(
  binding : FinalLearningStreamBindingV1,
  replay : @storage.ReplayResult,
  source_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> CurrentFinalLearningProjectionV1 raise OrchestrationError {
  if replay.workflow() != binding.stream_workflow ||
    source_replay.workflow() != binding.source_workflow ||
    governance_replay.workflow() != binding.governance_workflow {
    raise WorkflowMismatch(field="final_learning_replay_roots_v1")
  }
  let entries : Array[FinalLearningDurableRecordV1] = []
  let candidates : Array[FinalLearningDurableRecordV1] = []
  let decisions : Array[FinalLearningDurableRecordV1] = []
  let artifact_revisions : Array[FinalLearningDurableRecordV1] = []
  let deliveries : Array[FinalLearningDurableRecordV1] = []
  let observations : Array[FinalLearningDurableRecordV1] = []
  let assessments : Array[FinalLearningDurableRecordV1] = []
  let proposals : Array[FinalLearningDurableRecordV1] = []
  let evaluations : Array[FinalLearningDurableRecordV1] = []
  let human_decisions : Array[FinalLearningDurableRecordV1] = []
  let latest_evaluation_ledger_refs : Array[@contracts.RecordRef] = []
  let mut latest_outcome_history_ref : @contracts.RecordRef? = None
  for event in replay.events() {
    if event.payload().envelope_kind() != final_learning_event_kind_v1 {
      raise ReplayBindingViolation(field="final_learning_foreign_event_v1")
    }
    let entry = decode_final_learning_durable_record_v1(
      binding,
      event.payload().payload(),
    )
    require_final_learning_event_transport_v1(
      binding, entry, event, replay, source_replay, governance_replay,
    )
    validate_final_learning_transition_v1(entries, entry)
    entries.push(entry)
    match entry.kind {
      DurableDeliverableCandidateV1 => candidates.push(entry)
      DurableDeliverableDecisionV1 => decisions.push(entry)
      DurableArtifactRevisionV1 => artifact_revisions.push(entry)
      DurableDeliveryReceiptV1 => deliveries.push(entry)
      DurableOutcomeObservationV1 => {
        observations.push(entry)
        latest_outcome_history_ref = entry.snapshot_ref
      }
      DurableGapAssessmentV1 => assessments.push(entry)
      DurableImprovementProposalV1 => proposals.push(entry)
      DurableOfflineEvaluationV1 => {
        evaluations.push(entry)
        guard entry.snapshot_ref is Some(snapshot) else {
          raise ReplayBindingViolation(
            field="final_learning_evaluation_snapshot_v1",
          )
        }
        latest_evaluation_ledger_refs.push(snapshot)
      }
      DurableHumanVersionDecisionV1 => human_decisions.push(entry)
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CURRENT-FINAL-LEARNING-PROJECTION-V1/1.0.0")
  write_ref(writer, binding.binding_ref)
  writer.string(binding.digest.text())
  writer.string(replay.replay_digest().text())
  writer.count(entries.length())
  for entry in entries {
    write_ref(writer, entry.durable_ref)
    writer.string(entry.digest.text())
  }
  let state_digest = @contracts.sha256_digest(writer.finish())
  {
    binding,
    replay,
    entries: ReadOnlyArray::from_array(entries),
    candidates: ReadOnlyArray::from_array(candidates),
    decisions: ReadOnlyArray::from_array(decisions),
    artifact_revisions: ReadOnlyArray::from_array(artifact_revisions),
    deliveries: ReadOnlyArray::from_array(deliveries),
    observations: ReadOnlyArray::from_array(observations),
    assessments: ReadOnlyArray::from_array(assessments),
    proposals: ReadOnlyArray::from_array(proposals),
    evaluations: ReadOnlyArray::from_array(evaluations),
    human_decisions: ReadOnlyArray::from_array(human_decisions),
    latest_outcome_history_ref,
    latest_evaluation_ledger_refs: ReadOnlyArray::from_array(
      latest_evaluation_ledger_refs,
    ),
    state_digest,
  }
}

///|
pub fn CurrentFinalLearningProjectionV1::entries(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.entries
}

///|
pub fn CurrentFinalLearningProjectionV1::candidates(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.candidates
}

///|
pub fn CurrentFinalLearningProjectionV1::decisions(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.decisions
}

///|
pub fn CurrentFinalLearningProjectionV1::artifact_revisions(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.artifact_revisions
}

///|
pub fn CurrentFinalLearningProjectionV1::deliveries(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.deliveries
}

///|
pub fn CurrentFinalLearningProjectionV1::observations(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.observations
}

///|
pub fn CurrentFinalLearningProjectionV1::assessments(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.assessments
}

///|
pub fn CurrentFinalLearningProjectionV1::proposals(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.proposals
}

///|
pub fn CurrentFinalLearningProjectionV1::evaluations(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.evaluations
}

///|
pub fn CurrentFinalLearningProjectionV1::human_decisions(
  self : CurrentFinalLearningProjectionV1,
) -> ReadOnlyArray[FinalLearningDurableRecordV1] {
  self.human_decisions
}

///|
pub fn CurrentFinalLearningProjectionV1::latest_outcome_history_ref(
  self : CurrentFinalLearningProjectionV1,
) -> @contracts.RecordRef? {
  self.latest_outcome_history_ref
}

///|
pub fn CurrentFinalLearningProjectionV1::state_digest(
  self : CurrentFinalLearningProjectionV1,
) -> @contracts.ContentDigest {
  self.state_digest
}
