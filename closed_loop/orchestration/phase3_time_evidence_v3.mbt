///|
let time_observed_event_kind_v3 = "orchestration.time.observed.v3"

///|
let time_observation_magic_v3 = b"FLOW7/TIME-OBSERVATION-V3/3.0.0"

///|
fn phase3_time_schema_v3(
  kind : String,
) -> @contracts.SchemaRef raise OrchestrationError {
  @contracts.SchemaRef::new(
    "closed-loop.orchestration",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("closed-loop.orchestration/{kind}/3")).text(),
  ) catch {
    _ => raise MalformedInput(field="phase3_time_schema_v3")
  }
}

///|
pub(all) enum ClockJumpKindV3 {
  InitialClockObservationV3
  ClockAdvancedV3
  ClockUnchangedV3
  BackwardClockJumpClampedV3
} derive(Eq, Debug)

///|
fn ClockJumpKindV3::wire(self : ClockJumpKindV3) -> String {
  match self {
    InitialClockObservationV3 => "initial"
    ClockAdvancedV3 => "advanced"
    ClockUnchangedV3 => "unchanged"
    BackwardClockJumpClampedV3 => "backward-clamped"
  }
}

///|
fn decode_clock_jump_kind_v3(
  value : String,
) -> ClockJumpKindV3 raise OrchestrationError {
  match value {
    "initial" => InitialClockObservationV3
    "advanced" => ClockAdvancedV3
    "unchanged" => ClockUnchangedV3
    "backward-clamped" => BackwardClockJumpClampedV3
    _ => raise MalformedInput(field="time_observation_v3_jump_kind")
  }
}

///|
/// One append-only time fact. `source_instant` preserves the external clock
/// reading while `effective_instant` is a replay-derived monotonic value. A
/// backward clock jump is retained and classified instead of being discarded.
pub struct TimeObservationV3 {
  observation_ref : @contracts.RecordRef
  time_workflow : @contracts.RecordRef
  source_ref : @contracts.RecordRef
  source_timezone_id : String
  resolved_boundary_ref : @contracts.RecordRef?
  resolved_boundary_digest : @contracts.ContentDigest?
  source_instant : UtcInstantV3
  effective_instant : UtcInstantV3
  jump_kind : ClockJumpKindV3
  observation_ordinal : Int64
  previous_observation_ref : @contracts.RecordRef?
  previous_observation_digest : @contracts.ContentDigest?
  event_id : String
  command_idempotency_key : String
  expected_time_revision : Int64
  expected_time_head_digest : @contracts.ContentDigest?
  expected_time_replay_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn time_observation_signing_bytes_v3(
  observation_id : String,
  time_workflow : @contracts.RecordRef,
  source_ref : @contracts.RecordRef,
  source_timezone_id : String,
  resolved_boundary_ref : @contracts.RecordRef?,
  resolved_boundary_digest : @contracts.ContentDigest?,
  source_instant : UtcInstantV3,
  effective_instant : UtcInstantV3,
  jump_kind : ClockJumpKindV3,
  observation_ordinal : Int64,
  previous_observation_ref : @contracts.RecordRef?,
  previous_observation_digest : @contracts.ContentDigest?,
  event_id : String,
  command_idempotency_key : String,
  expected_time_revision : Int64,
  expected_time_head_digest : @contracts.ContentDigest?,
  expected_time_replay_digest : @contracts.ContentDigest,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(time_observation_magic_v3)
  writer.string("3.0.0")
  writer.string(observation_id)
  write_ref(writer, time_workflow)
  write_ref(writer, source_ref)
  writer.string(source_timezone_id)
  match resolved_boundary_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
      guard resolved_boundary_digest is Some(digest) else {
        raise ReplayBindingViolation(
          field="time_observation_v3_boundary_digest",
        )
      }
      writer.string(digest.text())
    }
  }
  if resolved_boundary_ref is None && resolved_boundary_digest is Some(_) {
    raise ReplayBindingViolation(field="time_observation_v3_boundary_ref")
  }
  writer.bytes(source_instant.canonical)
  writer.bytes(effective_instant.canonical)
  writer.string(jump_kind.wire())
  writer.int64(observation_ordinal)
  match previous_observation_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
      guard previous_observation_digest is Some(digest) else {
        raise ReplayBindingViolation(
          field="time_observation_v3_previous_digest",
        )
      }
      writer.string(digest.text())
    }
  }
  if previous_observation_ref is None && previous_observation_digest is Some(_) {
    raise ReplayBindingViolation(field="time_observation_v3_previous_ref")
  }
  writer.string(event_id)
  writer.string(command_idempotency_key)
  writer.int64(expected_time_revision)
  writer.optional_digest(expected_time_head_digest)
  writer.string(expected_time_replay_digest.text())
  write_evidence(writer, evidence)
  writer.finish()
}

///|
fn make_time_observation_v3(
  replay : @storage.ReplayResult,
  previous : TimeObservationV3?,
  observation_id : String,
  source_ref : @contracts.RecordRef,
  source_timezone_id : String,
  resolved_boundary : ResolvedCivilTimeV3?,
  source_instant : UtcInstantV3,
  event_id : String,
  command_idempotency_key : String,
  evidence : Array[@contracts.EvidenceRef],
) -> TimeObservationV3 raise OrchestrationError {
  require_text(observation_id, "time_observation_v3_id")
  require_text(source_timezone_id, "time_observation_v3_timezone_id")
  require_text(event_id, "time_observation_v3_event_id")
  require_text(command_idempotency_key, "time_observation_v3_command")
  if evidence.is_empty() {
    raise EvidenceMismatch(field="time_observation_v3_evidence")
  }
  match resolved_boundary {
    Some(value) if value.timezone_id != source_timezone_id ||
      value.instant != source_instant =>
      raise ReplayBindingViolation(field="time_observation_v3_civil_boundary")
    _ => ()
  }
  let (effective_millis, jump_kind, observation_ordinal) = match previous {
    None => (source_instant.epoch_millis, InitialClockObservationV3, 1L)
    Some(value) => {
      if value.observation_ordinal == int64_max {
        raise ArithmeticOverflow(field="time_observation_v3_ordinal")
      }
      let jump_kind = if source_instant.epoch_millis <
        value.source_instant.epoch_millis {
        BackwardClockJumpClampedV3
      } else if source_instant.epoch_millis == value.source_instant.epoch_millis {
        ClockUnchangedV3
      } else {
        ClockAdvancedV3
      }
      let effective = if source_instant.epoch_millis <
        value.effective_instant.epoch_millis {
        value.effective_instant.epoch_millis
      } else {
        source_instant.epoch_millis
      }
      (effective, jump_kind, value.observation_ordinal + 1L)
    }
  }
  let effective_instant = UtcInstantV3::new(effective_millis)
  let boundary_ref = resolved_boundary.map(value => value.resolution_ref)
  let boundary_digest = resolved_boundary.map(value => value.digest)
  let previous_ref = previous.map(value => value.observation_ref)
  let previous_digest = previous.map(value => value.digest)
  let head = replay.head()
  let canonical = time_observation_signing_bytes_v3(
    observation_id,
    replay.workflow(),
    source_ref,
    source_timezone_id,
    boundary_ref,
    boundary_digest,
    source_instant,
    effective_instant,
    jump_kind,
    observation_ordinal,
    previous_ref,
    previous_digest,
    event_id,
    command_idempotency_key,
    head.revision(),
    head.last_event_digest(),
    replay.replay_digest(),
    evidence,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    observation_ref: self_ref_v3(
      "orchestration-time-observation-v3", observation_id, digest,
    ),
    time_workflow: replay.workflow(),
    source_ref,
    source_timezone_id,
    resolved_boundary_ref: boundary_ref,
    resolved_boundary_digest: boundary_digest,
    source_instant,
    effective_instant,
    jump_kind,
    observation_ordinal,
    previous_observation_ref: previous_ref,
    previous_observation_digest: previous_digest,
    event_id,
    command_idempotency_key,
    expected_time_revision: head.revision(),
    expected_time_head_digest: head.last_event_digest(),
    expected_time_replay_digest: replay.replay_digest(),
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    canonical,
    digest,
  }
}

///|
fn decode_utc_instant_v3(
  bytes : Bytes,
) -> UtcInstantV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/UTC-INSTANT-V3/3.0.0" ||
    reader.read_string() != "3.0.0" {
    raise MalformedInput(field="utc_instant_v3_canonical")
  }
  let value = UtcInstantV3::new(reader.read_int64())
  reader.require_end()
  if value.canonical != bytes {
    raise DigestMismatch(field="utc_instant_v3_noncanonical")
  }
  value
}

///|
fn decode_time_observation_v3(
  bytes : Bytes,
) -> TimeObservationV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != time_observation_magic_v3 {
    raise MalformedInput(field="time_observation_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="time_observation_v3", version~)
  }
  let observation_id = reader.read_string()
  let time_workflow = reader.read_ref()
  let source_ref = reader.read_ref()
  let source_timezone_id = reader.read_string()
  let (resolved_boundary_ref, resolved_boundary_digest) = match
    reader.read_byte() {
    0 => (None, None)
    1 => (Some(reader.read_ref()), Some(reader.read_digest()))
    _ => raise MalformedInput(field="time_observation_v3_boundary_marker")
  }
  let source_instant = decode_utc_instant_v3(reader.read_bytes())
  let effective_instant = decode_utc_instant_v3(reader.read_bytes())
  let jump_kind = decode_clock_jump_kind_v3(reader.read_string())
  let observation_ordinal = reader.read_int64()
  let (previous_observation_ref, previous_observation_digest) = match
    reader.read_byte() {
    0 => (None, None)
    1 => (Some(reader.read_ref()), Some(reader.read_digest()))
    _ => raise MalformedInput(field="time_observation_v3_previous_marker")
  }
  let event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let expected_time_revision = reader.read_int64()
  let expected_time_head_digest = reader.read_optional_digest()
  let expected_time_replay_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  reader.require_end()
  require_text(observation_id, "time_observation_v3_id")
  require_text(source_timezone_id, "time_observation_v3_timezone_id")
  require_text(event_id, "time_observation_v3_event_id")
  require_text(command_idempotency_key, "time_observation_v3_command")
  if observation_ordinal <= 0L ||
    expected_time_revision < 0L ||
    evidence.is_empty() {
    raise MalformedInput(field="time_observation_v3_bounds")
  }
  match resolved_boundary_ref {
    Some(value) if resolved_boundary_digest != Some(value.digest()) =>
      raise ReplayBindingViolation(field="time_observation_v3_boundary_binding")
    _ => ()
  }
  let canonical = time_observation_signing_bytes_v3(
    observation_id, time_workflow, source_ref, source_timezone_id, resolved_boundary_ref,
    resolved_boundary_digest, source_instant, effective_instant, jump_kind, observation_ordinal,
    previous_observation_ref, previous_observation_digest, event_id, command_idempotency_key,
    expected_time_revision, expected_time_head_digest, expected_time_replay_digest,
    evidence,
  )
  if canonical != bytes {
    raise DigestMismatch(field="time_observation_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    observation_ref: self_ref_v3(
      "orchestration-time-observation-v3", observation_id, digest,
    ),
    time_workflow,
    source_ref,
    source_timezone_id,
    resolved_boundary_ref,
    resolved_boundary_digest,
    source_instant,
    effective_instant,
    jump_kind,
    observation_ordinal,
    previous_observation_ref,
    previous_observation_digest,
    event_id,
    command_idempotency_key,
    expected_time_revision,
    expected_time_head_digest,
    expected_time_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest,
  }
}

///|
fn time_observation_event_v3(
  record : TimeObservationV3,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let evidence = [ for value in record.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    "closed-loop.orchestration",
    orchestration_record_version,
    record.event_id,
    time_observed_event_kind_v3,
    record.source_ref,
    phase3_time_schema_v3(time_observed_event_kind_v3),
    record.canonical,
    "orchestration-protocol",
    orchestration_record_version,
    [],
    evidence,
    run_ref=record.time_workflow,
    correlation_ref=record.time_workflow.id(),
    causation_ref=record.source_ref.id(),
    idempotency_ref=record.observation_ref.id(),
    previous_digest?=record.expected_time_head_digest,
  ) catch {
    _ => raise MalformedInput(field="time_observation_v3_envelope")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    record.time_workflow,
    record.event_id,
    record.expected_time_revision + 1L,
    record.expected_time_revision + 1L,
    record.observation_ref.id(),
    envelope,
    evidence,
    previous_event_digest?=record.expected_time_head_digest,
  ) catch {
    _ => raise MalformedInput(field="time_observation_v3_event")
  }
}

///|
fn require_time_observation_transport_v3(
  record : TimeObservationV3,
  event : @storage.WorkflowEvent,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.workflow() != record.time_workflow ||
    event.event_ref().id() != record.event_id ||
    event.sequence() != record.expected_time_revision + 1L ||
    event.revision() != record.expected_time_revision + 1L ||
    event.previous_event_digest() != record.expected_time_head_digest ||
    event.idempotency_key() != record.observation_ref.id() ||
    envelope.envelope_id() != record.event_id ||
    envelope.envelope_kind() != time_observed_event_kind_v3 ||
    envelope.subject() != record.source_ref ||
    envelope.run_ref() != Some(record.time_workflow) ||
    envelope.payload() != record.canonical ||
    envelope.previous_digest() != record.expected_time_head_digest ||
    !same_evidence(event.evidence(), record.evidence) ||
    !same_evidence(envelope.evidence(), record.evidence) {
    raise ReplayBindingViolation(field="time_observation_v3_transport")
  }
}

///|
pub struct TimeEvidenceProjectionV3 {
  replay : @storage.ReplayResult
  observations : ReadOnlyArray[TimeObservationV3]
  latest : TimeObservationV3?
  digest : @contracts.ContentDigest
}

///|
fn require_time_observation_commit_boundary_v3(
  replay : @storage.ReplayResult,
  event : @storage.WorkflowEvent,
  record : TimeObservationV3,
) -> Unit raise OrchestrationError {
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref()
    })
  if batches.length() != 1 ||
    batches[0].command_idempotency_key() != record.command_idempotency_key ||
    batches[0].expected_revision() != record.expected_time_revision ||
    !batches[0].intent_refs().is_empty() ||
    !batches[0].guards().is_empty() {
    raise ReplayBindingViolation(field="time_observation_v3_commit_boundary")
  }
}

///|
pub fn fold_time_evidence_v3(
  replay : @storage.ReplayResult,
) -> TimeEvidenceProjectionV3 raise OrchestrationError {
  let observations : Array[TimeObservationV3] = []
  let mut previous : TimeObservationV3? = None
  for event in replay.events() {
    if event.payload().envelope_kind() != time_observed_event_kind_v3 {
      raise ReplayBindingViolation(field="time_evidence_v3_foreign_event")
    }
    let record = decode_time_observation_v3(event.payload().payload())
    require_time_observation_transport_v3(record, event)
    require_time_observation_commit_boundary_v3(replay, event, record)
    let prefix = replay.verified_prefix(record.expected_time_revision) catch {
      _ => raise ReplayBindingViolation(field="time_observation_v3_prefix")
    }
    if prefix.replay_digest() != record.expected_time_replay_digest ||
      prefix.head().last_event_digest() != record.expected_time_head_digest ||
      record.time_workflow != replay.workflow() {
      raise ReplayBindingViolation(field="time_observation_v3_replay")
    }
    match previous {
      None =>
        if record.observation_ordinal != 1L ||
          record.previous_observation_ref is Some(_) ||
          record.previous_observation_digest is Some(_) ||
          record.jump_kind != InitialClockObservationV3 ||
          record.effective_instant != record.source_instant {
          raise ReplayBindingViolation(field="time_observation_v3_initial")
        }
      Some(prior) => {
        let expected_jump = if record.source_instant.epoch_millis <
          prior.source_instant.epoch_millis {
          BackwardClockJumpClampedV3
        } else if record.source_instant.epoch_millis ==
          prior.source_instant.epoch_millis {
          ClockUnchangedV3
        } else {
          ClockAdvancedV3
        }
        let expected_effective = if record.source_instant.epoch_millis <
          prior.effective_instant.epoch_millis {
          prior.effective_instant.epoch_millis
        } else {
          record.source_instant.epoch_millis
        }
        if record.observation_ordinal != prior.observation_ordinal + 1L ||
          record.previous_observation_ref != Some(prior.observation_ref) ||
          record.previous_observation_digest != Some(prior.digest) ||
          record.jump_kind != expected_jump ||
          record.effective_instant.epoch_millis != expected_effective {
          raise ReplayBindingViolation(field="time_observation_v3_chain")
        }
      }
    }
    observations.push(record)
    previous = Some(record)
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/TIME-EVIDENCE-PROJECTION-V3/3.0.0")
  write_ref(writer, replay.workflow())
  writer.string(replay.replay_digest().text())
  writer.count(observations.length())
  for observation in observations {
    writer.string(observation.digest.text())
  }
  let digest = @contracts.sha256_digest(writer.finish())
  {
    replay,
    observations: ReadOnlyArray::from_array(observations),
    latest: previous,
    digest,
  }
}

///|
pub fn[S : @storage.StoragePort] replay_time_evidence_v3(
  store : S,
  time_workflow : @contracts.RecordRef,
) -> TimeEvidenceProjectionV3 raise {
  fold_time_evidence_v3(store.replay(time_workflow))
}

///|
pub fn TimeEvidenceProjectionV3::workflow(
  self : TimeEvidenceProjectionV3,
) -> @contracts.RecordRef {
  self.replay.workflow()
}

///|
pub fn TimeEvidenceProjectionV3::observations(
  self : TimeEvidenceProjectionV3,
) -> ReadOnlyArray[TimeObservationV3] {
  self.observations
}

///|
pub fn TimeEvidenceProjectionV3::latest(
  self : TimeEvidenceProjectionV3,
) -> TimeObservationV3? {
  self.latest
}

///|
pub fn TimeEvidenceProjectionV3::digest(
  self : TimeEvidenceProjectionV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct TimeObservationCommitPlanV3 {
  observation : TimeObservationV3
  request : @storage.CommitRequest
}

///|
pub fn prepare_time_observation_commit_v3(
  current : TimeEvidenceProjectionV3,
  observation_id : String,
  event_id : String,
  command_idempotency_key : String,
  source_ref : @contracts.RecordRef,
  source_timezone_id : String,
  source_instant : UtcInstantV3,
  evidence : Array[@contracts.EvidenceRef],
  resolved_boundary? : ResolvedCivilTimeV3,
) -> TimeObservationCommitPlanV3 raise OrchestrationError {
  let observation = make_time_observation_v3(
    current.replay,
    current.latest,
    observation_id,
    source_ref,
    source_timezone_id,
    resolved_boundary,
    source_instant,
    event_id,
    command_idempotency_key,
    evidence,
  )
  let event = time_observation_event_v3(observation)
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    observation.time_workflow,
    observation.expected_time_revision,
    command_idempotency_key,
    [event],
    [],
  ) catch {
    _ =>
      raise ReplayBindingViolation(field="time_observation_v3_commit_request")
  }
  { observation, request }
}

///|
pub fn TimeObservationCommitPlanV3::observation(
  self : TimeObservationCommitPlanV3,
) -> TimeObservationV3 {
  self.observation
}

///|
pub fn TimeObservationCommitPlanV3::request(
  self : TimeObservationCommitPlanV3,
) -> @storage.CommitRequest {
  self.request
}

///|
pub struct TimeObservationCommitReceiptV3 {
  receipt_ref : @contracts.RecordRef
  observation_ref : @contracts.RecordRef
  time_workflow : @contracts.RecordRef
  workflow_revision : Int64
  committed_event_digest : @contracts.ContentDigest
  storage_batch_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_time_observation_commit_receipt_v3(
  observation : TimeObservationV3,
  committed : @storage.CommitResult,
) -> TimeObservationCommitReceiptV3 raise OrchestrationError {
  if committed.workflow() != observation.time_workflow ||
    committed.command_idempotency_key() != observation.command_idempotency_key ||
    committed.first_sequence() != observation.expected_time_revision + 1L ||
    committed.workflow_revision() != observation.expected_time_revision + 1L ||
    committed.last_sequence() != observation.expected_time_revision + 1L ||
    committed.event_count() <= 0L {
    raise ReplayBindingViolation(field="time_observation_v3_commit_result")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/TIME-OBSERVATION-COMMIT-RECEIPT-V3/3.0.0")
  writer.string("3.0.0")
  write_ref(writer, observation.observation_ref)
  write_ref(writer, observation.time_workflow)
  writer.int64(committed.workflow_revision())
  writer.string(committed.last_event_digest().text())
  writer.string(committed.batch_digest().text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref_v3(
      "orchestration-time-observation-commit-receipt-v3",
      observation.observation_ref.id(),
      digest,
    ),
    observation_ref: observation.observation_ref,
    time_workflow: observation.time_workflow,
    workflow_revision: committed.workflow_revision(),
    committed_event_digest: committed.last_event_digest(),
    storage_batch_digest: committed.batch_digest(),
    canonical,
    digest,
  }
}

///|
pub fn[S : @storage.StoragePort] commit_time_observation_v3(
  store : S,
  plan : TimeObservationCommitPlanV3,
) -> TimeObservationCommitReceiptV3 raise {
  make_time_observation_commit_receipt_v3(
    plan.observation,
    store.commit(plan.request),
  )
}

///|
pub fn TimeObservationV3::record_ref(
  self : TimeObservationV3,
) -> @contracts.RecordRef {
  self.observation_ref
}

///|
pub fn TimeObservationV3::source_instant(
  self : TimeObservationV3,
) -> UtcInstantV3 {
  self.source_instant
}

///|
pub fn TimeObservationV3::source_timezone_id(
  self : TimeObservationV3,
) -> String {
  self.source_timezone_id
}

///|
pub fn TimeObservationV3::effective_instant(
  self : TimeObservationV3,
) -> UtcInstantV3 {
  self.effective_instant
}

///|
pub fn TimeObservationV3::jump_kind(
  self : TimeObservationV3,
) -> ClockJumpKindV3 {
  self.jump_kind
}

///|
pub fn TimeObservationV3::observation_ordinal(
  self : TimeObservationV3,
) -> Int64 {
  self.observation_ordinal
}

///|
pub fn TimeObservationV3::canonical_bytes(self : TimeObservationV3) -> Bytes {
  self.canonical
}

///|
pub fn TimeObservationV3::digest(
  self : TimeObservationV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn TimeObservationCommitReceiptV3::record_ref(
  self : TimeObservationCommitReceiptV3,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn TimeObservationCommitReceiptV3::workflow_revision(
  self : TimeObservationCommitReceiptV3,
) -> Int64 {
  self.workflow_revision
}

///|
pub fn TimeObservationCommitReceiptV3::canonical_bytes(
  self : TimeObservationCommitReceiptV3,
) -> Bytes {
  self.canonical
}

///|
pub fn TimeObservationCommitReceiptV3::digest(
  self : TimeObservationCommitReceiptV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum TimingWindowStateV3 {
  TimingWindowWaitingV3
  TimingWindowDueV3
  TimingWindowExpiredV3
} derive(Eq, Debug)

///|
pub struct TimingWindowDecisionV3 {
  decision_ref : @contracts.RecordRef
  observation_ref : @contracts.RecordRef
  observation_digest : @contracts.ContentDigest
  evaluated_at : UtcInstantV3
  not_before_inclusive : UtcInstantV3
  effective_deadline_ref : @contracts.RecordRef
  state : TimingWindowStateV3
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
/// Frozen window decision: `not_before` is inclusive and the effective
/// deadline is exclusive. The only time input is a committed observation.
pub fn evaluate_timing_window_v3(
  decision_id : String,
  observation : TimeObservationV3,
  not_before_inclusive : UtcInstantV3,
  effective_deadline : EffectiveDeadlineV3,
) -> TimingWindowDecisionV3 raise OrchestrationError {
  require_text(decision_id, "timing_window_v3_id")
  if not_before_inclusive.epoch_millis >=
    effective_deadline.exclusive_cutoff.epoch_millis {
    raise ScheduleStateViolation(field="timing_window_v3_empty")
  }
  let now = observation.effective_instant.epoch_millis
  let state = if now >= effective_deadline.exclusive_cutoff.epoch_millis {
    TimingWindowExpiredV3
  } else if now >= not_before_inclusive.epoch_millis {
    TimingWindowDueV3
  } else {
    TimingWindowWaitingV3
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/TIMING-WINDOW-DECISION-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(decision_id)
  write_ref(writer, observation.observation_ref)
  writer.string(observation.digest.text())
  writer.bytes(observation.effective_instant.canonical)
  writer.bytes(not_before_inclusive.canonical)
  write_ref(writer, effective_deadline.deadline_ref)
  writer.string(effective_deadline.digest.text())
  writer.string(
    match state {
      TimingWindowWaitingV3 => "waiting"
      TimingWindowDueV3 => "due"
      TimingWindowExpiredV3 => "expired"
    },
  )
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    decision_ref: self_ref_v3(
      "orchestration-timing-window-decision-v3", decision_id, digest,
    ),
    observation_ref: observation.observation_ref,
    observation_digest: observation.digest,
    evaluated_at: observation.effective_instant,
    not_before_inclusive,
    effective_deadline_ref: effective_deadline.deadline_ref,
    state,
    canonical,
    digest,
  }
}

///|
pub fn TimingWindowDecisionV3::record_ref(
  self : TimingWindowDecisionV3,
) -> @contracts.RecordRef {
  self.decision_ref
}

///|
pub fn TimingWindowDecisionV3::state(
  self : TimingWindowDecisionV3,
) -> TimingWindowStateV3 {
  self.state
}

///|
pub fn TimingWindowDecisionV3::evaluated_at(
  self : TimingWindowDecisionV3,
) -> UtcInstantV3 {
  self.evaluated_at
}

///|
pub fn TimingWindowDecisionV3::canonical_bytes(
  self : TimingWindowDecisionV3,
) -> Bytes {
  self.canonical
}

///|
pub fn TimingWindowDecisionV3::digest(
  self : TimingWindowDecisionV3,
) -> @contracts.ContentDigest {
  self.digest
}
