///|
let orchestration_record_version_v22 = "2.2.0"

///|
let retry_policy_bound_event_kind_v22 = "retry.policy.bound.v2"

///|
let cancellation_governance_bound_event_kind_v22 = "cancellation.governance.bound.v2"

///|
let utc_millis_upper_inclusive_v22 = 253402300799999L

///|
let governance_cutoff_upper_inclusive_v22 = 253402300799998L

///|
fn self_ref_v22(
  kind : String,
  id : String,
  digest : @contracts.ContentDigest,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    orchestration_record_version_v22,
    digest.text(),
  )
}

///|
fn empty_orchestration_state_digest_v22(
  workflow : @contracts.RecordRef,
) -> @contracts.ContentDigest raise OrchestrationError {
  build_projection_v2(
    workflow,
    0L,
    0L,
    None,
    [],
    [],
    [],
    [],
    [],
    [],
    [],
    None,
    None,
    0L,
    0L,
  ).state_digest()
}

///|
fn require_utc_millis_v22(
  value : Int64,
  field : String,
) -> Unit raise OrchestrationError {
  if value < 0L || value > utc_millis_upper_inclusive_v22 {
    raise MalformedInput(field~)
  }
}

///|
pub fn checked_exclusive_deadline_v22(
  valid_until_inclusive : Int64,
) -> Int64 raise OrchestrationError {
  if valid_until_inclusive < 0L ||
    valid_until_inclusive > governance_cutoff_upper_inclusive_v22 {
    raise ArithmeticOverflow(field="exclusive_deadline_v22")
  }
  valid_until_inclusive + 1L
}

///|
pub fn cancellation_authorization_times_v22(
  proposal_observed_at : Int64,
  authority_requested_at : Int64,
  authority_decided_at : Int64,
  review_requested_at : Int64,
  review_decided_at : Int64,
  review_bound_at : Int64,
  governance_valid_until_inclusive : Int64,
  request_deadline_exclusive : Int64?,
) -> (Int64, Int64, Int64) raise OrchestrationError {
  let values = [
    proposal_observed_at, authority_requested_at, authority_decided_at, review_requested_at,
    review_decided_at, review_bound_at,
  ]
  for value in values {
    require_utc_millis_v22(value, "cancellation_authorization_time_v22")
  }
  for index = 1; index < values.length(); index = index + 1 {
    if values[index] < values[index - 1] {
      raise ClockRegression(previous=values[index - 1], incoming=values[index])
    }
  }
  if governance_valid_until_inclusive < 0L ||
    governance_valid_until_inclusive > governance_cutoff_upper_inclusive_v22 {
    raise MalformedInput(field="governance_valid_until_inclusive_v22")
  }
  let observed_at = values.fold(init=0L, (current, value) => {
    if value > current {
      value
    } else {
      current
    }
  })
  let root_deadline_exclusive = checked_exclusive_deadline_v22(
    governance_valid_until_inclusive,
  )
  let effective_deadline_exclusive = match request_deadline_exclusive {
    None => root_deadline_exclusive
    Some(value) => {
      if value < 1L || value > utc_millis_upper_inclusive_v22 {
        raise MalformedInput(field="request_deadline_exclusive_v22")
      }
      if value < root_deadline_exclusive {
        value
      } else {
        root_deadline_exclusive
      }
    }
  }
  if observed_at >= effective_deadline_exclusive {
    raise AuthorityExpired(
      expires_at=effective_deadline_exclusive,
      observed_at~,
    )
  }
  (observed_at, effective_deadline_exclusive - 1L, effective_deadline_exclusive)
}

///|
/// Strictly derive an empty aggregate from one storage-verified empty replay.
/// `ClosedLoopProjectionV2` is opaque, so this is the only genesis aggregate
/// minting path available to callers.
pub fn fold_empty_closed_loop_v22(
  empty_effects : @effects.EffectsProjection,
  replay : @storage.ReplayResult,
) -> ClosedLoopProjectionV2 raise OrchestrationError {
  let head = replay.head()
  if replay.workflow() != empty_effects.workflow() ||
    head.workflow() != replay.workflow() {
    raise WorkflowMismatch(field="initial_work_empty_replay_workflow")
  }
  if !replay.events().is_empty() ||
    !replay.intents().is_empty() ||
    !replay.committed_batches().is_empty() ||
    replay.checkpoint() is Some(_) ||
    head.sequence() != 0L ||
    head.revision() != 0L ||
    head.event_count() != 0L ||
    head.intent_count() != 0L ||
    head.last_event_digest() is Some(_) ||
    empty_effects.sequence() != 0L ||
    empty_effects.revision() != 0L ||
    empty_effects.last_event_digest() is Some(_) ||
    !empty_effects.attempts().is_empty() ||
    !empty_effects.intents().is_empty() {
    raise ReplayBindingViolation(field="initial_work_empty_replay")
  }
  let orchestration = fold_orchestration_v2_internal(replay, false, false)
  if orchestration.workflow() != replay.workflow() ||
    orchestration.sequence() != 0L ||
    orchestration.revision() != 0L ||
    orchestration.last_event_digest() is Some(_) ||
    orchestration.schedule_count() != 0 {
    raise ReplayBindingViolation(field="initial_work_empty_projection")
  }
  {
    effects: empty_effects,
    orchestration,
    prefix_event: None,
    replay_digest: replay.replay_digest(),
    cancellation: None,
    work_terminal: None,
    terminal_batch_boundary: None,
  }
}

///|
/// Opaque, replay-derived authority for exactly one initial three-event batch.
/// It has no public constructor or decoder and exposes no component authority.
pub struct InitialWorkAuthorizationV2 {
  authorization_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  effects_state_digest : @contracts.ContentDigest
  orchestration_state_digest : @contracts.ContentDigest
  replay_digest : @contracts.ContentDigest
  registration_ref : @contracts.RecordRef
  registration_bytes : Bytes
  admission_proof_ref : @contracts.RecordRef
  admission_proof_digest : @contracts.ContentDigest
  admission_proof_bytes : Bytes
  governed_subject : @contracts.RecordRef
  retry_policy : RetryPolicyV2
  governance_policy : @governance.GovernancePolicy
  governance_stream_ref : @contracts.RecordRef
  governance_valid_until_inclusive : Int64
  schedule_event_id : String
  retry_binding_id : String
  retry_binding_event_id : String
  retry_binding_event_key : String
  governance_binding_id : String
  governance_binding_event_id : String
  governance_binding_event_key : String
  command_idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn initial_work_authorization_signing_bytes_v22(
  authorization_id : String,
  aggregate : ClosedLoopProjectionV2,
  registration : ScheduleRegisteredV2,
  retry_policy : RetryPolicyV2,
  governance_policy : @governance.GovernancePolicy,
  governance_stream_ref : @contracts.RecordRef,
  governance_valid_until_inclusive : Int64,
  schedule_event_id : String,
  retry_binding_id : String,
  retry_binding_event_id : String,
  retry_binding_event_key : String,
  governance_binding_id : String,
  governance_binding_event_id : String,
  governance_binding_event_key : String,
  command_idempotency_key : String,
) -> Bytes raise OrchestrationError {
  let schedule = registration.schedule()
  let admission = schedule.admission()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/INITIAL-WORK-AUTHORIZATION-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(authorization_id)
  write_ref(writer, registration.workflow())
  writer.int64(0L)
  writer.int64(0L)
  writer.optional_digest(None)
  writer.bytes(@utf8.encode(aggregate.effects().state_digest().text()))
  writer.bytes(@utf8.encode(aggregate.orchestration().state_digest().text()))
  writer.bytes(@utf8.encode(aggregate.replay_digest().text()))
  write_ref(writer, registration.record_ref())
  writer.bytes(registration.canonical_bytes())
  write_ref(writer, admission.proof_ref())
  writer.bytes(@utf8.encode(admission.proof_digest().text()))
  writer.bytes(admission.proof_bytes())
  write_ref(writer, admission.governance().governed_subject())
  write_ref(writer, retry_policy.policy_ref())
  writer.bytes(@utf8.encode(retry_policy.digest().text()))
  writer.bytes(retry_policy.canonical_bytes())
  write_ref(writer, governance_policy.policy_ref())
  writer.bytes(@utf8.encode(governance_policy.digest().text()))
  writer.bytes(governance_policy.canonical_bytes())
  write_ref(writer, governance_stream_ref)
  writer.int64(governance_valid_until_inclusive)
  writer.string(schedule_event_id)
  writer.string(retry_binding_id)
  writer.string(retry_binding_event_id)
  writer.string(retry_binding_event_key)
  writer.string(governance_binding_id)
  writer.string(governance_binding_event_id)
  writer.string(governance_binding_event_key)
  writer.string(command_idempotency_key)
  write_evidence(writer, schedule.evidence())
  write_ref(writer, schedule.causation_ref())
  writer.finish()
}

///|
pub fn authorize_initial_work_v22(
  authorization_id : String,
  aggregate : ClosedLoopProjectionV2,
  registration : ScheduleRegisteredV2,
  retry_policy : RetryPolicyV2,
  governance_policy : @governance.GovernancePolicy,
  governance_stream_ref : @contracts.RecordRef,
  governance_valid_until_inclusive : Int64,
  schedule_event_id : String,
  retry_binding_id : String,
  retry_binding_event_id : String,
  retry_binding_event_key : String,
  governance_binding_id : String,
  governance_binding_event_id : String,
  governance_binding_event_key : String,
  command_idempotency_key : String,
) -> InitialWorkAuthorizationV2 raise OrchestrationError {
  for
    pair in [
      (authorization_id, "initial_work_authorization_id"),
      (schedule_event_id, "initial_work_schedule_event_id"),
      (retry_binding_id, "initial_work_retry_binding_id"),
      (retry_binding_event_id, "initial_work_retry_event_id"),
      (retry_binding_event_key, "initial_work_retry_event_key"),
      (governance_binding_id, "initial_work_governance_binding_id"),
      (governance_binding_event_id, "initial_work_governance_event_id"),
      (governance_binding_event_key, "initial_work_governance_event_key"),
      (command_idempotency_key, "initial_work_command_key"),
    ] {
    require_text(pair.0, pair.1)
  }
  let effects = aggregate.effects()
  let orchestration = aggregate.orchestration()
  if effects.workflow() != orchestration.workflow() ||
    registration.workflow() != orchestration.workflow() ||
    effects.sequence() != 0L ||
    effects.revision() != 0L ||
    effects.last_event_digest() is Some(_) ||
    orchestration.sequence() != 0L ||
    orchestration.revision() != 0L ||
    orchestration.last_event_digest() is Some(_) ||
    orchestration.schedule_count() != 0 ||
    aggregate.prefix_event() is Some(_) {
    raise ReplayBindingViolation(field="initial_work_authorization_empty")
  }
  let schedule = registration.schedule()
  let admission = schedule.admission()
  require_schedule_admission_head_v2(
    registration.workflow(),
    0L,
    0L,
    None,
    registration,
  )
  if schedule.previous_digest() is Some(_) {
    raise DigestMismatch(field="initial_work_previous_digest")
  }
  let decoded_retry = RetryPolicyV2::decode(
    retry_policy.policy_ref().id(),
    retry_policy.canonical_bytes(),
  )
  if decoded_retry.policy_ref() != retry_policy.policy_ref() ||
    decoded_retry.digest() != retry_policy.digest() ||
    decoded_retry.canonical_bytes() != retry_policy.canonical_bytes() {
    raise PolicyMismatch(field="initial_work_retry_policy")
  }
  match schedule.retry_policy() {
    None => ()
    Some(bound) =>
      if bound.policy_ref() != retry_policy.policy_ref() ||
        bound.digest() != retry_policy.digest() ||
        bound.canonical_bytes() != retry_policy.canonical_bytes() {
        raise PolicyMismatch(field="initial_work_schedule_retry_policy")
      }
  }
  let decoded_governance = @governance.GovernancePolicy::decode(
    governance_policy.policy_ref(),
    governance_policy.canonical_bytes(),
  ) catch {
    _ => raise PolicyMismatch(field="initial_work_governance_policy")
  }
  let admission_governance = admission.governance()
  let expected_empty_effects = @effects.EffectsProjection::new(
    registration.workflow(),
    governance_policy.policy_ref(),
  )
  if decoded_governance.policy_ref() != governance_policy.policy_ref() ||
    decoded_governance.digest() != governance_policy.digest() ||
    decoded_governance.canonical_bytes() != governance_policy.canonical_bytes() ||
    admission_governance.policy_ref() != governance_policy.policy_ref() ||
    admission_governance.policy_digest() != governance_policy.digest() ||
    effects.state_digest() != expected_empty_effects.state_digest() ||
    orchestration.state_digest() !=
    empty_orchestration_state_digest_v22(registration.workflow()) ||
    aggregate.replay_digest() !=
    @storage.empty_replay_digest(registration.workflow()) {
    raise PolicyMismatch(field="initial_work_governance_policy")
  }
  if governance_stream_ref == registration.workflow() {
    raise GovernanceMismatch(field="initial_work_governance_stream")
  }
  let admission_clock = admission.eligibility().clock()
  if !admission_governance.accepts(admission_clock) {
    raise AuthorityExpired(
      expires_at=admission_governance.valid_until_inclusive(),
      observed_at=admission_clock,
    )
  }
  if governance_valid_until_inclusive < 0L ||
    governance_valid_until_inclusive > governance_cutoff_upper_inclusive_v22 ||
    governance_valid_until_inclusive < admission_clock ||
    governance_valid_until_inclusive <
    admission_governance.valid_from_inclusive() ||
    governance_valid_until_inclusive >
    admission_governance.valid_until_inclusive() {
    raise MalformedInput(field="cancellation_governance_valid_until_inclusive")
  }
  let canonical = initial_work_authorization_signing_bytes_v22(
    authorization_id, aggregate, registration, decoded_retry, decoded_governance,
    governance_stream_ref, governance_valid_until_inclusive, schedule_event_id, retry_binding_id,
    retry_binding_event_id, retry_binding_event_key, governance_binding_id, governance_binding_event_id,
    governance_binding_event_key, command_idempotency_key,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    authorization_ref: self_ref_v22(
      "orchestration-initial-work-authorization-v2", authorization_id, digest,
    ),
    workflow: registration.workflow(),
    effects_state_digest: effects.state_digest(),
    orchestration_state_digest: orchestration.state_digest(),
    replay_digest: aggregate.replay_digest(),
    registration_ref: registration.record_ref(),
    registration_bytes: registration.canonical_bytes(),
    admission_proof_ref: admission.proof_ref(),
    admission_proof_digest: admission.proof_digest(),
    admission_proof_bytes: admission.proof_bytes(),
    governed_subject: admission_governance.governed_subject(),
    retry_policy: decoded_retry,
    governance_policy: decoded_governance,
    governance_stream_ref,
    governance_valid_until_inclusive,
    schedule_event_id,
    retry_binding_id,
    retry_binding_event_id,
    retry_binding_event_key,
    governance_binding_id,
    governance_binding_event_id,
    governance_binding_event_key,
    command_idempotency_key,
    evidence: ReadOnlyArray::from_array(
      [
        for value in schedule.evidence() => value
      ],
    ),
    causation: schedule.causation_ref(),
    canonical,
    digest,
  }
}

///|
fn digest_from_bytes_v22(
  bytes : Bytes,
  field : String,
) -> @contracts.ContentDigest raise OrchestrationError {
  let text = @utf8.decode(bytes) catch { _ => raise MalformedInput(field~) }
  @contracts.ContentDigest::parse(text) catch {
    _ => raise MalformedInput(field~)
  }
}

///|
fn decode_initial_work_authorization_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> InitialWorkAuthorizationV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/INITIAL-WORK-AUTHORIZATION-V2/2.2.0" {
    raise MalformedInput(field="initial_work_authorization_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="initial_work_authorization", version~)
  }
  let authorization_id = reader.read_string()
  let workflow = reader.read_ref()
  if reader.read_int64() != 0L ||
    reader.read_int64() != 0L ||
    reader.read_optional_digest() is Some(_) {
    raise ReplayBindingViolation(field="initial_work_authorization_genesis")
  }
  let effects_state_digest = digest_from_bytes_v22(
    reader.read_bytes(),
    "initial_work_effects_state_digest",
  )
  let orchestration_state_digest = digest_from_bytes_v22(
    reader.read_bytes(),
    "initial_work_orchestration_state_digest",
  )
  let replay_digest = digest_from_bytes_v22(
    reader.read_bytes(),
    "initial_work_replay_digest",
  )
  let registration_ref = reader.read_ref()
  let registration_bytes = reader.read_bytes()
  let admission_proof_ref = reader.read_ref()
  let admission_proof_digest_bytes = reader.read_bytes()
  let admission_proof_bytes = reader.read_bytes()
  let governed_subject = reader.read_ref()
  let retry_policy_ref = reader.read_ref()
  let retry_policy_digest_bytes = reader.read_bytes()
  let retry_policy_bytes = reader.read_bytes()
  let governance_policy_ref = reader.read_ref()
  let governance_policy_digest_bytes = reader.read_bytes()
  let governance_policy_bytes = reader.read_bytes()
  let governance_stream_ref = reader.read_ref()
  let governance_valid_until_inclusive = reader.read_int64()
  let schedule_event_id = reader.read_string()
  let retry_binding_id = reader.read_string()
  let retry_binding_event_id = reader.read_string()
  let retry_binding_event_key = reader.read_string()
  let governance_binding_id = reader.read_string()
  let governance_binding_event_id = reader.read_string()
  let governance_binding_event_key = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let evidence = reader.read_evidence()
  let causation = reader.read_ref()
  reader.require_end()
  let digest = @contracts.sha256_digest(bytes)
  let actual_ref = self_ref_v22(
    "orchestration-initial-work-authorization-v2", authorization_id, digest,
  )
  if actual_ref != expected_ref {
    raise DigestMismatch(field="initial_work_authorization_expected_ref")
  }
  let registration = ScheduleRegisteredV2::decode(
    registration_ref.id(),
    registration_bytes,
  )
  let admission = registration.schedule().admission()
  if registration.record_ref() != registration_ref ||
    registration.workflow() != workflow ||
    admission.proof_ref() != admission_proof_ref ||
    admission.proof_digest() !=
    digest_from_bytes_v22(
      admission_proof_digest_bytes, "initial_work_admission_proof_digest",
    ) ||
    admission.proof_bytes() != admission_proof_bytes ||
    admission.governance().governed_subject() != governed_subject {
    raise ReplayBindingViolation(field="initial_work_authorization_admission")
  }
  let retry_policy = RetryPolicyV2::decode(
    retry_policy_ref.id(),
    retry_policy_bytes,
  )
  if retry_policy.policy_ref() != retry_policy_ref ||
    retry_policy.digest() !=
    digest_from_bytes_v22(
      retry_policy_digest_bytes, "initial_work_retry_policy_digest",
    ) ||
    retry_policy.canonical_bytes() != retry_policy_bytes {
    raise PolicyMismatch(field="initial_work_retry_policy")
  }
  let governance_policy = @governance.GovernancePolicy::decode(
    governance_policy_ref, governance_policy_bytes,
  ) catch {
    _ => raise PolicyMismatch(field="initial_work_governance_policy")
  }
  if governance_policy.digest() !=
    digest_from_bytes_v22(
      governance_policy_digest_bytes, "initial_work_governance_policy_digest",
    ) ||
    admission.governance().policy_ref() != governance_policy_ref ||
    admission.governance().policy_digest() != governance_policy.digest() ||
    governance_stream_ref == workflow ||
    governance_valid_until_inclusive < admission.eligibility().clock() ||
    governance_valid_until_inclusive <
    admission.governance().valid_from_inclusive() ||
    governance_valid_until_inclusive >
    admission.governance().valid_until_inclusive() ||
    governance_valid_until_inclusive > governance_cutoff_upper_inclusive_v22 {
    raise PolicyMismatch(field="initial_work_governance_policy")
  }
  match registration.schedule().retry_policy() {
    None => ()
    Some(bound) =>
      if bound.policy_ref() != retry_policy.policy_ref() ||
        bound.digest() != retry_policy.digest() ||
        bound.canonical_bytes() != retry_policy.canonical_bytes() {
        raise PolicyMismatch(field="initial_work_schedule_retry_policy")
      }
  }
  {
    authorization_ref: actual_ref,
    workflow,
    effects_state_digest,
    orchestration_state_digest,
    replay_digest,
    registration_ref,
    registration_bytes,
    admission_proof_ref,
    admission_proof_digest: admission_proof_ref.digest(),
    admission_proof_bytes,
    governed_subject,
    retry_policy,
    governance_policy,
    governance_stream_ref,
    governance_valid_until_inclusive,
    schedule_event_id,
    retry_binding_id,
    retry_binding_event_id,
    retry_binding_event_key,
    governance_binding_id,
    governance_binding_event_id,
    governance_binding_event_key,
    command_idempotency_key,
    evidence: ReadOnlyArray::from_array(evidence),
    causation,
    canonical: bytes,
    digest,
  }
}

///|
pub struct CommittedRetryPolicyBindingV2 {
  record_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  prefix_schedule_event_ref : @contracts.RecordRef
  prefix_schedule_event_digest : @contracts.ContentDigest
  prefix_schedule_event_bytes : Bytes
  retry_policy_ref : @contracts.RecordRef
  retry_policy_digest : @contracts.ContentDigest
  retry_policy_bytes : Bytes
  admission_proof_ref : @contracts.RecordRef
  admission_proof_digest : @contracts.ContentDigest
  admission_proof_bytes : Bytes
  initial_authorization_ref : @contracts.RecordRef
  initial_authorization_digest : @contracts.ContentDigest
  initial_authorization_bytes : Bytes
  schedule_event_id : String
  retry_binding_event_id : String
  retry_binding_event_key : String
  governance_binding_id : String
  governance_binding_event_id : String
  governance_binding_event_key : String
  command_idempotency_key : String
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn retry_policy_binding_signing_bytes_v22(
  binding_id : String,
  workflow : @contracts.RecordRef,
  schedule_registration_ref : @contracts.RecordRef,
  prefix_schedule_event : @storage.WorkflowEvent,
  authorization : InitialWorkAuthorizationV2,
) -> Bytes raise OrchestrationError {
  let retry_policy = authorization.retry_policy
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-RETRY-POLICY-BINDING-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(binding_id)
  write_ref(writer, workflow)
  write_ref(writer, schedule_registration_ref)
  write_ref(writer, prefix_schedule_event.event_ref())
  writer.bytes(@utf8.encode(prefix_schedule_event.event_ref().digest().text()))
  writer.bytes(prefix_schedule_event.canonical_bytes())
  write_ref(writer, retry_policy.policy_ref())
  writer.bytes(@utf8.encode(retry_policy.digest().text()))
  writer.bytes(retry_policy.canonical_bytes())
  write_ref(writer, authorization.admission_proof_ref)
  writer.bytes(@utf8.encode(authorization.admission_proof_digest.text()))
  writer.bytes(authorization.admission_proof_bytes)
  write_ref(writer, authorization.authorization_ref)
  writer.bytes(@utf8.encode(authorization.digest.text()))
  writer.bytes(authorization.canonical)
  writer.string(authorization.schedule_event_id)
  writer.string(authorization.retry_binding_event_id)
  writer.string(authorization.retry_binding_event_key)
  writer.string(authorization.governance_binding_id)
  writer.string(authorization.governance_binding_event_id)
  writer.string(authorization.governance_binding_event_key)
  writer.string(authorization.command_idempotency_key)
  writer.finish()
}

///|
fn build_retry_policy_binding_v22(
  binding_id : String,
  registration : ScheduleRegisteredV2,
  prefix_schedule_event : @storage.WorkflowEvent,
  authorization : InitialWorkAuthorizationV2,
) -> CommittedRetryPolicyBindingV2 raise OrchestrationError {
  require_text(binding_id, "retry_policy_binding_v22_id")
  if binding_id != authorization.retry_binding_id {
    raise ReplayBindingViolation(field="initial_work_retry_binding_id")
  }
  if prefix_schedule_event.payload().envelope_kind() !=
    schedule_registered_event_kind_v2 ||
    prefix_schedule_event.payload().subject() != registration.record_ref() ||
    prefix_schedule_event.payload().payload() != registration.canonical_bytes() {
    raise ReplayBindingViolation(field="retry_policy_binding_v22_e1")
  }
  let admission = registration.schedule().admission()
  let retry_policy = authorization.retry_policy
  let canonical = retry_policy_binding_signing_bytes_v22(
    binding_id,
    registration.workflow(),
    registration.record_ref(),
    prefix_schedule_event,
    authorization,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v22(
      "orchestration-committed-retry-policy-binding-v2", binding_id, digest,
    ),
    workflow: registration.workflow(),
    schedule_registration_ref: registration.record_ref(),
    prefix_schedule_event_ref: prefix_schedule_event.event_ref(),
    prefix_schedule_event_digest: prefix_schedule_event.event_ref().digest(),
    prefix_schedule_event_bytes: prefix_schedule_event.canonical_bytes(),
    retry_policy_ref: retry_policy.policy_ref(),
    retry_policy_digest: retry_policy.digest(),
    retry_policy_bytes: retry_policy.canonical_bytes(),
    admission_proof_ref: admission.proof_ref(),
    admission_proof_digest: admission.proof_digest(),
    admission_proof_bytes: admission.proof_bytes(),
    initial_authorization_ref: authorization.authorization_ref,
    initial_authorization_digest: authorization.digest,
    initial_authorization_bytes: authorization.canonical,
    schedule_event_id: authorization.schedule_event_id,
    retry_binding_event_id: authorization.retry_binding_event_id,
    retry_binding_event_key: authorization.retry_binding_event_key,
    governance_binding_id: authorization.governance_binding_id,
    governance_binding_event_id: authorization.governance_binding_event_id,
    governance_binding_event_key: authorization.governance_binding_event_key,
    command_idempotency_key: authorization.command_idempotency_key,
    canonical,
    digest,
  }
}

///|
fn decode_retry_policy_binding_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> CommittedRetryPolicyBindingV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/COMMITTED-RETRY-POLICY-BINDING-V2/2.2.0" {
    raise MalformedInput(field="retry_policy_binding_v22_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="retry_policy_binding_v22", version~)
  }
  let binding_id = reader.read_string()
  let workflow = reader.read_ref()
  let registration_ref = reader.read_ref()
  let e1_ref = reader.read_ref()
  let e1_digest = reader.read_bytes()
  let e1_bytes = reader.read_bytes()
  let policy_ref = reader.read_ref()
  let policy_digest = reader.read_bytes()
  let policy_bytes = reader.read_bytes()
  let proof_ref = reader.read_ref()
  let proof_digest = reader.read_bytes()
  let proof_bytes = reader.read_bytes()
  let initial_authorization_ref = reader.read_ref()
  let initial_authorization_digest = reader.read_bytes()
  let initial_authorization_bytes = reader.read_bytes()
  let schedule_event_id = reader.read_string()
  let retry_binding_event_id = reader.read_string()
  let retry_binding_event_key = reader.read_string()
  let governance_binding_id = reader.read_string()
  let governance_binding_event_id = reader.read_string()
  let governance_binding_event_key = reader.read_string()
  let command_idempotency_key = reader.read_string()
  reader.require_end()
  if e1_digest != @utf8.encode(e1_ref.digest().text()) ||
    policy_digest != @utf8.encode(policy_ref.digest().text()) ||
    proof_digest != @utf8.encode(proof_ref.digest().text()) ||
    initial_authorization_digest !=
    @utf8.encode(initial_authorization_ref.digest().text()) ||
    @contracts.sha256_digest(initial_authorization_bytes) !=
    initial_authorization_ref.digest() {
    raise DigestMismatch(field="retry_policy_binding_v22_embedded_digest")
  }
  let digest = @contracts.sha256_digest(bytes)
  let actual_ref = self_ref_v22(
    "orchestration-committed-retry-policy-binding-v2", binding_id, digest,
  )
  if actual_ref != expected_ref {
    raise DigestMismatch(field="retry_policy_binding_v22_expected_ref")
  }
  {
    record_ref: actual_ref,
    workflow,
    schedule_registration_ref: registration_ref,
    prefix_schedule_event_ref: e1_ref,
    prefix_schedule_event_digest: e1_ref.digest(),
    prefix_schedule_event_bytes: e1_bytes,
    retry_policy_ref: policy_ref,
    retry_policy_digest: policy_ref.digest(),
    retry_policy_bytes: policy_bytes,
    admission_proof_ref: proof_ref,
    admission_proof_digest: proof_ref.digest(),
    admission_proof_bytes: proof_bytes,
    initial_authorization_ref,
    initial_authorization_digest: initial_authorization_ref.digest(),
    initial_authorization_bytes,
    schedule_event_id,
    retry_binding_event_id,
    retry_binding_event_key,
    governance_binding_id,
    governance_binding_event_id,
    governance_binding_event_key,
    command_idempotency_key,
    canonical: bytes,
    digest,
  }
}

///|
fn verify_retry_policy_binding_v22(
  expected_ref : @contracts.RecordRef,
  expected_e1 : @storage.WorkflowEvent,
  bytes : Bytes,
) -> CommittedRetryPolicyBindingV2 raise OrchestrationError {
  let decoded = decode_retry_policy_binding_v22(expected_ref, bytes)
  let authorization = decode_initial_work_authorization_v22(
    decoded.initial_authorization_ref,
    decoded.initial_authorization_bytes,
  )
  let registration = ScheduleRegisteredV2::decode(
    expected_e1.payload().subject().id(),
    expected_e1.payload().payload(),
  )
  let admission = registration.schedule().admission()
  let retry_policy = RetryPolicyV2::decode(
    decoded.retry_policy_ref.id(),
    decoded.retry_policy_bytes,
  )
  if decoded.prefix_schedule_event_ref != expected_e1.event_ref() ||
    decoded.prefix_schedule_event_digest != expected_e1.event_ref().digest() ||
    decoded.prefix_schedule_event_bytes != expected_e1.canonical_bytes() ||
    decoded.workflow != registration.workflow() ||
    decoded.schedule_registration_ref != registration.record_ref() ||
    decoded.admission_proof_ref != admission.proof_ref() ||
    decoded.admission_proof_digest != admission.proof_digest() ||
    decoded.admission_proof_bytes != admission.proof_bytes() ||
    authorization.registration_ref != registration.record_ref() ||
    authorization.registration_bytes != registration.canonical_bytes() ||
    authorization.admission_proof_ref != admission.proof_ref() ||
    authorization.admission_proof_digest != admission.proof_digest() ||
    authorization.admission_proof_bytes != admission.proof_bytes() ||
    authorization.retry_policy.policy_ref() != decoded.retry_policy_ref ||
    authorization.retry_policy.digest() != decoded.retry_policy_digest ||
    authorization.retry_policy.canonical_bytes() != decoded.retry_policy_bytes ||
    retry_policy.policy_ref() != decoded.retry_policy_ref ||
    retry_policy.digest() != decoded.retry_policy_digest ||
    retry_policy.canonical_bytes() != decoded.retry_policy_bytes ||
    authorization.schedule_event_id != expected_e1.event_ref().id() ||
    authorization.retry_binding_id != expected_ref.id() {
    raise ReplayBindingViolation(field="retry_policy_binding_v22_e1")
  }
  match registration.schedule().retry_policy() {
    None => ()
    Some(bound) =>
      if bound.policy_ref() != retry_policy.policy_ref() ||
        bound.digest() != retry_policy.digest() ||
        bound.canonical_bytes() != retry_policy.canonical_bytes() {
        raise PolicyMismatch(field="initial_work_schedule_retry_policy")
      }
  }
  decoded
}

///|
pub fn CommittedRetryPolicyBindingV2::record_ref(
  self : CommittedRetryPolicyBindingV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn CommittedRetryPolicyBindingV2::canonical_bytes(
  self : CommittedRetryPolicyBindingV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedRetryPolicyBindingV2::retry_policy_ref(
  self : CommittedRetryPolicyBindingV2,
) -> @contracts.RecordRef {
  self.retry_policy_ref
}

///|
pub struct CommittedCancellationGovernanceBindingV2 {
  record_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  prefix_schedule_event_ref : @contracts.RecordRef
  prefix_schedule_event_bytes : Bytes
  retry_policy_binding_ref : @contracts.RecordRef
  retry_policy_binding_bytes : Bytes
  retry_policy_binding_event_ref : @contracts.RecordRef
  retry_policy_binding_event_bytes : Bytes
  governance_stream_ref : @contracts.RecordRef
  governance_policy_ref : @contracts.RecordRef
  governance_policy_digest : @contracts.ContentDigest
  governance_policy_bytes : Bytes
  valid_until_inclusive : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn cancellation_governance_binding_signing_bytes_v22(
  binding_id : String,
  registration : ScheduleRegisteredV2,
  e1 : @storage.WorkflowEvent,
  retry_binding : CommittedRetryPolicyBindingV2,
  e2 : @storage.WorkflowEvent,
  governance_stream_ref : @contracts.RecordRef,
  governance_policy_ref : @contracts.RecordRef,
  governance_policy_bytes : Bytes,
  valid_until_inclusive : Int64,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-CANCELLATION-GOVERNANCE-BINDING-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(binding_id)
  write_ref(writer, registration.workflow())
  write_ref(writer, registration.record_ref())
  write_ref(writer, e1.event_ref())
  writer.bytes(e1.canonical_bytes())
  write_ref(writer, retry_binding.record_ref())
  writer.bytes(retry_binding.canonical_bytes())
  write_ref(writer, e2.event_ref())
  writer.bytes(e2.canonical_bytes())
  write_ref(writer, governance_stream_ref)
  write_ref(writer, governance_policy_ref)
  writer.bytes(@utf8.encode(governance_policy_ref.digest().text()))
  writer.bytes(governance_policy_bytes)
  writer.int64(valid_until_inclusive)
  writer.finish()
}

///|
fn build_cancellation_governance_binding_v22(
  binding_id : String,
  registration : ScheduleRegisteredV2,
  e1 : @storage.WorkflowEvent,
  retry_binding : CommittedRetryPolicyBindingV2,
  e2 : @storage.WorkflowEvent,
  governance_stream_ref : @contracts.RecordRef,
  governance_policy_ref : @contracts.RecordRef,
  governance_policy_bytes : Bytes,
  valid_until_inclusive : Int64,
) -> CommittedCancellationGovernanceBindingV2 raise OrchestrationError {
  require_text(binding_id, "cancellation_governance_binding_v22_id")
  if governance_stream_ref == registration.workflow() {
    raise GovernanceMismatch(field="cancellation_governance_stream_v22")
  }
  if @contracts.sha256_digest(governance_policy_bytes) !=
    governance_policy_ref.digest() {
    raise DigestMismatch(field="cancellation_governance_policy_v22")
  }
  let decoded_governance_policy = @governance.GovernancePolicy::decode(
    governance_policy_ref, governance_policy_bytes,
  ) catch {
    _ => raise PolicyMismatch(field="root_cancellation_governance_binding")
  }
  if decoded_governance_policy.policy_ref() != governance_policy_ref ||
    decoded_governance_policy.digest() != governance_policy_ref.digest() ||
    decoded_governance_policy.canonical_bytes() != governance_policy_bytes {
    raise PolicyMismatch(field="root_cancellation_governance_binding")
  }
  if valid_until_inclusive < 0L ||
    valid_until_inclusive > governance_cutoff_upper_inclusive_v22 {
    raise MalformedInput(field="cancellation_governance_cutoff_v22")
  }
  if e2.payload().envelope_kind() != retry_policy_bound_event_kind_v22 ||
    e2.payload().subject() != retry_binding.record_ref() ||
    e2.payload().payload() != retry_binding.canonical_bytes() {
    raise ReplayBindingViolation(field="cancellation_governance_binding_v22_e2")
  }
  let canonical = cancellation_governance_binding_signing_bytes_v22(
    binding_id, registration, e1, retry_binding, e2, governance_stream_ref, governance_policy_ref,
    governance_policy_bytes, valid_until_inclusive,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v22(
      "orchestration-committed-cancellation-governance-binding-v2", binding_id, digest,
    ),
    workflow: registration.workflow(),
    schedule_registration_ref: registration.record_ref(),
    prefix_schedule_event_ref: e1.event_ref(),
    prefix_schedule_event_bytes: e1.canonical_bytes(),
    retry_policy_binding_ref: retry_binding.record_ref(),
    retry_policy_binding_bytes: retry_binding.canonical_bytes(),
    retry_policy_binding_event_ref: e2.event_ref(),
    retry_policy_binding_event_bytes: e2.canonical_bytes(),
    governance_stream_ref,
    governance_policy_ref,
    governance_policy_digest: governance_policy_ref.digest(),
    governance_policy_bytes,
    valid_until_inclusive,
    canonical,
    digest,
  }
}

///|
pub fn CommittedCancellationGovernanceBindingV2::record_ref(
  self : CommittedCancellationGovernanceBindingV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn CommittedCancellationGovernanceBindingV2::canonical_bytes(
  self : CommittedCancellationGovernanceBindingV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedCancellationGovernanceBindingV2::governance_stream_ref(
  self : CommittedCancellationGovernanceBindingV2,
) -> @contracts.RecordRef {
  self.governance_stream_ref
}

///|
pub fn CommittedCancellationGovernanceBindingV2::valid_until_inclusive(
  self : CommittedCancellationGovernanceBindingV2,
) -> Int64 {
  self.valid_until_inclusive
}

///|
fn decode_cancellation_governance_binding_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> CommittedCancellationGovernanceBindingV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() !=
    b"FLOW7/COMMITTED-CANCELLATION-GOVERNANCE-BINDING-V2/2.2.0" {
    raise MalformedInput(field="cancellation_governance_binding_v22_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(
      field="cancellation_governance_binding_v22",
      version~,
    )
  }
  let binding_id = reader.read_string()
  let workflow = reader.read_ref()
  let registration_ref = reader.read_ref()
  let e1_ref = reader.read_ref()
  let e1_bytes = reader.read_bytes()
  let r2_ref = reader.read_ref()
  let r2_bytes = reader.read_bytes()
  let e2_ref = reader.read_ref()
  let e2_bytes = reader.read_bytes()
  let governance_stream_ref = reader.read_ref()
  let governance_policy_ref = reader.read_ref()
  let governance_policy_digest = reader.read_bytes()
  let governance_policy_bytes = reader.read_bytes()
  let valid_until_inclusive = reader.read_int64()
  reader.require_end()
  if governance_stream_ref == workflow {
    raise GovernanceMismatch(field="cancellation_governance_stream_v22")
  }
  if governance_policy_digest !=
    @utf8.encode(governance_policy_ref.digest().text()) ||
    @contracts.sha256_digest(governance_policy_bytes) !=
    governance_policy_ref.digest() {
    raise DigestMismatch(field="cancellation_governance_policy_v22")
  }
  let decoded_governance_policy = @governance.GovernancePolicy::decode(
    governance_policy_ref, governance_policy_bytes,
  ) catch {
    _ => raise PolicyMismatch(field="root_cancellation_governance_binding")
  }
  if decoded_governance_policy.canonical_bytes() != governance_policy_bytes {
    raise PolicyMismatch(field="root_cancellation_governance_binding")
  }
  if valid_until_inclusive < 0L ||
    valid_until_inclusive > governance_cutoff_upper_inclusive_v22 {
    raise MalformedInput(field="cancellation_governance_cutoff_v22")
  }
  let digest = @contracts.sha256_digest(bytes)
  let actual_ref = self_ref_v22(
    "orchestration-committed-cancellation-governance-binding-v2", binding_id, digest,
  )
  if actual_ref != expected_ref {
    raise DigestMismatch(
      field="cancellation_governance_binding_v22_expected_ref",
    )
  }
  {
    record_ref: actual_ref,
    workflow,
    schedule_registration_ref: registration_ref,
    prefix_schedule_event_ref: e1_ref,
    prefix_schedule_event_bytes: e1_bytes,
    retry_policy_binding_ref: r2_ref,
    retry_policy_binding_bytes: r2_bytes,
    retry_policy_binding_event_ref: e2_ref,
    retry_policy_binding_event_bytes: e2_bytes,
    governance_stream_ref,
    governance_policy_ref,
    governance_policy_digest: governance_policy_ref.digest(),
    governance_policy_bytes,
    valid_until_inclusive,
    canonical: bytes,
    digest,
  }
}

///|
fn verify_cancellation_governance_binding_v22(
  expected_ref : @contracts.RecordRef,
  expected_e1 : @storage.WorkflowEvent,
  expected_r2 : CommittedRetryPolicyBindingV2,
  expected_e2 : @storage.WorkflowEvent,
  bytes : Bytes,
) -> CommittedCancellationGovernanceBindingV2 raise OrchestrationError {
  let decoded = decode_cancellation_governance_binding_v22(expected_ref, bytes)
  if decoded.prefix_schedule_event_ref != expected_e1.event_ref() ||
    decoded.prefix_schedule_event_bytes != expected_e1.canonical_bytes() ||
    decoded.retry_policy_binding_ref != expected_r2.record_ref() ||
    decoded.retry_policy_binding_bytes != expected_r2.canonical_bytes() ||
    decoded.retry_policy_binding_event_ref != expected_e2.event_ref() ||
    decoded.retry_policy_binding_event_bytes != expected_e2.canonical_bytes() {
    raise ReplayBindingViolation(
      field="cancellation_governance_binding_v22_dag",
    )
  }
  decoded
}

///|
fn phase1a_schema_v22(kind : String) -> @contracts.SchemaRef {
  orchestration_schema(kind)
}

///|
fn phase1a_event_v22(
  workflow : @contracts.RecordRef,
  event_id : String,
  event_kind : String,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  event_idempotency_key : String,
  sequence : Int64,
  revision : Int64,
  previous_digest : @contracts.ContentDigest?,
) -> @storage.WorkflowEvent raise {
  let envelope = @contracts.WireEnvelope::new(
    orchestration_contract_id,
    orchestration_record_version,
    event_id,
    event_kind,
    subject,
    phase1a_schema_v22(event_kind),
    payload,
    orchestration_producer_id,
    orchestration_record_version,
    [],
    evidence,
    run_ref=workflow,
    correlation_ref=workflow.id(),
    causation_ref=causation.id(),
    idempotency_ref=event_idempotency_key,
    previous_digest?,
  )
  let previous_event_digest = previous_digest
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    workflow,
    event_id,
    sequence,
    revision,
    event_idempotency_key,
    envelope,
    evidence,
    previous_event_digest?,
  )
}

///|
pub fn prepare_initial_work_v22(
  supplied_authorization : InitialWorkAuthorizationV2,
  registration : ScheduleRegisteredV2,
) -> @storage.CommitRequest raise {
  let authorization = decode_initial_work_authorization_v22(
    supplied_authorization.authorization_ref,
    supplied_authorization.canonical,
  )
  if registration.record_ref() != authorization.registration_ref ||
    registration.canonical_bytes() != authorization.registration_bytes ||
    registration.workflow() != authorization.workflow {
    raise ReplayBindingViolation(field="initial_work_registration")
  }
  let schedule = registration.schedule()
  if schedule.previous_digest() is Some(_) {
    raise DigestMismatch(field="initial_admission_v22_previous_digest")
  }
  let evidence = [ for value in authorization.evidence => value ]
  if !same_evidence(schedule.evidence(), evidence) ||
    schedule.causation_ref() != authorization.causation {
    raise ReplayBindingViolation(field="initial_work_wrapper_inputs")
  }
  let e1 = phase1a_event_v22(
    authorization.workflow,
    authorization.schedule_event_id,
    schedule_registered_event_kind_v2,
    registration.record_ref(),
    registration.canonical_bytes(),
    evidence,
    authorization.causation,
    schedule.idempotency_key(),
    1L,
    1L,
    None,
  )
  let r2 = build_retry_policy_binding_v22(
    authorization.retry_binding_id,
    registration,
    e1,
    authorization,
  )
  let e2 = phase1a_event_v22(
    authorization.workflow,
    authorization.retry_binding_event_id,
    retry_policy_bound_event_kind_v22,
    r2.record_ref(),
    r2.canonical_bytes(),
    evidence,
    authorization.causation,
    authorization.retry_binding_event_key,
    2L,
    2L,
    Some(e1.event_ref().digest()),
  )
  let r3 = build_cancellation_governance_binding_v22(
    authorization.governance_binding_id,
    registration,
    e1,
    r2,
    e2,
    authorization.governance_stream_ref,
    authorization.governance_policy.policy_ref(),
    authorization.governance_policy.canonical_bytes(),
    authorization.governance_valid_until_inclusive,
  )
  let e3 = phase1a_event_v22(
    authorization.workflow,
    authorization.governance_binding_event_id,
    cancellation_governance_bound_event_kind_v22,
    r3.record_ref(),
    r3.canonical_bytes(),
    evidence,
    authorization.causation,
    authorization.governance_binding_event_key,
    3L,
    3L,
    Some(e2.event_ref().digest()),
  )
  @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    authorization.workflow,
    0L,
    authorization.command_idempotency_key,
    [e1, e2, e3],
    [],
  )
}

///|
pub struct CommittedCancellationGovernanceBindingReceiptV2 {
  record_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  registration : ScheduleRegisteredV2
  retry_policy : CommittedRetryPolicyBindingV2
  cancellation_governance : CommittedCancellationGovernanceBindingV2
  initial_expected_revision : Int64
  initial_command_idempotency_key : String
  initial_batch_digest : @contracts.ContentDigest
  initial_event_refs : ReadOnlyArray[@contracts.RecordRef]
  effects_state_digest : @contracts.ContentDigest
  orchestration_state_digest : @contracts.ContentDigest
  current_sequence : Int64
  current_revision : Int64
  current_head_digest : @contracts.ContentDigest
  replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn CommittedCancellationGovernanceBindingReceiptV2::record_ref(
  self : CommittedCancellationGovernanceBindingReceiptV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn CommittedCancellationGovernanceBindingReceiptV2::canonical_bytes(
  self : CommittedCancellationGovernanceBindingReceiptV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedCancellationGovernanceBindingReceiptV2::retry_policy_ref(
  self : CommittedCancellationGovernanceBindingReceiptV2,
) -> @contracts.RecordRef {
  self.retry_policy.retry_policy_ref
}

///|
pub fn CommittedCancellationGovernanceBindingReceiptV2::governance_stream_ref(
  self : CommittedCancellationGovernanceBindingReceiptV2,
) -> @contracts.RecordRef {
  self.cancellation_governance.governance_stream_ref
}

///|
pub fn CommittedCancellationGovernanceBindingReceiptV2::governance_policy_ref(
  self : CommittedCancellationGovernanceBindingReceiptV2,
) -> @contracts.RecordRef {
  self.cancellation_governance.governance_policy_ref
}

///|
pub fn CommittedCancellationGovernanceBindingReceiptV2::valid_until_inclusive(
  self : CommittedCancellationGovernanceBindingReceiptV2,
) -> Int64 {
  self.cancellation_governance.valid_until_inclusive
}

///|
pub fn CommittedCancellationGovernanceBindingReceiptV2::root_batch_digest(
  self : CommittedCancellationGovernanceBindingReceiptV2,
) -> @contracts.ContentDigest {
  self.initial_batch_digest
}

///|
pub fn CommittedCancellationGovernanceBindingReceiptV2::current_revision(
  self : CommittedCancellationGovernanceBindingReceiptV2,
) -> Int64 {
  self.current_revision
}

///|
fn require_phase1a_wrapper_v22(
  event : @storage.WorkflowEvent,
  event_id : String,
  event_kind : String,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence : ArrayView[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  idempotency_key : String,
  sequence : Int64,
  revision : Int64,
  previous_digest : @contracts.ContentDigest?,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.workflow() != envelope.run_ref().unwrap_or(event.workflow()) ||
    event.event_ref().id() != event_id ||
    envelope.envelope_id() != event_id ||
    event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.sequence() != sequence ||
    event.revision() != revision ||
    event.previous_event_digest() != previous_digest ||
    event.idempotency_key() != idempotency_key ||
    envelope.contract_id() != orchestration_contract_id ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.schema() != phase1a_schema_v22(event_kind) ||
    envelope.producer_id() != orchestration_producer_id ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != event_kind ||
    envelope.subject() != subject ||
    envelope.payload() != payload ||
    envelope.run_ref() != Some(event.workflow()) ||
    envelope.correlation_ref() != Some(event.workflow().id()) ||
    envelope.causation_ref() != Some(causation.id()) ||
    envelope.idempotency_ref() != Some(idempotency_key) ||
    envelope.previous_digest() != previous_digest ||
    !same_evidence(event.evidence(), evidence) ||
    !same_evidence(envelope.evidence(), evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) {
    raise ReplayBindingViolation(field="initial_work_wrapper_binding")
  }
}

///|
fn require_closed_replay_accounting_with_root_v22(
  replay : @storage.ReplayResult,
  effects : @effects.EffectsProjection,
  root_refs : ArrayView[@contracts.RecordRef],
) -> Unit raise OrchestrationError {
  let consumed = effects.strict_consumed_event_refs() catch {
    _ => raise ReplayBindingViolation(field="aggregate_effect_coverage")
  }
  for event in replay.events() {
    let effects_count = consumed
      .filter(value => value == event.event_ref())
      .length()
    let root_count = root_refs
      .filter(value => value == event.event_ref())
      .length()
    let orchestration_count = if root_count == 0 &&
      orchestration_event_kind_v2(event.payload().envelope_kind()) {
      1
    } else {
      0
    }
    let recovery_count = if root_count == 0 {
      recovery_event_consumption_v3(event, replay)
    } else {
      0
    }
    if effects_count + orchestration_count + recovery_count + root_count != 1 {
      raise ReplayBindingViolation(field="aggregate_event_consumption")
    }
  }
  let matched = effects.strict_matched_outbox_refs() catch {
    _ => raise ReplayBindingViolation(field="aggregate_outbox_coverage")
  }
  for outbox in replay.intents() {
    if matched.filter(value => value == outbox.intent_ref()).length() != 1 {
      raise ReplayBindingViolation(field="aggregate_outbox_consumption")
    }
  }
  for matched_ref in matched {
    if replay
      .intents()
      .filter(value => value.intent_ref() == matched_ref)
      .length() !=
      1 {
      raise ReplayBindingViolation(field="aggregate_matched_outbox_ref")
    }
  }
}

///|
fn root_binding_receipt_signing_bytes_v22(
  receipt_id : String,
  workflow : @contracts.RecordRef,
  registration : ScheduleRegisteredV2,
  r2 : CommittedRetryPolicyBindingV2,
  r3 : CommittedCancellationGovernanceBindingV2,
  batch : @storage.CommittedBatchBoundary,
  effects : @effects.EffectsProjection,
  orchestration : OrchestrationProjectionV2,
  replay : @storage.ReplayResult,
) -> Bytes raise OrchestrationError {
  let head = replay.head()
  let writer = OrchestrationWriter::new()
  writer.bytes(
    b"FLOW7/COMMITTED-CANCELLATION-GOVERNANCE-BINDING-RECEIPT-V2/2.2.0",
  )
  writer.string(orchestration_record_version_v22)
  writer.string(receipt_id)
  write_ref(writer, workflow)
  write_ref(writer, registration.record_ref())
  writer.bytes(registration.canonical_bytes())
  write_ref(writer, r2.record_ref())
  writer.bytes(r2.canonical_bytes())
  write_ref(writer, r3.record_ref())
  writer.bytes(r3.canonical_bytes())
  writer.int64(batch.expected_revision())
  writer.string(batch.command_idempotency_key())
  writer.bytes(@utf8.encode(batch.batch_digest().text()))
  writer.count(batch.event_refs().length())
  for value in batch.event_refs() {
    write_ref(writer, value)
  }
  writer.count(0)
  writer.bytes(@utf8.encode(effects.state_digest().text()))
  writer.bytes(@utf8.encode(orchestration.state_digest().text()))
  writer.int64(head.sequence())
  writer.int64(head.revision())
  writer.bytes(@utf8.encode(head.last_event_digest().unwrap().text()))
  writer.bytes(@utf8.encode(replay.replay_digest().text()))
  writer.finish()
}

///|
/// Reject a second committed root as a stable replay-cardinality violation.
/// A later schedule by itself is valid (for retry), so only another exact
/// three-event, no-outbox root-shaped commit is classified as a duplicate.
fn require_single_committed_root_batch_v22(
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let events = replay.events()
  for batch_index, batch in replay.committed_batches() {
    if batch_index > 0 {
      let refs = batch.event_refs()
      if refs.length() == 3 && batch.intent_refs().is_empty() {
        let first = events.search_by(event => event.event_ref() == refs[0])
        let second = events.search_by(event => event.event_ref() == refs[1])
        let third = events.search_by(event => event.event_ref() == refs[2])
        if first is Some(first_index) &&
          second is Some(second_index) &&
          third is Some(third_index) &&
          events[first_index].payload().envelope_kind() ==
          schedule_registered_event_kind_v2 &&
          events[second_index].payload().envelope_kind() ==
          retry_policy_bound_event_kind_v22 &&
          events[third_index].payload().envelope_kind() ==
          cancellation_governance_bound_event_kind_v22 {
          raise ReplayBindingViolation(
            field="initial_admission_v22_duplicate_root",
          )
        }
      }
    }
  }
}

///|
pub fn fold_initial_work_receipt_v22(
  empty_effects : @effects.EffectsProjection,
  replay : @storage.ReplayResult,
) -> CommittedCancellationGovernanceBindingReceiptV2 raise OrchestrationError {
  let events = replay.events()
  if events.is_empty() ||
    events[0].payload().envelope_kind() != schedule_registered_event_kind_v2 {
    raise PolicyMismatch(field="root_retry_policy_binding_missing")
  }
  if events.length() < 2 ||
    events[1].payload().envelope_kind() != retry_policy_bound_event_kind_v22 {
    raise PolicyMismatch(field="root_retry_policy_binding_missing")
  }
  if events.length() < 3 ||
    events[2].payload().envelope_kind() !=
    cancellation_governance_bound_event_kind_v22 {
    raise PolicyMismatch(field="root_cancellation_governance_binding_missing")
  }
  if replay.committed_batches().is_empty() {
    raise ReplayBindingViolation(field="initial_admission_v22_batch")
  }
  let batch = replay.committed_batches()[0]
  let refs = batch.event_refs()
  if batch.expected_revision() != 0L ||
    refs.length() != 3 ||
    !batch.intent_refs().is_empty() {
    raise ReplayBindingViolation(field="initial_admission_v22_batch")
  }
  let events = replay.events()
  let e1 = events[0]
  let e2 = events[1]
  let e3 = events[2]
  if refs[0] != e1.event_ref() ||
    refs[1] != e2.event_ref() ||
    refs[2] != e3.event_ref() ||
    e1.payload().envelope_kind() != schedule_registered_event_kind_v2 ||
    e2.payload().envelope_kind() != retry_policy_bound_event_kind_v22 ||
    e3.payload().envelope_kind() != cancellation_governance_bound_event_kind_v22 {
    raise ReplayBindingViolation(field="initial_admission_v22_order")
  }
  require_single_committed_root_batch_v22(replay)
  let registration = ScheduleRegisteredV2::decode(
    e1.payload().subject().id(),
    e1.payload().payload(),
  )
  if registration.record_ref() != e1.payload().subject() ||
    registration.workflow() != replay.workflow() {
    raise ReplayBindingViolation(field="initial_admission_v22_e1")
  }
  let r2 = verify_retry_policy_binding_v22(
    e2.payload().subject(),
    e1,
    e2.payload().payload(),
  )
  let authorization = decode_initial_work_authorization_v22(
    r2.initial_authorization_ref,
    r2.initial_authorization_bytes,
  )
  let expected_empty_effects = @effects.EffectsProjection::new(
    replay.workflow(),
    authorization.governance_policy.policy_ref(),
  )
  if authorization.effects_state_digest != expected_empty_effects.state_digest() ||
    empty_effects.state_digest() != expected_empty_effects.state_digest() ||
    authorization.orchestration_state_digest !=
    empty_orchestration_state_digest_v22(replay.workflow()) ||
    authorization.replay_digest !=
    @storage.empty_replay_digest(replay.workflow()) {
    raise ReplayBindingViolation(field="initial_work_authorization_genesis")
  }
  let schedule = registration.schedule()
  let evidence = [ for value in schedule.evidence() => value ]
  require_phase1a_wrapper_v22(
    e1,
    authorization.schedule_event_id,
    schedule_registered_event_kind_v2,
    registration.record_ref(),
    registration.canonical_bytes(),
    evidence,
    schedule.causation_ref(),
    schedule.idempotency_key(),
    1L,
    1L,
    None,
  )
  require_phase1a_wrapper_v22(
    e2,
    r2.retry_binding_event_id,
    retry_policy_bound_event_kind_v22,
    r2.record_ref(),
    r2.canonical_bytes(),
    evidence,
    schedule.causation_ref(),
    r2.retry_binding_event_key,
    2L,
    2L,
    Some(e1.event_ref().digest()),
  )
  if r2.workflow != replay.workflow() ||
    r2.schedule_registration_ref != registration.record_ref() ||
    r2.prefix_schedule_event_ref != e1.event_ref() ||
    r2.prefix_schedule_event_bytes != e1.canonical_bytes() ||
    e2.previous_event_digest() != Some(e1.event_ref().digest()) ||
    batch.command_idempotency_key() != r2.command_idempotency_key {
    raise ReplayBindingViolation(field="initial_admission_v22_r2")
  }
  let decoded_policy = RetryPolicyV2::decode(
    r2.retry_policy_ref.id(),
    r2.retry_policy_bytes,
  )
  if decoded_policy.policy_ref() != r2.retry_policy_ref ||
    decoded_policy.digest() != r2.retry_policy_digest ||
    decoded_policy.canonical_bytes() != r2.retry_policy_bytes {
    raise PolicyMismatch(field="initial_admission_v22_retry_policy")
  }
  let r3 = verify_cancellation_governance_binding_v22(
    e3.payload().subject(),
    e1,
    r2,
    e2,
    e3.payload().payload(),
  )
  require_phase1a_wrapper_v22(
    e3,
    r2.governance_binding_event_id,
    cancellation_governance_bound_event_kind_v22,
    r3.record_ref(),
    r3.canonical_bytes(),
    evidence,
    schedule.causation_ref(),
    r2.governance_binding_event_key,
    3L,
    3L,
    Some(e2.event_ref().digest()),
  )
  if r3.workflow != replay.workflow() ||
    r3.schedule_registration_ref != registration.record_ref() ||
    r3.prefix_schedule_event_ref != e1.event_ref() ||
    r3.retry_policy_binding_ref != r2.record_ref() ||
    r3.retry_policy_binding_event_ref != e2.event_ref() ||
    e3.previous_event_digest() != Some(e2.event_ref().digest()) ||
    r3.record_ref().id() != r2.governance_binding_id ||
    r3.governance_stream_ref != authorization.governance_stream_ref ||
    r3.governance_policy_ref != authorization.governance_policy.policy_ref() ||
    r3.governance_policy_digest != authorization.governance_policy.digest() ||
    r3.governance_policy_bytes !=
    authorization.governance_policy.canonical_bytes() ||
    r3.valid_until_inclusive != authorization.governance_valid_until_inclusive {
    raise ReplayBindingViolation(field="initial_admission_v22_r3")
  }
  let effects = @effects.fold_committed_effects_bytes(empty_effects, replay) catch {
    _ => raise ReplayBindingViolation(field="aggregate_effects_replay")
  }
  if !effects.attempts().is_empty() && !effects.strict_semantic_governance_v2() {
    raise ReplayBindingViolation(field="aggregate_governance_v2_required")
  }
  let orchestration = fold_orchestration_v2_internal(replay, true, true)
  require_closed_replay_accounting_with_root_v22(replay, effects, [
    e1.event_ref(),
    e2.event_ref(),
    e3.event_ref(),
  ])
  let head = replay.head()
  guard head.last_event_digest() is Some(current_head_digest) else {
    raise ReplayBindingViolation(field="initial_work_receipt_head")
  }
  if effects.workflow() != replay.workflow() ||
    effects.sequence() != head.sequence() ||
    effects.revision() != head.revision() ||
    effects.last_event_digest() != Some(current_head_digest) ||
    orchestration.workflow() != replay.workflow() ||
    orchestration.sequence() != head.sequence() ||
    orchestration.revision() != head.revision() ||
    orchestration.last_event_digest() != Some(current_head_digest) ||
    orchestration.schedule_registration_refs().is_empty() ||
    orchestration.schedule_registration_refs()[0] != registration.record_ref() {
    raise ReplayBindingViolation(field="initial_work_receipt_projection")
  }
  let receipt_id = "{registration.record_ref().id()}:root-binding"
  let canonical = root_binding_receipt_signing_bytes_v22(
    receipt_id,
    replay.workflow(),
    registration,
    r2,
    r3,
    batch,
    effects,
    orchestration,
    replay,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v22(
      "orchestration-committed-cancellation-governance-binding-receipt-v2", receipt_id,
      digest,
    ),
    workflow: replay.workflow(),
    registration,
    retry_policy: r2,
    cancellation_governance: r3,
    initial_expected_revision: batch.expected_revision(),
    initial_command_idempotency_key: batch.command_idempotency_key(),
    initial_batch_digest: batch.batch_digest(),
    initial_event_refs: ReadOnlyArray::from_array(
      [
        for value in refs => value
      ],
    ),
    effects_state_digest: effects.state_digest(),
    orchestration_state_digest: orchestration.state_digest(),
    current_sequence: head.sequence(),
    current_revision: head.revision(),
    current_head_digest,
    replay_digest: replay.replay_digest(),
    canonical,
    digest,
  }
}

///|
pub fn CommittedCancellationGovernanceBindingReceiptV2::validate_current(
  self : CommittedCancellationGovernanceBindingReceiptV2,
  empty_effects : @effects.EffectsProjection,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let current = fold_initial_work_receipt_v22(empty_effects, replay)
  if current.record_ref != self.record_ref ||
    current.canonical != self.canonical ||
    current.workflow != self.workflow ||
    current.effects_state_digest != self.effects_state_digest ||
    current.orchestration_state_digest != self.orchestration_state_digest ||
    current.current_sequence != self.current_sequence ||
    current.current_revision != self.current_revision ||
    current.current_head_digest != self.current_head_digest ||
    current.replay_digest != self.replay_digest ||
    current.initial_batch_digest != self.initial_batch_digest {
    raise ReplayBindingViolation(field="root_binding_receipt_not_current")
  }
}

///|
/// Rebuild the V2 lifecycle projection only after the exact Phase 1A root batch
/// and its closed replay accounting have been verified. The returned opaque
/// projection carries replay-derived root authority required by every public
/// lease/lifecycle preparation path.
pub fn fold_root_bound_orchestration_v22(
  empty_effects : @effects.EffectsProjection,
  replay : @storage.ReplayResult,
) -> OrchestrationProjectionV2 raise OrchestrationError {
  ignore(fold_initial_work_receipt_v22(empty_effects, replay))
  fold_orchestration_v2_internal(replay, true, true)
}

///|
fn fold_root_bound_orchestration_auto_v22(
  replay : @storage.ReplayResult,
) -> OrchestrationProjectionV2 raise OrchestrationError {
  let events = replay.events()
  if events.length() < 3 {
    raise ReplayBindingViolation(field="initial_work_root_batch_missing")
  }
  let r2 = verify_retry_policy_binding_v22(
    events[1].payload().subject(),
    events[0],
    events[1].payload().payload(),
  )
  let authorization = decode_initial_work_authorization_v22(
    r2.initial_authorization_ref,
    r2.initial_authorization_bytes,
  )
  let empty_effects = @effects.EffectsProjection::new(
    replay.workflow(),
    authorization.governance_policy.policy_ref(),
  )
  fold_root_bound_orchestration_v22(empty_effects, replay)
}
