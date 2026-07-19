///|
let scheduled_action_registered_event_kind_v1 = "orchestration.scheduler.action-registered.v1"

///|
let scheduled_action_registration_magic_v1 = b"FLOW7/SCHEDULED-ACTION-REGISTRATION-V1/1.0.0"

///|
pub struct ScheduledActionRegistrationV1 {
  registration_ref : @contracts.RecordRef
  scheduler_workflow : @contracts.RecordRef
  action : ScheduledActionV3
  time_workflow : @contracts.RecordRef
  time_observation_ref : @contracts.RecordRef
  time_observation_digest : @contracts.ContentDigest
  registered_at : Int64
  expected_time_revision : Int64
  expected_time_head_digest : @contracts.ContentDigest?
  expected_time_replay_digest : @contracts.ContentDigest
  expected_scheduler_revision : Int64
  expected_scheduler_head_digest : @contracts.ContentDigest?
  expected_scheduler_replay_digest : @contracts.ContentDigest
  event_id : String
  command_idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn scheduled_action_registration_signing_bytes_v1(
  registration_id : String,
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
  action : ScheduledActionV3,
  event_id : String,
  command_idempotency_key : String,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Bytes raise OrchestrationError {
  guard time.latest() is Some(observation) else {
    raise ScheduleStateViolation(field="schedule_registration_time_v1")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(scheduled_action_registration_magic_v1)
  writer.string("1.0.0")
  writer.string(registration_id)
  write_ref(writer, scheduler.workflow())
  writer.bytes(action.canonical_bytes())
  writer.string(action.digest().text())
  write_ref(writer, time.workflow())
  write_ref(writer, observation.record_ref())
  writer.string(observation.digest().text())
  writer.int64(observation.effective_instant().epoch_millis())
  writer.int64(time.replay.head().revision())
  writer.optional_digest(time.replay.head().last_event_digest())
  writer.string(time.replay.replay_digest().text())
  writer.int64(scheduler.replay.head().revision())
  writer.optional_digest(scheduler.replay.head().last_event_digest())
  writer.string(scheduler.replay.replay_digest().text())
  writer.string(event_id)
  writer.string(command_idempotency_key)
  write_evidence(writer, evidence)
  writer.finish()
}

///|
fn decode_scheduled_action_registration_v1(
  bytes : Bytes,
) -> ScheduledActionRegistrationV1 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != scheduled_action_registration_magic_v1 ||
    reader.read_string() != "1.0.0" {
    raise MalformedInput(field="schedule_registration_magic_v1")
  }
  let registration_id = reader.read_string()
  let scheduler_workflow = reader.read_ref()
  let action = decode_scheduled_action_handoff_v1(reader.read_bytes())
  let action_digest = reader.read_digest()
  let time_workflow = reader.read_ref()
  let time_observation_ref = reader.read_ref()
  let time_observation_digest = reader.read_digest()
  let registered_at = reader.read_int64()
  let expected_time_revision = reader.read_int64()
  let expected_time_head_digest = reader.read_optional_digest()
  let expected_time_replay_digest = reader.read_digest()
  let expected_scheduler_revision = reader.read_int64()
  let expected_scheduler_head_digest = reader.read_optional_digest()
  let expected_scheduler_replay_digest = reader.read_digest()
  let event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let evidence = reader.read_evidence()
  reader.require_end()
  require_text(registration_id, "schedule_registration_id_v1")
  require_text(event_id, "schedule_registration_event_v1")
  require_text(command_idempotency_key, "schedule_registration_command_v1")
  if action.digest() != action_digest ||
    evidence.is_empty() ||
    expected_time_revision < 0L ||
    expected_scheduler_revision < 0L ||
    time_observation_ref.digest() != time_observation_digest {
    raise ReplayBindingViolation(field="schedule_registration_binding_v1")
  }
  let canonical = bytes.copy()
  let digest = @contracts.sha256_digest(canonical)
  {
    registration_ref: self_ref(
      "orchestration-scheduled-action-registration-v1", registration_id, digest,
    ),
    scheduler_workflow,
    action,
    time_workflow,
    time_observation_ref,
    time_observation_digest,
    registered_at,
    expected_time_revision,
    expected_time_head_digest,
    expected_time_replay_digest,
    expected_scheduler_revision,
    expected_scheduler_head_digest,
    expected_scheduler_replay_digest,
    event_id,
    command_idempotency_key,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest,
  }
}

///|
fn require_scheduled_action_registration_transport_v1(
  record : ScheduledActionRegistrationV1,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  require_scheduler_transport_v3(
    event,
    scheduled_action_registered_event_kind_v1,
    record.scheduler_workflow,
    record.action.subject_ref(),
    record.registration_ref,
    record.event_id,
    record.expected_scheduler_revision,
    record.expected_scheduler_head_digest,
    record.canonical,
    record.evidence,
  )
  require_scheduler_time_guard_v3(
    replay,
    event,
    record.command_idempotency_key,
    record.expected_scheduler_revision,
    record.time_workflow,
    record.expected_time_revision,
    record.expected_time_head_digest,
    record.expected_time_replay_digest,
  )
  let prefix = replay.verified_prefix(record.expected_scheduler_revision) catch {
    _ => raise ReplayBindingViolation(field="schedule_registration_prefix_v1")
  }
  if prefix.replay_digest() != record.expected_scheduler_replay_digest ||
    prefix.head().last_event_digest() != record.expected_scheduler_head_digest ||
    record.scheduler_workflow != replay.workflow() {
    raise ReplayBindingViolation(field="schedule_registration_replay_v1")
  }
}

///|
fn scheduled_action_registration_event_consumption_v1(
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Int raise OrchestrationError {
  let record = decode_scheduled_action_registration_v1(
    event.payload().payload(),
  )
  require_scheduled_action_registration_transport_v1(record, event, replay)
  1
}

///|
pub struct ScheduledActionRegistrationPlanV1 {
  registration : ScheduledActionRegistrationV1
  request : @storage.GuardedCommitRequest
}

///|
pub fn prepare_scheduled_action_registration_v1(
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
  action : ScheduledActionV3,
  registration_id : String,
  event_id : String,
  command_idempotency_key : String,
  evidence : Array[@contracts.EvidenceRef],
) -> ScheduledActionRegistrationPlanV1 raise OrchestrationError {
  require_text(registration_id, "schedule_registration_id_v1")
  require_text(event_id, "schedule_registration_event_v1")
  require_text(command_idempotency_key, "schedule_registration_command_v1")
  if evidence.is_empty() ||
    action.time_workflow != time.workflow() ||
    action.target_workflow() == scheduler.workflow() {
    raise ScheduleStateViolation(field="schedule_registration_binding_v1")
  }
  let existing = fold_scheduled_action_registrations_v1(scheduler.replay)
  match existing.action_by_ref(action.record_ref()) {
    Some(value) if value.canonical_bytes() == action.canonical_bytes() =>
      raise ScheduleStateViolation(field="schedule_registration_existing_v1")
    Some(_) => raise IdentityMismatch(field="schedule_registration_identity_v1")
    None => ()
  }
  guard time.latest() is Some(observation) else {
    raise ScheduleStateViolation(field="schedule_registration_time_v1")
  }
  let canonical = scheduled_action_registration_signing_bytes_v1(
    registration_id, scheduler, time, action, event_id, command_idempotency_key,
    evidence,
  )
  let digest = @contracts.sha256_digest(canonical)
  let registration : ScheduledActionRegistrationV1 = {
    registration_ref: self_ref(
      "orchestration-scheduled-action-registration-v1", registration_id, digest,
    ),
    scheduler_workflow: scheduler.workflow(),
    action,
    time_workflow: time.workflow(),
    time_observation_ref: observation.record_ref(),
    time_observation_digest: observation.digest(),
    registered_at: observation.effective_instant().epoch_millis(),
    expected_time_revision: time.replay.head().revision(),
    expected_time_head_digest: time.replay.head().last_event_digest(),
    expected_time_replay_digest: time.replay.replay_digest(),
    expected_scheduler_revision: scheduler.replay.head().revision(),
    expected_scheduler_head_digest: scheduler.replay.head().last_event_digest(),
    expected_scheduler_replay_digest: scheduler.replay.replay_digest(),
    event_id,
    command_idempotency_key,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    canonical,
    digest,
  }
  let event = scheduler_event_v3(
    scheduled_action_registered_event_kind_v1,
    registration.scheduler_workflow,
    action.subject_ref(),
    registration.registration_ref,
    event_id,
    command_idempotency_key,
    registration.expected_scheduler_revision,
    registration.expected_scheduler_head_digest,
    canonical,
    evidence,
  )
  let mutation = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    registration.scheduler_workflow,
    registration.expected_scheduler_revision,
    command_idempotency_key,
    [event],
    [],
  ) catch {
    _ => raise MalformedInput(field="schedule_registration_commit_request_v1")
  }
  let request = @storage.GuardedCommitRequest::new(mutation, [
    @storage.WorkflowHeadGuard::new(
      registration.time_workflow,
      registration.expected_time_revision,
      registration.expected_time_head_digest,
      registration.expected_time_replay_digest,
    ),
  ]) catch {
    _ => raise MalformedInput(field="schedule_registration_guarded_request_v1")
  }
  { registration, request }
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_scheduled_action_registration_v1(
  store : S,
  plan : ScheduledActionRegistrationPlanV1,
) -> @storage.ClassifiedGuardedCommitOutcome raise {
  store.classified_guarded_commit(plan.request)
}

///|
pub struct ScheduledActionRegistrationProjectionV1 {
  workflow : @contracts.RecordRef
  registrations : ReadOnlyArray[ScheduledActionRegistrationV1]
  actions : ReadOnlyArray[ScheduledActionV3]
  replay_digest : @contracts.ContentDigest
  state_digest : @contracts.ContentDigest
}

///|
pub fn fold_scheduled_action_registrations_v1(
  replay : @storage.ReplayResult,
) -> ScheduledActionRegistrationProjectionV1 raise OrchestrationError {
  let registrations : Array[ScheduledActionRegistrationV1] = []
  let actions : Array[ScheduledActionV3] = []
  for event in replay.events() {
    if event.payload().envelope_kind() ==
      scheduled_action_registered_event_kind_v1 {
      let record = decode_scheduled_action_registration_v1(
        event.payload().payload(),
      )
      require_scheduled_action_registration_transport_v1(record, event, replay)
      if actions.any(value => {
          value.record_ref().kind() == record.action.record_ref().kind() &&
          value.record_ref().id() == record.action.record_ref().id()
        }) {
        raise IdentityMismatch(field="schedule_registration_duplicate_v1")
      }
      registrations.push(record)
      actions.push(record.action)
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/SCHEDULED-ACTION-REGISTRATION-PROJECTION-V1/1.0.0")
  writer.string("1.0.0")
  write_ref(writer, replay.workflow())
  writer.string(replay.replay_digest().text())
  writer.count(registrations.length())
  for value in registrations {
    writer.bytes(value.canonical)
  }
  {
    workflow: replay.workflow(),
    registrations: ReadOnlyArray::from_array(registrations),
    actions: ReadOnlyArray::from_array(actions),
    replay_digest: replay.replay_digest(),
    state_digest: @contracts.sha256_digest(writer.finish()),
  }
}

///|
pub fn ScheduledActionRegistrationProjectionV1::actions(
  self : ScheduledActionRegistrationProjectionV1,
) -> ReadOnlyArray[ScheduledActionV3] {
  self.actions
}

///|
pub fn ScheduledActionRegistrationProjectionV1::action_by_ref(
  self : ScheduledActionRegistrationProjectionV1,
  reference : @contracts.RecordRef,
) -> ScheduledActionV3? {
  self.actions.filter(value => value.record_ref() == reference).last()
}

///|
pub fn ScheduledActionRegistrationV1::record_ref(
  self : ScheduledActionRegistrationV1,
) -> @contracts.RecordRef {
  self.registration_ref
}

///|
pub fn ScheduledActionRegistrationV1::action(
  self : ScheduledActionRegistrationV1,
) -> ScheduledActionV3 {
  self.action
}

///|
pub fn ScheduledActionRegistrationPlanV1::registration(
  self : ScheduledActionRegistrationPlanV1,
) -> ScheduledActionRegistrationV1 {
  self.registration
}
