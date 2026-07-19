///|
let recovery_activation_event_kind_v3 = "effect.recovery.activated.v3"

///|
let recovery_activation_record_magic_v3 = b"FLOW7/RECOVERY-PROTOCOL-ACTIVATED-V3/3.0.0"

///|
/// Generic provider contract declared by the host adapter. This is inert
/// configuration, not proof that a remote provider actually enforces it.
pub struct ProviderRecoveryProfileV3 {
  profile_id : String
  stable_create_key : Bool
  monotonic_fence : Bool
  authoritative_query : Bool
  authoritative_tombstone : Bool
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn ProviderRecoveryProfileV3::new(
  profile_id : String,
  stable_create_key : Bool,
  monotonic_fence : Bool,
  authoritative_query : Bool,
  authoritative_tombstone : Bool,
) -> ProviderRecoveryProfileV3 raise OrchestrationError {
  require_text(profile_id, "recovery_profile_v3_id")
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/PROVIDER-RECOVERY-PROFILE-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(profile_id)
  writer.byte(if stable_create_key { 1 } else { 0 })
  writer.byte(if monotonic_fence { 1 } else { 0 })
  writer.byte(if authoritative_query { 1 } else { 0 })
  writer.byte(if authoritative_tombstone { 1 } else { 0 })
  let canonical = writer.finish()
  {
    profile_id,
    stable_create_key,
    monotonic_fence,
    authoritative_query,
    authoritative_tombstone,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn ProviderRecoveryProfileV3::profile_id(
  self : ProviderRecoveryProfileV3,
) -> String {
  self.profile_id
}

///|
pub fn ProviderRecoveryProfileV3::supports_automatic_create(
  self : ProviderRecoveryProfileV3,
) -> Bool {
  self.stable_create_key && self.monotonic_fence
}

///|
pub fn ProviderRecoveryProfileV3::supports_authoritative_query(
  self : ProviderRecoveryProfileV3,
) -> Bool {
  self.authoritative_query
}

///|
pub fn ProviderRecoveryProfileV3::supports_authoritative_tombstone(
  self : ProviderRecoveryProfileV3,
) -> Bool {
  self.authoritative_tombstone
}

///|
pub fn ProviderRecoveryProfileV3::canonical_bytes(
  self : ProviderRecoveryProfileV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ProviderRecoveryProfileV3::digest(
  self : ProviderRecoveryProfileV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
fn recovery_profile_flag_v3(
  value : Byte,
  field : String,
) -> Bool raise OrchestrationError {
  match value {
    0 => false
    1 => true
    _ => raise MalformedInput(field~)
  }
}

///|
fn decode_provider_recovery_profile_v3(
  bytes : Bytes,
) -> ProviderRecoveryProfileV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/PROVIDER-RECOVERY-PROFILE-V3/3.0.0" {
    raise MalformedInput(field="recovery_profile_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="recovery_profile_v3", version~)
  }
  let profile_id = reader.read_string()
  let stable_create_key = recovery_profile_flag_v3(
    reader.read_byte(),
    "recovery_profile_v3_stable_key",
  )
  let monotonic_fence = recovery_profile_flag_v3(
    reader.read_byte(),
    "recovery_profile_v3_monotonic_fence",
  )
  let authoritative_query = recovery_profile_flag_v3(
    reader.read_byte(),
    "recovery_profile_v3_query",
  )
  let authoritative_tombstone = recovery_profile_flag_v3(
    reader.read_byte(),
    "recovery_profile_v3_tombstone",
  )
  reader.require_end()
  let profile = ProviderRecoveryProfileV3::new(
    profile_id, stable_create_key, monotonic_fence, authoritative_query, authoritative_tombstone,
  )
  if profile.canonical != bytes {
    raise DigestMismatch(field="recovery_profile_v3_noncanonical")
  }
  profile
}

///|
/// Durable capability-scoped activation. It is replay evidence only and never
/// a provider-call capability.
pub struct RecoveryProtocolActivatedV3 {
  activation_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  source_intent_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  capability_ref : @contracts.RecordRef
  capability_kind : String
  protocol_version : String
  profile : ProviderRecoveryProfileV3
  event_id : String
  command_idempotency_key : String
  activated_at : Int64
  expected_work_revision : Int64
  expected_work_head_digest : @contracts.ContentDigest
  expected_work_replay_digest : @contracts.ContentDigest
  governance_workflow : @contracts.RecordRef
  expected_governance_revision : Int64
  expected_governance_head_digest : @contracts.ContentDigest?
  expected_governance_replay_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn recovery_activation_signing_bytes_v3(
  activation_id : String,
  workflow : @contracts.RecordRef,
  source_intent_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  capability_ref : @contracts.RecordRef,
  capability_kind : String,
  profile : ProviderRecoveryProfileV3,
  event_id : String,
  command_idempotency_key : String,
  activated_at : Int64,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
  governance_workflow : @contracts.RecordRef,
  expected_governance_revision : Int64,
  expected_governance_head_digest : @contracts.ContentDigest?,
  expected_governance_replay_digest : @contracts.ContentDigest,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_activation_record_magic_v3)
  writer.string("3.0.0")
  writer.string(activation_id)
  write_ref(writer, workflow)
  write_ref(writer, source_intent_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, capability_ref)
  writer.string(capability_kind)
  writer.bytes(profile.canonical)
  writer.string(event_id)
  writer.string(command_idempotency_key)
  writer.int64(activated_at)
  writer.int64(expected_work_revision)
  writer.string(expected_work_head_digest.text())
  writer.string(expected_work_replay_digest.text())
  write_ref(writer, governance_workflow)
  writer.int64(expected_governance_revision)
  writer.optional_digest(expected_governance_head_digest)
  writer.string(expected_governance_replay_digest.text())
  write_evidence(writer, evidence)
  writer.finish()
}

///|
fn make_recovery_protocol_activated_v3(
  activation_id : String,
  workflow : @contracts.RecordRef,
  source_intent_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  capability_ref : @contracts.RecordRef,
  capability_kind : String,
  profile : ProviderRecoveryProfileV3,
  event_id : String,
  command_idempotency_key : String,
  activated_at : Int64,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
  governance_workflow : @contracts.RecordRef,
  expected_governance_revision : Int64,
  expected_governance_head_digest : @contracts.ContentDigest?,
  expected_governance_replay_digest : @contracts.ContentDigest,
  evidence : Array[@contracts.EvidenceRef],
) -> RecoveryProtocolActivatedV3 raise OrchestrationError {
  require_text(activation_id, "recovery_activation_v3_id")
  require_text(capability_kind, "recovery_activation_v3_capability_kind")
  require_text(event_id, "recovery_activation_v3_event_id")
  require_text(command_idempotency_key, "recovery_activation_v3_command_key")
  if activated_at < 0L ||
    expected_work_revision < 0L ||
    expected_governance_revision < 0L ||
    workflow == governance_workflow {
    raise MalformedInput(field="recovery_activation_v3_bounds")
  }
  let canonical = recovery_activation_signing_bytes_v3(
    activation_id, workflow, source_intent_ref, governed_subject, capability_ref,
    capability_kind, profile, event_id, command_idempotency_key, activated_at, expected_work_revision,
    expected_work_head_digest, expected_work_replay_digest, governance_workflow,
    expected_governance_revision, expected_governance_head_digest, expected_governance_replay_digest,
    evidence,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    activation_ref: self_ref_v3(
      "orchestration-recovery-protocol-activation-v3", activation_id, digest,
    ),
    workflow,
    source_intent_ref,
    governed_subject,
    capability_ref,
    capability_kind,
    protocol_version: "3.0.0",
    profile,
    event_id,
    command_idempotency_key,
    activated_at,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    governance_workflow,
    expected_governance_revision,
    expected_governance_head_digest,
    expected_governance_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    canonical,
    digest,
  }
}

///|
fn decode_recovery_protocol_activated_v3(
  bytes : Bytes,
) -> RecoveryProtocolActivatedV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_activation_record_magic_v3 {
    raise MalformedInput(field="recovery_activation_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="recovery_activation_v3", version~)
  }
  let activation_id = reader.read_string()
  let workflow = reader.read_ref()
  let source_intent_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let capability_ref = reader.read_ref()
  let capability_kind = reader.read_string()
  let profile = decode_provider_recovery_profile_v3(reader.read_bytes())
  let event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let activated_at = reader.read_int64()
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  let governance_workflow = reader.read_ref()
  let expected_governance_revision = reader.read_int64()
  let expected_governance_head_digest = reader.read_optional_digest()
  let expected_governance_replay_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  reader.require_end()
  let activation = make_recovery_protocol_activated_v3(
    activation_id, workflow, source_intent_ref, governed_subject, capability_ref,
    capability_kind, profile, event_id, command_idempotency_key, activated_at, expected_work_revision,
    expected_work_head_digest, expected_work_replay_digest, governance_workflow,
    expected_governance_revision, expected_governance_head_digest, expected_governance_replay_digest,
    evidence,
  )
  if activation.canonical != bytes {
    raise DigestMismatch(field="recovery_activation_v3_noncanonical")
  }
  activation
}

///|
fn bytes_have_recovery_activation_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == recovery_activation_record_magic_v3
  }
}

///|
fn recovery_activation_event_v3(
  current : CurrentGovernedClosedLoopProjectionV2,
  activation : RecoveryProtocolActivatedV3,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let evidence = [ for value in activation.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    activation.event_id,
    recovery_activation_event_kind_v3,
    activation.governed_subject,
    phase1b_effect_schema_v22(recovery_activation_event_kind_v3),
    activation.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=activation.workflow,
    correlation_ref=activation.workflow.id(),
    causation_ref=activation.capability_ref.id(),
    idempotency_ref=activation.activation_ref.id(),
    previous_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="recovery_activation_v3_envelope")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    activation.workflow,
    activation.event_id,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    activation.activation_ref.id(),
    envelope,
    evidence,
    previous_event_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="recovery_activation_v3_event")
  }
}

///|
fn require_recovery_activation_event_binding_v3(
  activation : RecoveryProtocolActivatedV3,
  event : @storage.WorkflowEvent,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.workflow() != activation.workflow ||
    event.event_ref().id() != activation.event_id ||
    event.revision() != activation.expected_work_revision + 1L ||
    event.sequence() != event.revision() ||
    event.previous_event_digest() != Some(activation.expected_work_head_digest) ||
    event.idempotency_key() != activation.activation_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != recovery_activation_event_kind_v3 ||
    envelope.subject() != activation.governed_subject ||
    envelope.run_ref() != Some(activation.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) ||
    envelope.correlation_ref() != Some(activation.workflow.id()) ||
    envelope.causation_ref() != Some(activation.capability_ref.id()) ||
    envelope.idempotency_ref() != Some(activation.activation_ref.id()) ||
    envelope.previous_digest() != Some(activation.expected_work_head_digest) ||
    envelope.schema() !=
    phase1b_effect_schema_v22(recovery_activation_event_kind_v3) ||
    envelope.payload() != activation.canonical ||
    !same_evidence(event.evidence(), activation.evidence) ||
    !same_evidence(envelope.evidence(), activation.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="recovery_activation_v3_event_binding")
  }
}

///|
fn require_recovery_activation_transaction_v3(
  activation : RecoveryProtocolActivatedV3,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let matching = replay
    .committed_batches()
    .filter(batch => batch.event_refs().any(value => value == event.event_ref()))
  if matching.length() != 1 {
    raise ReplayBindingViolation(field="recovery_activation_v3_commit_boundary")
  }
  let boundary = matching[0]
  if boundary.expected_revision() != activation.expected_work_revision ||
    boundary.command_idempotency_key() != activation.command_idempotency_key ||
    boundary.event_refs().length() != 1 ||
    boundary.event_refs()[0] != event.event_ref() ||
    !boundary.intent_refs().is_empty() ||
    boundary.guards().length() != 1 {
    raise ReplayBindingViolation(field="recovery_activation_v3_commit_shape")
  }
  let head_guard = boundary.guards()[0]
  if head_guard.workflow() != activation.governance_workflow ||
    head_guard.expected_revision() != activation.expected_governance_revision ||
    head_guard.expected_head_digest() !=
    activation.expected_governance_head_digest ||
    head_guard.expected_replay_digest() !=
    activation.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="recovery_activation_v3_commit_guard")
  }
}

///|
fn require_recovery_activation_prefix_v3(
  empty : @effects.EffectsProjection,
  activation : RecoveryProtocolActivatedV3,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let work_prefix = verified_prefix_v3(
    work_replay,
    activation.expected_work_revision,
    "recovery_activation_v3_work_prefix",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    activation.expected_governance_revision,
    "recovery_activation_v3_governance_prefix",
  )
  if work_prefix.head().last_event_digest() !=
    Some(activation.expected_work_head_digest) ||
    work_prefix.replay_digest() != activation.expected_work_replay_digest ||
    governance_prefix.workflow() != activation.governance_workflow ||
    governance_prefix.head().last_event_digest() !=
    activation.expected_governance_head_digest ||
    governance_prefix.replay_digest() !=
    activation.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="recovery_activation_v3_prefix")
  }
  let prefix = fold_governed_closed_loop_v2(
    empty, work_prefix, governance_prefix,
  )
  let target = prefix.work.effects.strict_recovery_target_v3(
    activation.source_intent_ref,
  ) catch {
    _ => raise ReplayBindingViolation(field="recovery_activation_v3_effects")
  }
  if target.capability_ref() != activation.capability_ref ||
    target.capability_kind() != activation.capability_kind ||
    target.governed_subject() != activation.governed_subject ||
    !same_evidence(target.permitted_evidence(), activation.evidence) {
    raise ReplayBindingViolation(field="recovery_activation_v3_capability")
  }
  if !recovery_activation_capability_is_clean_v3(
      prefix.work.effects,
      activation.capability_ref,
      activation.capability_kind,
    ) {
    raise ReplayBindingViolation(
      field="recovery_activation_v3_dirty_capability",
    )
  }
}

///|
/// A capability may cross the V2/V3 boundary only while every intent already
/// committed for that exact capability is still dispatch eligible. Identity
/// and state are both derived from the same authoritative strict replay.
fn recovery_activation_capability_is_clean_v3(
  effects : @effects.EffectsProjection,
  capability_ref : @contracts.RecordRef,
  capability_kind : String,
) -> Bool raise OrchestrationError {
  let identities = effects.strict_recovery_intent_catalog_v3() catch {
    _ => raise ReplayBindingViolation(field="recovery_activation_v3_catalog")
  }
  for identity in identities {
    if identity.capability_ref() == capability_ref &&
      identity.capability_kind() == capability_kind {
      let state = effects.strict_intent_state_v2(identity.intent_ref()) catch {
        _ =>
          raise ReplayBindingViolation(
            field="recovery_activation_v3_intent_state",
          )
      }
      if state.state() != @effects.DurableIntentDispatchEligible {
        return false
      }
    }
  }
  true
}

///|
priv struct RecoveryActivationCandidateV3 {
  activation : RecoveryProtocolActivatedV3
  request : @storage.CommitRequest
  guarded_request : @storage.GuardedCommitRequest
}

///|
pub(all) enum RecoveryProtocolActivationResultV3 {
  RecoveryProtocolActivationFreshV3
  RecoveryProtocolActivationAlreadyCommittedV3
  RecoveryProtocolActivationRaceLostV3
  RecoveryProtocolActivationStaleGovernanceV3
} derive(Eq, Debug)

///|
fn prepare_recovery_activation_v3(
  joint : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
  profile : ProviderRecoveryProfileV3,
  activation_id : String,
  event_id : String,
  command_idempotency_key : String,
  activated_at : Int64,
) -> RecoveryActivationCandidateV3 raise OrchestrationError {
  let current = joint.current
  ignore(current.open_work_authority())
  let target = current.work.effects.strict_recovery_target_v3(intent_ref) catch {
    _ => raise ReplayBindingViolation(field="recovery_activation_v3_target")
  }
  if !recovery_activation_capability_is_clean_v3(
      current.work.effects,
      target.capability_ref(),
      target.capability_kind(),
    ) {
    raise RecoveryViolation(field="recovery_activation_v3_dirty_capability")
  }
  let activation = make_recovery_protocol_activated_v3(
    activation_id,
    joint.work_replay.workflow(),
    intent_ref,
    target.governed_subject(),
    target.capability_ref(),
    target.capability_kind(),
    profile,
    event_id,
    command_idempotency_key,
    activated_at,
    current.work_revision,
    current.work_head_digest,
    current.work_replay_digest,
    current.root_binding.governance_stream_ref(),
    current.governance_revision,
    current.governance_head_digest,
    current.governance_replay_digest,
    [
      for value in target.permitted_evidence() => value
    ],
  )
  let event = recovery_activation_event_v3(current, activation)
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    activation.workflow,
    current.work_revision,
    command_idempotency_key,
    [event],
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="recovery_activation_v3_request")
  }
  {
    activation,
    request,
    guarded_request: guarded_lifecycle_commit_request_v22(current, request),
  }
}

///|
/// Publish one inert, capability-scoped Phase-2 activation. The caller must
/// refold before dispatch; this result cannot be converted into call authority.
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] activate_recovery_protocol_v3(
  store : S,
  current : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
  profile : ProviderRecoveryProfileV3,
  activation_id : String,
  event_id : String,
  command_idempotency_key : String,
  activated_at : Int64,
) -> RecoveryProtocolActivationResultV3 raise {
  let target = current.current.work.effects.strict_recovery_target_v3(
    intent_ref,
  ) catch {
    _ => raise ReplayBindingViolation(field="recovery_activation_v3_target")
  }
  match
    current.activation_for_capability_v3(
      target.capability_ref(),
      target.capability_kind(),
    ) {
    Some(existing) => {
      if existing.profile.digest != profile.digest {
        raise RecoveryViolation(field="recovery_activation_v3_profile_fork")
      }
      return RecoveryProtocolActivationAlreadyCommittedV3
    }
    None => ()
  }
  let candidate = prepare_recovery_activation_v3(
    current, intent_ref, profile, activation_id, event_id, command_idempotency_key,
    activated_at,
  )
  require_phase2_governance_guard_profile_v3(store, candidate.guarded_request)
  try {
    match store.classified_guarded_commit(candidate.guarded_request) {
      @storage.FreshlyApplied(_) => RecoveryProtocolActivationFreshV3
      @storage.AlreadyCommitted(_) =>
        RecoveryProtocolActivationAlreadyCommittedV3
      @storage.GuardRejected(_) => RecoveryProtocolActivationStaleGovernanceV3
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) =>
      RecoveryProtocolActivationRaceLostV3
    error => raise error
  }
}

///|
pub fn RecoveryProtocolActivatedV3::record_ref(
  self : RecoveryProtocolActivatedV3,
) -> @contracts.RecordRef {
  self.activation_ref
}

///|
pub fn RecoveryProtocolActivatedV3::capability_ref(
  self : RecoveryProtocolActivatedV3,
) -> @contracts.RecordRef {
  self.capability_ref
}

///|
pub fn RecoveryProtocolActivatedV3::capability_kind(
  self : RecoveryProtocolActivatedV3,
) -> String {
  self.capability_kind
}

///|
pub fn RecoveryProtocolActivatedV3::profile(
  self : RecoveryProtocolActivatedV3,
) -> ProviderRecoveryProfileV3 {
  self.profile
}

///|
pub fn RecoveryProtocolActivatedV3::canonical_bytes(
  self : RecoveryProtocolActivatedV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryProtocolActivatedV3::digest(
  self : RecoveryProtocolActivatedV3,
) -> @contracts.ContentDigest {
  self.digest
}
