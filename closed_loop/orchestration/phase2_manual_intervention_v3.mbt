///|
let manual_intervention_hold_event_kind_v3 = "effect.recovery.manual-hold.v3"

///|
let manual_intervention_resume_event_kind_v3 = "effect.recovery.manual-resume.v3"

///|
let manual_intervention_authority_magic_v3 = b"FLOW7/MANUAL-INTERVENTION-AUTHORITY-V3/3.0.0"

///|
let manual_intervention_record_magic_v3 = b"FLOW7/MANUAL-INTERVENTION-RECORD-V3/3.0.0"

///|
fn bytes_have_manual_intervention_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == manual_intervention_record_magic_v3
  }
}

///|
pub(all) enum ManualInterventionAuthorityScopeV3 {
  ManualInterventionHoldAuthorityV3
  ManualInterventionResumeAuthorityV3
} derive(Eq, Debug)

///|
fn ManualInterventionAuthorityScopeV3::wire(
  self : ManualInterventionAuthorityScopeV3,
) -> String {
  match self {
    ManualInterventionHoldAuthorityV3 => "manual_intervention.hold.v3"
    ManualInterventionResumeAuthorityV3 => "manual_intervention.resume.v3"
  }
}

///|
fn manual_intervention_authority_scope_from_wire_v3(
  value : String,
) -> ManualInterventionAuthorityScopeV3 raise OrchestrationError {
  match value {
    "manual_intervention.hold.v3" => ManualInterventionHoldAuthorityV3
    "manual_intervention.resume.v3" => ManualInterventionResumeAuthorityV3
    _ => raise MalformedInput(field="manual_intervention_authority_scope_v3")
  }
}

///|
/// A generic operator authority artifact. MoonFlow binds its exact signed bytes
/// and scope but deliberately does not interpret organization-specific roles.
pub struct ManualInterventionAuthorityV3 {
  operator_ref : @contracts.RecordRef
  authority_ref : @contracts.RecordRef
  authority_bytes : Bytes
  scope : ManualInterventionAuthorityScopeV3
  issued_at : Int64
  expires_at : Int64?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn ManualInterventionAuthorityV3::new(
  operator_ref : @contracts.RecordRef,
  authority_ref : @contracts.RecordRef,
  authority_bytes : Bytes,
  scope : ManualInterventionAuthorityScopeV3,
  issued_at : Int64,
  expires_at : Int64?,
) -> ManualInterventionAuthorityV3 raise OrchestrationError {
  if authority_bytes.is_empty() ||
    @contracts.sha256_digest(authority_bytes) != authority_ref.digest() ||
    issued_at < 0L {
    raise ReplayBindingViolation(field="manual_intervention_authority_v3")
  }
  match expires_at {
    Some(value) if value <= issued_at =>
      raise MalformedInput(field="manual_intervention_authority_expiry_v3")
    _ => ()
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(manual_intervention_authority_magic_v3)
  writer.string("3.0.0")
  write_ref(writer, operator_ref)
  write_ref(writer, authority_ref)
  writer.bytes(authority_bytes)
  writer.string(scope.wire())
  writer.int64(issued_at)
  writer.optional_int64(expires_at)
  let canonical = writer.finish()
  {
    operator_ref,
    authority_ref,
    authority_bytes,
    scope,
    issued_at,
    expires_at,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
fn decode_manual_intervention_authority_v3(
  bytes : Bytes,
) -> ManualInterventionAuthorityV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != manual_intervention_authority_magic_v3 {
    raise MalformedInput(field="manual_intervention_authority_magic_v3")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="manual_intervention_authority_v3", version~)
  }
  let value = ManualInterventionAuthorityV3::new(
    reader.read_ref(),
    reader.read_ref(),
    reader.read_bytes(),
    manual_intervention_authority_scope_from_wire_v3(reader.read_string()),
    reader.read_int64(),
    reader.read_optional_int64(),
  )
  reader.require_end()
  if value.canonical != bytes {
    raise ReplayBindingViolation(
      field="manual_intervention_authority_canonical_v3",
    )
  }
  value
}

///|
pub fn ManualInterventionAuthorityV3::operator_ref(
  self : ManualInterventionAuthorityV3,
) -> @contracts.RecordRef {
  self.operator_ref
}

///|
pub fn ManualInterventionAuthorityV3::authority_ref(
  self : ManualInterventionAuthorityV3,
) -> @contracts.RecordRef {
  self.authority_ref
}

///|
pub fn ManualInterventionAuthorityV3::scope(
  self : ManualInterventionAuthorityV3,
) -> ManualInterventionAuthorityScopeV3 {
  self.scope
}

///|
pub fn ManualInterventionAuthorityV3::canonical_bytes(
  self : ManualInterventionAuthorityV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ManualInterventionAuthorityV3::digest(
  self : ManualInterventionAuthorityV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum ManualInterventionActionV3 {
  ManualInterventionHeldV3
  ManualInterventionResumedV3
} derive(Eq, Debug)

///|
fn ManualInterventionActionV3::wire(
  self : ManualInterventionActionV3,
) -> String {
  match self {
    ManualInterventionHeldV3 => "held_v3"
    ManualInterventionResumedV3 => "resumed_v3"
  }
}

///|
fn manual_intervention_action_from_wire_v3(
  value : String,
) -> ManualInterventionActionV3 raise OrchestrationError {
  match value {
    "held_v3" => ManualInterventionHeldV3
    "resumed_v3" => ManualInterventionResumedV3
    _ => raise MalformedInput(field="manual_intervention_action_v3")
  }
}

///|
pub struct ManualInterventionRecordV3 {
  record_ref : @contracts.RecordRef
  action_id : String
  action : ManualInterventionActionV3
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  authority : ManualInterventionAuthorityV3
  reason : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  authored_at : Int64
  prior_hold_ref : @contracts.RecordRef?
  prior_hold_digest : @contracts.ContentDigest?
  prior_hold_bytes : Bytes?
  expected_work_revision : Int64
  expected_work_head_digest : @contracts.ContentDigest
  expected_work_replay_digest : @contracts.ContentDigest
  governance_workflow : @contracts.RecordRef
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  governance_replay_digest : @contracts.ContentDigest
  evidence_head : RecoveryEvidenceHeadV3
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn build_manual_intervention_record_v3(
  action_id : String,
  action : ManualInterventionActionV3,
  workflow : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  authority : ManualInterventionAuthorityV3,
  reason : String,
  evidence : Array[@contracts.EvidenceRef],
  authored_at : Int64,
  prior_hold : ManualInterventionRecordV3?,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
  governance_workflow : @contracts.RecordRef,
  governance_revision : Int64,
  governance_head_digest : @contracts.ContentDigest?,
  governance_replay_digest : @contracts.ContentDigest,
  evidence_head : RecoveryEvidenceHeadV3,
) -> ManualInterventionRecordV3 raise OrchestrationError {
  require_text(action_id, "manual_intervention_action_id_v3")
  require_text(reason, "manual_intervention_reason_v3")
  if evidence.is_empty() ||
    authored_at < 0L ||
    expected_work_revision < 0L ||
    governance_revision < 0L ||
    evidence_head.bound_workflow != workflow ||
    evidence_head.evidence_workflow == governance_workflow {
    raise MalformedInput(field="manual_intervention_bounds_v3")
  }
  match authority.expires_at {
    Some(value) if authored_at >= value =>
      raise RecoveryViolation(field="manual_intervention_authority_expired_v3")
    _ => ()
  }
  if authored_at < authority.issued_at ||
    (
      action == ManualInterventionHeldV3 &&
      authority.scope != ManualInterventionHoldAuthorityV3
    ) ||
    (
      action == ManualInterventionResumedV3 &&
      authority.scope != ManualInterventionResumeAuthorityV3
    ) {
    raise RecoveryViolation(field="manual_intervention_authority_scope_v3")
  }
  match (action, prior_hold) {
    (ManualInterventionHeldV3, None) => ()
    (ManualInterventionResumedV3, Some(value)) =>
      if value.action != ManualInterventionHeldV3 ||
        value.workflow != workflow ||
        value.intent_ref != intent_ref {
        raise ReplayBindingViolation(field="manual_intervention_prior_hold_v3")
      }
    _ => raise RecoveryViolation(field="manual_intervention_prior_hold_v3")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(manual_intervention_record_magic_v3)
  writer.string("3.0.0")
  writer.string(action_id)
  writer.string(action.wire())
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, governed_subject)
  writer.bytes(authority.canonical)
  writer.string(reason)
  write_evidence(writer, evidence)
  writer.int64(authored_at)
  match prior_hold {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value.record_ref)
      writer.string(value.digest.text())
      writer.bytes(value.canonical)
    }
  }
  writer.int64(expected_work_revision)
  writer.string(expected_work_head_digest.text())
  writer.string(expected_work_replay_digest.text())
  write_ref(writer, governance_workflow)
  writer.int64(governance_revision)
  writer.optional_digest(governance_head_digest)
  writer.string(governance_replay_digest.text())
  writer.bytes(evidence_head.canonical)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v3(
      "orchestration-manual-intervention-v3", action_id, digest,
    ),
    action_id,
    action,
    workflow,
    intent_ref,
    governed_subject,
    authority,
    reason,
    evidence: ReadOnlyArray::from_array(evidence),
    authored_at,
    prior_hold_ref: prior_hold.map(value => value.record_ref),
    prior_hold_digest: prior_hold.map(value => value.digest),
    prior_hold_bytes: prior_hold.map(value => value.canonical),
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    governance_workflow,
    governance_revision,
    governance_head_digest,
    governance_replay_digest,
    evidence_head,
    canonical,
    digest,
  }
}

///|
fn decode_manual_intervention_record_v3(
  bytes : Bytes,
) -> ManualInterventionRecordV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != manual_intervention_record_magic_v3 {
    raise MalformedInput(field="manual_intervention_record_magic_v3")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="manual_intervention_record_v3", version~)
  }
  let action_id = reader.read_string()
  let action = manual_intervention_action_from_wire_v3(reader.read_string())
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let authority = decode_manual_intervention_authority_v3(reader.read_bytes())
  let reason = reader.read_string()
  let evidence = reader.read_evidence()
  let authored_at = reader.read_int64()
  let prior_hold = match reader.read_byte() {
    0 => None
    1 => {
      let expected_ref = reader.read_ref()
      let expected_digest = reader.read_digest()
      let prior_bytes = reader.read_bytes()
      let value = decode_manual_intervention_record_v3(prior_bytes)
      if value.record_ref != expected_ref || value.digest != expected_digest {
        raise ReplayBindingViolation(
          field="manual_intervention_prior_hold_bytes_v3",
        )
      }
      Some(value)
    }
    _ => raise MalformedInput(field="manual_intervention_prior_hold_tag_v3")
  }
  let value = build_manual_intervention_record_v3(
    action_id,
    action,
    workflow,
    intent_ref,
    governed_subject,
    authority,
    reason,
    evidence,
    authored_at,
    prior_hold,
    reader.read_int64(),
    reader.read_digest(),
    reader.read_digest(),
    reader.read_ref(),
    reader.read_int64(),
    reader.read_optional_digest(),
    reader.read_digest(),
    decode_recovery_evidence_head_v3(reader.read_bytes()),
  )
  reader.require_end()
  if value.canonical != bytes {
    raise ReplayBindingViolation(
      field="manual_intervention_record_canonical_v3",
    )
  }
  value
}

///|
pub fn ManualInterventionRecordV3::record_ref(
  self : ManualInterventionRecordV3,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn ManualInterventionRecordV3::action(
  self : ManualInterventionRecordV3,
) -> ManualInterventionActionV3 {
  self.action
}

///|
pub fn ManualInterventionRecordV3::intent_ref(
  self : ManualInterventionRecordV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn ManualInterventionRecordV3::workflow(
  self : ManualInterventionRecordV3,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn ManualInterventionRecordV3::governed_subject(
  self : ManualInterventionRecordV3,
) -> @contracts.RecordRef {
  self.governed_subject
}

///|
pub fn ManualInterventionRecordV3::authority(
  self : ManualInterventionRecordV3,
) -> ManualInterventionAuthorityV3 {
  self.authority
}

///|
pub fn ManualInterventionRecordV3::reason(
  self : ManualInterventionRecordV3,
) -> String {
  self.reason
}

///|
pub fn ManualInterventionRecordV3::evidence(
  self : ManualInterventionRecordV3,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn ManualInterventionRecordV3::authored_at(
  self : ManualInterventionRecordV3,
) -> Int64 {
  self.authored_at
}

///|
pub fn ManualInterventionRecordV3::prior_hold_ref(
  self : ManualInterventionRecordV3,
) -> @contracts.RecordRef? {
  self.prior_hold_ref
}

///|
pub fn ManualInterventionRecordV3::canonical_bytes(
  self : ManualInterventionRecordV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ManualInterventionRecordV3::digest(
  self : ManualInterventionRecordV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct ManualInterventionCandidateV3 {
  record : ManualInterventionRecordV3
  event : @storage.WorkflowEvent
  guarded_request : @storage.GuardedCommitRequest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn prepare_manual_intervention_candidate_v3(
  governed : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  action_id : String,
  intent_ref : @contracts.RecordRef,
  authority : ManualInterventionAuthorityV3,
  reason : String,
  evidence : Array[@contracts.EvidenceRef],
  authored_at : Int64,
  prior_hold : ManualInterventionRecordV3?,
) -> ManualInterventionCandidateV3 raise OrchestrationError {
  if governed.current.work.work_terminal is Some(_) ||
    evidence_projection.bound_workflow() !=
    governed.current.root_binding.workflow ||
    evidence_projection.bound_work_replay_digest() !=
    governed.work_replay.replay_digest() ||
    !governed.v3_owned_intent_refs().any(value => value == intent_ref) {
    raise RecoveryViolation(field="manual_intervention_current_v3")
  }
  // A legacy strict dispatch target intentionally disappears after create.
  // Manual intervention, however, is primarily needed after that boundary.
  // Derive the immutable subject from the durable claim when one exists and
  // fall back to the dispatch target only for an unclaimed scheduled retry.
  let governed_subject = match governed.current_claim(intent_ref) {
    Some(claim) => claim.governed_subject
    None => governed.dispatch_source_target_v3(intent_ref).governed_subject
  }
  let evidence_head = evidence_projection.recovery_evidence_head_v3()
  let action = match prior_hold {
    None => ManualInterventionHeldV3
    Some(_) => ManualInterventionResumedV3
  }
  let record = build_manual_intervention_record_v3(
    action_id,
    action,
    governed.current.root_binding.workflow,
    intent_ref,
    governed_subject,
    authority,
    reason,
    evidence,
    authored_at,
    prior_hold,
    governed.current.work_revision,
    governed.current.work_head_digest,
    governed.current.work_replay_digest,
    governed.governance_replay.workflow(),
    governed.current.governance_revision,
    governed.current.governance_head_digest,
    governed.current.governance_replay_digest,
    evidence_head,
  )
  let kind = match action {
    ManualInterventionHeldV3 => manual_intervention_hold_event_kind_v3
    ManualInterventionResumedV3 => manual_intervention_resume_event_kind_v3
  }
  let event_key = "manual-intervention-event:\{record.digest.text()}"
  let command_key = "manual-intervention-command:\{record.digest.text()}"
  let event = prepare_phase1b_work_event_v22(
    record.workflow,
    governed.current.work_sequence + 1L,
    governed.current.work_revision + 1L,
    governed.current.work_head_digest,
    record.record_ref.id(),
    kind,
    record.record_ref,
    record.canonical,
    record.governed_subject,
    evidence,
    authority.authority_ref,
    event_key,
  )
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    record.workflow,
    governed.current.work_revision,
    command_key,
    [event],
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="manual_intervention_batch_v3")
  }
  let guarded = @storage.GuardedCommitRequest::new(request, [
    @storage.WorkflowHeadGuard::new(
      record.governance_workflow,
      record.governance_revision,
      record.governance_head_digest,
      record.governance_replay_digest,
    ),
    @storage.WorkflowHeadGuard::new(
      evidence_head.evidence_workflow,
      evidence_head.revision,
      evidence_head.head_digest,
      evidence_head.replay_digest,
    ),
  ]) catch {
    _ => raise ReplayBindingViolation(field="manual_intervention_guards_v3")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/MANUAL-INTERVENTION-CANDIDATE-V3/3.0.0")
  writer.string("3.0.0")
  writer.bytes(record.canonical)
  writer.bytes(guarded.canonical_bytes())
  let canonical = writer.finish()
  {
    record,
    event,
    guarded_request: guarded,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn prepare_manual_intervention_hold_v3(
  governed : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  action_id : String,
  intent_ref : @contracts.RecordRef,
  authority : ManualInterventionAuthorityV3,
  reason : String,
  evidence : Array[@contracts.EvidenceRef],
  authored_at : Int64,
) -> ManualInterventionCandidateV3 raise OrchestrationError {
  let projection = fold_manual_intervention_v3(governed.work_replay)
  if projection.active_hold(intent_ref) is Some(_) {
    raise RecoveryViolation(field="manual_intervention_already_held_v3")
  }
  prepare_manual_intervention_candidate_v3(
    governed,
    evidence_projection,
    action_id,
    intent_ref,
    authority,
    reason,
    evidence,
    authored_at,
    None,
  )
}

///|
pub fn prepare_manual_intervention_resume_v3(
  governed : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  action_id : String,
  intent_ref : @contracts.RecordRef,
  authority : ManualInterventionAuthorityV3,
  reason : String,
  evidence : Array[@contracts.EvidenceRef],
  authored_at : Int64,
) -> ManualInterventionCandidateV3 raise OrchestrationError {
  let projection = fold_manual_intervention_v3(governed.work_replay)
  guard projection.active_hold(intent_ref) is Some(hold) else {
    raise RecoveryViolation(field="manual_intervention_not_held_v3")
  }
  prepare_manual_intervention_candidate_v3(
    governed,
    evidence_projection,
    action_id,
    intent_ref,
    authority,
    reason,
    evidence,
    authored_at,
    Some(hold),
  )
}

///|
pub(all) enum ManualInterventionCommitResultV3 {
  ManualInterventionFreshV3
  ManualInterventionAlreadyCommittedV3
  ManualInterventionRaceLostV3
  ManualInterventionGuardStaleV3
} derive(Eq, Debug)

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_manual_intervention_v3(
  store : S,
  candidate : ManualInterventionCandidateV3,
) -> ManualInterventionCommitResultV3 raise {
  require_phase2_recovery_evidence_guard_profile_v3(
    store,
    candidate.guarded_request,
  )
  try {
    match store.classified_guarded_commit(candidate.guarded_request) {
      @storage.FreshlyApplied(_) => ManualInterventionFreshV3
      @storage.AlreadyCommitted(_) => ManualInterventionAlreadyCommittedV3
      @storage.GuardRejected(_) => ManualInterventionGuardStaleV3
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) => ManualInterventionRaceLostV3
    error => raise error
  }
}

///|
pub fn ManualInterventionCandidateV3::record(
  self : ManualInterventionCandidateV3,
) -> ManualInterventionRecordV3 {
  self.record
}

///|
pub fn ManualInterventionCandidateV3::canonical_bytes(
  self : ManualInterventionCandidateV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ManualInterventionCandidateV3::digest(
  self : ManualInterventionCandidateV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct CurrentManualInterventionProjectionV3 {
  workflow : @contracts.RecordRef
  replay : @storage.ReplayResult
  entries : ReadOnlyArray[ManualInterventionRecordV3]
  active_holds : ReadOnlyArray[ManualInterventionRecordV3]
  state_digest : @contracts.ContentDigest
}

///|
fn require_manual_intervention_event_v3(
  record : ManualInterventionRecordV3,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let expected_kind = match record.action {
    ManualInterventionHeldV3 => manual_intervention_hold_event_kind_v3
    ManualInterventionResumedV3 => manual_intervention_resume_event_kind_v3
  }
  let expected_event_key = "manual-intervention-event:\{record.digest.text()}"
  let expected_command_key = "manual-intervention-command:\{record.digest.text()}"
  let envelope = event.payload()
  if event.workflow() != record.workflow ||
    event.event_ref() != record.record_ref ||
    event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.sequence() != event.revision() ||
    event.revision() != record.expected_work_revision + 1L ||
    event.previous_event_digest() != Some(record.expected_work_head_digest) ||
    event.idempotency_key() != expected_event_key ||
    envelope.envelope_id() != record.record_ref.id() ||
    envelope.contract_id() != orchestration_contract_id ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != orchestration_producer_id ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != expected_kind ||
    envelope.schema() != orchestration_schema(expected_kind) ||
    envelope.subject() != record.record_ref ||
    envelope.payload() != record.canonical ||
    envelope.run_ref() != Some(record.workflow) ||
    envelope.correlation_ref() != Some(record.workflow.id()) ||
    envelope.causation_ref() != Some(record.authority.authority_ref.id()) ||
    envelope.idempotency_ref() != Some(expected_event_key) ||
    envelope.previous_digest() != Some(record.expected_work_head_digest) ||
    !same_evidence(event.evidence(), record.evidence) ||
    !same_evidence(envelope.evidence(), record.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="manual_intervention_transport_v3")
  }
  let prefix = verified_prefix_v3(
    replay,
    record.expected_work_revision,
    "manual_intervention_work_prefix_v3",
  )
  if prefix.head().last_event_digest() != Some(record.expected_work_head_digest) ||
    prefix.replay_digest() != record.expected_work_replay_digest {
    raise ReplayBindingViolation(field="manual_intervention_work_head_v3")
  }
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref() &&
      batch.intent_refs().is_empty()
    })
  if batches.length() != 1 ||
    batches[0].expected_revision() != record.expected_work_revision ||
    batches[0].command_idempotency_key() != expected_command_key ||
    batches[0].guards().length() != 2 {
    raise ReplayBindingViolation(field="manual_intervention_transaction_v3")
  }
  let governance_guard = batches[0].guards()[0]
  let evidence_guard = batches[0].guards()[1]
  if governance_guard.workflow() != record.governance_workflow ||
    governance_guard.expected_revision() != record.governance_revision ||
    governance_guard.expected_head_digest() != record.governance_head_digest ||
    governance_guard.expected_replay_digest() != record.governance_replay_digest ||
    evidence_guard.workflow() != record.evidence_head.evidence_workflow ||
    evidence_guard.expected_revision() != record.evidence_head.revision ||
    evidence_guard.expected_head_digest() != record.evidence_head.head_digest ||
    evidence_guard.expected_replay_digest() !=
    record.evidence_head.replay_digest {
    raise ReplayBindingViolation(field="manual_intervention_guard_binding_v3")
  }
}

///|
pub fn fold_manual_intervention_v3(
  replay : @storage.ReplayResult,
) -> CurrentManualInterventionProjectionV3 raise OrchestrationError {
  let entries : Array[ManualInterventionRecordV3] = []
  let active : Array[ManualInterventionRecordV3] = []
  for event in replay.events() {
    let kind = event.payload().envelope_kind()
    if kind == manual_intervention_hold_event_kind_v3 ||
      kind == manual_intervention_resume_event_kind_v3 {
      let record = decode_manual_intervention_record_v3(
        event.payload().payload(),
      )
      require_manual_intervention_event_v3(record, event, replay)
      match record.action {
        ManualInterventionHeldV3 => {
          if active.any(value => value.intent_ref == record.intent_ref) {
            raise RecoveryViolation(
              field="manual_intervention_duplicate_hold_v3",
            )
          }
          active.push(record)
        }
        ManualInterventionResumedV3 => {
          guard first(active, value => value.intent_ref == record.intent_ref)
            is Some(hold) else {
            raise RecoveryViolation(
              field="manual_intervention_resume_without_hold_v3",
            )
          }
          if record.prior_hold_ref != Some(hold.record_ref) ||
            record.prior_hold_digest != Some(hold.digest) ||
            record.prior_hold_bytes != Some(hold.canonical) {
            raise ReplayBindingViolation(
              field="manual_intervention_resume_binding_v3",
            )
          }
          let retained = active.filter(value => {
            value.intent_ref != record.intent_ref
          })
          active.clear()
          for value in retained {
            active.push(value)
          }
        }
      }
      entries.push(record)
    } else if bytes_have_manual_intervention_magic_v3(event.payload().payload()) {
      raise ReplayBindingViolation(
        field="manual_intervention_unknown_wrapper_v3",
      )
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CURRENT-MANUAL-INTERVENTION-PROJECTION-V3/3.0.0")
  writer.string("3.0.0")
  write_ref(writer, replay.workflow())
  writer.string(replay.replay_digest().text())
  writer.count(entries.length())
  for value in entries {
    writer.bytes(value.canonical)
  }
  writer.count(active.length())
  for value in active {
    writer.bytes(value.canonical)
  }
  {
    workflow: replay.workflow(),
    replay,
    entries: ReadOnlyArray::from_array(entries),
    active_holds: ReadOnlyArray::from_array(active),
    state_digest: @contracts.sha256_digest(writer.finish()),
  }
}

///|
pub fn CurrentManualInterventionProjectionV3::entries(
  self : CurrentManualInterventionProjectionV3,
) -> ReadOnlyArray[ManualInterventionRecordV3] {
  self.entries
}

///|
pub fn CurrentManualInterventionProjectionV3::active_holds(
  self : CurrentManualInterventionProjectionV3,
) -> ReadOnlyArray[ManualInterventionRecordV3] {
  self.active_holds
}

///|
pub fn CurrentManualInterventionProjectionV3::active_hold(
  self : CurrentManualInterventionProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> ManualInterventionRecordV3? {
  first(self.active_holds, value => value.intent_ref == intent_ref)
}

///|
pub fn CurrentManualInterventionProjectionV3::state_digest(
  self : CurrentManualInterventionProjectionV3,
) -> @contracts.ContentDigest {
  self.state_digest
}

///|
/// Operator holds override the displayed recovery state without changing or
/// erasing the independently derived provider/reconciliation state.
pub fn CurrentGovernedRecoveryProjectionV3::state_for_with_manual_intervention_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  recovery_evidence : CurrentRecoveryEvidenceProjectionV3,
  manual : CurrentManualInterventionProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> @effects.EffectRecoveryStateV3 raise OrchestrationError {
  if manual.workflow != self.current.root_binding.workflow ||
    manual.replay.replay_digest() != self.work_replay.replay_digest() {
    raise ReplayBindingViolation(
      field="manual_intervention_projection_current_v3",
    )
  }
  match manual.active_hold(intent_ref) {
    Some(_) => @effects.RecoveryManualInterventionV3
    None =>
      self.state_for_with_recovery_evidence_v3(recovery_evidence, intent_ref)
  }
}

///|
pub fn validate_manual_intervention_external_heads_v3(
  projection : CurrentManualInterventionProjectionV3,
  governance_replay : @storage.ReplayResult,
  evidence_binding : RecoveryEvidenceStreamBindingV3,
  evidence_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  for record in projection.entries {
    let governance_prefix = verified_prefix_v3(
      governance_replay,
      record.governance_revision,
      "manual_intervention_governance_prefix_v3",
    )
    let evidence_prefix = verified_prefix_v3(
      evidence_replay,
      record.evidence_head.revision,
      "manual_intervention_evidence_prefix_v3",
    )
    let work_prefix = verified_prefix_v3(
      projection.replay,
      record.expected_work_revision,
      "manual_intervention_bound_work_prefix_v3",
    )
    if governance_prefix.workflow() != record.governance_workflow ||
      governance_prefix.head().last_event_digest() !=
      record.governance_head_digest ||
      governance_prefix.replay_digest() != record.governance_replay_digest ||
      evidence_prefix.workflow() != record.evidence_head.evidence_workflow ||
      evidence_prefix.head().last_event_digest() !=
      record.evidence_head.head_digest ||
      evidence_prefix.replay_digest() != record.evidence_head.replay_digest {
      raise ReplayBindingViolation(
        field="manual_intervention_external_heads_v3",
      )
    }
    let evidence_projection = fold_recovery_evidence_stream_v3(
      evidence_binding, evidence_prefix, work_prefix,
    )
    if evidence_projection.state_digest() != record.evidence_head.state_digest {
      raise ReplayBindingViolation(
        field="manual_intervention_evidence_state_v3",
      )
    }
  }
}

///|
fn require_no_active_manual_intervention_v3(
  projection : CurrentManualInterventionProjectionV3,
  intent_refs : ArrayView[@contracts.RecordRef],
) -> Unit raise OrchestrationError {
  if projection.active_holds.any(hold => {
      intent_refs.any(intent_ref => intent_ref == hold.intent_ref)
    }) {
    raise RecoveryViolation(field="manual_intervention_blocks_terminal_v3")
  }
}

///|
fn manual_intervention_event_consumption_v3(
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Int raise OrchestrationError {
  let kind = event.payload().envelope_kind()
  if kind != manual_intervention_hold_event_kind_v3 &&
    kind != manual_intervention_resume_event_kind_v3 {
    return 0
  }
  let record = decode_manual_intervention_record_v3(event.payload().payload())
  require_manual_intervention_event_v3(record, event, replay)
  1
}

///|
fn manual_intervention_fact_allowed_after_pending_cancellation_v3(
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Bool raise OrchestrationError {
  manual_intervention_event_consumption_v3(event, replay) == 1
}
