///|
let dispatch_claim_event_kind_v3 = "effect.dispatch.claimed.v3"

///|
let dispatch_claim_record_magic_v3 = b"FLOW7/DISPATCH-CLAIM-RECORD-V3/3.0.0"

///|
let dispatch_claim_transport_contract_id_v3 = "closed-loop.effects"

///|
let dispatch_claim_transport_producer_id_v3 = "effects-protocol"

///|
fn self_ref_v3(
  kind : String,
  id : String,
  digest : @contracts.ContentDigest,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(kind, id, "3.0.0", digest.text())
}

///|
/// Immutable dispatch-ownership fact. It is deliberately inert: decoding or
/// constructing this package-private value grants no provider-call authority.
pub struct DispatchClaimRecordV3 {
  claim_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  outbox_ref : @contracts.RecordRef
  provider_operation : @contracts.WireEnvelope
  external_idempotency_key : String
  capability_ref : @contracts.RecordRef
  capability_kind : String
  activation_ref : @contracts.RecordRef
  activation_digest : @contracts.ContentDigest
  provider_profile_digest : @contracts.ContentDigest
  dispatch_event_id : String
  invocation_event_id : String
  command_idempotency_key : String
  owner : @contracts.RecordRef
  lease_receipt_ref : @contracts.RecordRef
  lease_receipt_digest : @contracts.ContentDigest
  lease_claimed_ref : @contracts.RecordRef
  lease_claimed_digest : @contracts.ContentDigest
  lease_epoch : Int64
  fencing_token : Int64
  claim_ordinal : Int64
  claimed_at : Int64
  expires_at : Int64
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
fn dispatch_claim_signing_bytes_v3(
  claim_id : String,
  workflow : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef,
  attempt_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  outbox_ref : @contracts.RecordRef,
  provider_operation : @contracts.WireEnvelope,
  external_idempotency_key : String,
  capability_ref : @contracts.RecordRef,
  capability_kind : String,
  activation_ref : @contracts.RecordRef,
  activation_digest : @contracts.ContentDigest,
  provider_profile_digest : @contracts.ContentDigest,
  dispatch_event_id : String,
  invocation_event_id : String,
  command_idempotency_key : String,
  owner : @contracts.RecordRef,
  lease_receipt_ref : @contracts.RecordRef,
  lease_receipt_digest : @contracts.ContentDigest,
  lease_claimed_ref : @contracts.RecordRef,
  lease_claimed_digest : @contracts.ContentDigest,
  lease_epoch : Int64,
  fencing_token : Int64,
  claim_ordinal : Int64,
  claimed_at : Int64,
  expires_at : Int64,
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
  writer.bytes(dispatch_claim_record_magic_v3)
  writer.string("3.0.0")
  writer.string(claim_id)
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, attempt_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, outbox_ref)
  writer.bytes(@contracts.encode_wire_envelope(provider_operation))
  writer.string(external_idempotency_key)
  write_ref(writer, capability_ref)
  writer.string(capability_kind)
  write_ref(writer, activation_ref)
  writer.string(activation_digest.text())
  writer.string(provider_profile_digest.text())
  writer.string(dispatch_event_id)
  writer.string(invocation_event_id)
  writer.string(command_idempotency_key)
  write_ref(writer, owner)
  write_ref(writer, lease_receipt_ref)
  writer.string(lease_receipt_digest.text())
  write_ref(writer, lease_claimed_ref)
  writer.string(lease_claimed_digest.text())
  writer.int64(lease_epoch)
  writer.int64(fencing_token)
  writer.int64(claim_ordinal)
  writer.int64(claimed_at)
  writer.int64(expires_at)
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
fn make_dispatch_claim_record_v3(
  claim_id : String,
  workflow : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef,
  attempt_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  outbox_ref : @contracts.RecordRef,
  provider_operation : @contracts.WireEnvelope,
  external_idempotency_key : String,
  capability_ref : @contracts.RecordRef,
  capability_kind : String,
  activation_ref : @contracts.RecordRef,
  activation_digest : @contracts.ContentDigest,
  provider_profile_digest : @contracts.ContentDigest,
  dispatch_event_id : String,
  invocation_event_id : String,
  command_idempotency_key : String,
  owner : @contracts.RecordRef,
  lease_receipt_ref : @contracts.RecordRef,
  lease_receipt_digest : @contracts.ContentDigest,
  lease_claimed_ref : @contracts.RecordRef,
  lease_claimed_digest : @contracts.ContentDigest,
  lease_epoch : Int64,
  fencing_token : Int64,
  claim_ordinal : Int64,
  claimed_at : Int64,
  expires_at : Int64,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
  governance_workflow : @contracts.RecordRef,
  expected_governance_revision : Int64,
  expected_governance_head_digest : @contracts.ContentDigest?,
  expected_governance_replay_digest : @contracts.ContentDigest,
  evidence : Array[@contracts.EvidenceRef],
) -> DispatchClaimRecordV3 raise OrchestrationError {
  require_text(claim_id, "dispatch_claim_v3_id")
  require_text(external_idempotency_key, "dispatch_claim_v3_external_key")
  require_text(capability_kind, "dispatch_claim_v3_capability_kind")
  require_text(dispatch_event_id, "dispatch_claim_v3_event_id")
  require_text(invocation_event_id, "dispatch_invocation_v3_event_id")
  require_text(command_idempotency_key, "dispatch_claim_v3_command_key")
  if lease_epoch < 0L ||
    fencing_token < 0L ||
    claim_ordinal <= 0L ||
    claimed_at < 0L ||
    expires_at <= claimed_at ||
    expected_work_revision < 0L ||
    expected_governance_revision < 0L {
    raise MalformedInput(field="dispatch_claim_v3_bounds")
  }
  if workflow == governance_workflow {
    raise ReplayBindingViolation(field="dispatch_claim_v3_workflow_separation")
  }
  let canonical = dispatch_claim_signing_bytes_v3(
    claim_id, workflow, intent_ref, attempt_ref, governed_subject, outbox_ref, provider_operation,
    external_idempotency_key, capability_ref, capability_kind, activation_ref, activation_digest,
    provider_profile_digest, dispatch_event_id, invocation_event_id, command_idempotency_key,
    owner, lease_receipt_ref, lease_receipt_digest, lease_claimed_ref, lease_claimed_digest,
    lease_epoch, fencing_token, claim_ordinal, claimed_at, expires_at, expected_work_revision,
    expected_work_head_digest, expected_work_replay_digest, governance_workflow,
    expected_governance_revision, expected_governance_head_digest, expected_governance_replay_digest,
    evidence,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    claim_ref: self_ref_v3("orchestration-dispatch-claim-v3", claim_id, digest),
    workflow,
    intent_ref,
    attempt_ref,
    governed_subject,
    outbox_ref,
    provider_operation,
    external_idempotency_key,
    capability_ref,
    capability_kind,
    activation_ref,
    activation_digest,
    provider_profile_digest,
    dispatch_event_id,
    invocation_event_id,
    command_idempotency_key,
    owner,
    lease_receipt_ref,
    lease_receipt_digest,
    lease_claimed_ref,
    lease_claimed_digest,
    lease_epoch,
    fencing_token,
    claim_ordinal,
    claimed_at,
    expires_at,
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
fn decode_dispatch_claim_record_v3(
  bytes : Bytes,
) -> DispatchClaimRecordV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != dispatch_claim_record_magic_v3 {
    raise MalformedInput(field="dispatch_claim_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="dispatch_claim_v3", version~)
  }
  let claim_id = reader.read_string()
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let attempt_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let outbox_ref = reader.read_ref()
  let provider_operation = @contracts.decode_wire_envelope(reader.read_bytes()) catch {
    _ => raise MalformedInput(field="dispatch_claim_v3_provider_operation")
  }
  let external_idempotency_key = reader.read_string()
  let capability_ref = reader.read_ref()
  let capability_kind = reader.read_string()
  let activation_ref = reader.read_ref()
  let activation_digest = reader.read_digest()
  let provider_profile_digest = reader.read_digest()
  let dispatch_event_id = reader.read_string()
  let invocation_event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let owner = reader.read_ref()
  let lease_receipt_ref = reader.read_ref()
  let lease_receipt_digest = reader.read_digest()
  let lease_claimed_ref = reader.read_ref()
  let lease_claimed_digest = reader.read_digest()
  let lease_epoch = reader.read_int64()
  let fencing_token = reader.read_int64()
  let claim_ordinal = reader.read_int64()
  let claimed_at = reader.read_int64()
  let expires_at = reader.read_int64()
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  let governance_workflow = reader.read_ref()
  let expected_governance_revision = reader.read_int64()
  let expected_governance_head_digest = reader.read_optional_digest()
  let expected_governance_replay_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  reader.require_end()
  let value = make_dispatch_claim_record_v3(
    claim_id, workflow, intent_ref, attempt_ref, governed_subject, outbox_ref, provider_operation,
    external_idempotency_key, capability_ref, capability_kind, activation_ref, activation_digest,
    provider_profile_digest, dispatch_event_id, invocation_event_id, command_idempotency_key,
    owner, lease_receipt_ref, lease_receipt_digest, lease_claimed_ref, lease_claimed_digest,
    lease_epoch, fencing_token, claim_ordinal, claimed_at, expires_at, expected_work_revision,
    expected_work_head_digest, expected_work_replay_digest, governance_workflow,
    expected_governance_revision, expected_governance_head_digest, expected_governance_replay_digest,
    evidence,
  )
  if value.canonical != bytes {
    raise DigestMismatch(field="dispatch_claim_v3_noncanonical")
  }
  value
}

///|
fn bytes_have_dispatch_claim_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == dispatch_claim_record_magic_v3
  }
}

///|
fn bytes_have_dispatch_invocation_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == invocation_started_record_magic_v3
  }
}

///|
fn bytes_have_recovery_retry_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic =>
      magic == effect_retry_policy_bound_magic_v3 ||
      magic == recovery_retry_intent_magic_v3 ||
      magic == recovery_retry_scheduled_magic_v3
  }
}

///|
fn bytes_have_recovery_terminal_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == recovery_work_terminal_magic_v3
  }
}

///|
fn require_dispatch_claim_event_binding_v3(
  claim : DispatchClaimRecordV3,
  event : @storage.WorkflowEvent,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.workflow() != claim.workflow ||
    event.event_ref().id() != claim.dispatch_event_id ||
    event.revision() != claim.expected_work_revision + 1L ||
    event.sequence() != event.revision() ||
    event.previous_event_digest() != Some(claim.expected_work_head_digest) ||
    event.idempotency_key() != claim.claim_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != dispatch_claim_event_kind_v3 ||
    envelope.subject() != claim.governed_subject ||
    envelope.run_ref() != Some(claim.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() != Some(claim.attempt_ref) ||
    envelope.correlation_ref() != Some(claim.workflow.id()) ||
    envelope.causation_ref() != Some(claim.intent_ref.id()) ||
    envelope.idempotency_ref() != Some(claim.claim_ref.id()) ||
    envelope.previous_digest() != Some(claim.expected_work_head_digest) ||
    envelope.schema() != phase1b_effect_schema_v22(dispatch_claim_event_kind_v3) ||
    envelope.payload() != claim.canonical ||
    !same_evidence(event.evidence(), claim.evidence) ||
    !same_evidence(envelope.evidence(), claim.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="dispatch_claim_v3_event_binding")
  }
}

///|
/// Prove that the claim was published by the exact guarded transaction bound
/// into its own canonical bytes. Historical prefix validity alone is
/// insufficient because the same event bytes could otherwise be replayed
/// later under a different governance head or command key.
fn require_dispatch_claim_transaction_v3(
  claim : DispatchClaimRecordV3,
  event : @storage.WorkflowEvent,
  work_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  guard work_replay
    .events()
    .search_by(candidate => {
      candidate.event_ref().id() == claim.invocation_event_id
    })
    is Some(start_index) else {
    raise ReplayBindingViolation(field="dispatch_invocation_v3_missing")
  }
  let start_event = work_replay.events()[start_index]
  let started = decode_dispatch_invocation_started_v3(
    start_event.payload().payload(),
  )
  require_dispatch_invocation_event_binding_v3(started, start_event, claim)
  if start_event.previous_event_digest() != Some(event.event_ref().digest()) ||
    start_event.payload().previous_digest() != Some(event.event_ref().digest()) {
    raise ReplayBindingViolation(field="dispatch_invocation_v3_chain")
  }
  let matching = work_replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().any(event_ref => event_ref == event.event_ref())
    })
  if matching.length() != 1 {
    raise ReplayBindingViolation(field="dispatch_claim_v3_commit_boundary")
  }
  let boundary = matching[0]
  if boundary.expected_revision() != claim.expected_work_revision ||
    boundary.command_idempotency_key() != claim.command_idempotency_key ||
    boundary.event_refs().length() != 2 ||
    boundary.event_refs()[0] != event.event_ref() ||
    boundary.event_refs()[1] != start_event.event_ref() ||
    boundary.intent_refs().length() != 0 {
    raise ReplayBindingViolation(field="dispatch_claim_v3_commit_shape")
  }
  let guards = boundary.guards()
  if guards.length() != 1 {
    raise ReplayBindingViolation(field="dispatch_claim_v3_commit_guards")
  }
  let head_guard = guards[0]
  if head_guard.workflow() != claim.governance_workflow ||
    head_guard.expected_revision() != claim.expected_governance_revision ||
    head_guard.expected_head_digest() != claim.expected_governance_head_digest ||
    head_guard.expected_replay_digest() !=
    claim.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="dispatch_claim_v3_commit_guard_binding")
  }
}

///|
/// Shared closed-replay accounting hook. A known claim wrapper is consumed
/// exactly once only after strict decode/re-canonicalization and transport
/// binding. Claim bytes under any other wrapper fail closed.
fn recovery_event_consumption_v3(
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Int raise OrchestrationError {
  let kind = event.payload().envelope_kind()
  let payload = event.payload().payload()
  match kind {
    value if value == recovery_activation_event_kind_v3 => {
      let activation = decode_recovery_protocol_activated_v3(payload)
      require_recovery_activation_event_binding_v3(activation, event)
      require_recovery_activation_transaction_v3(activation, event, replay)
      1
    }
    value if value == dispatch_claim_event_kind_v3 => {
      let claim = decode_dispatch_claim_record_v3(payload)
      require_dispatch_claim_event_binding_v3(claim, event)
      require_dispatch_claim_transaction_v3(claim, event, replay)
      1
    }
    value if value == invocation_started_event_kind_v3 => {
      let started = decode_dispatch_invocation_started_v3(payload)
      guard replay
        .events()
        .search_by(candidate => {
          candidate.event_ref().id() == started.claim_event_id
        })
        is Some(claim_index) else {
        raise ReplayBindingViolation(field="dispatch_invocation_v3_claim")
      }
      let claim_event = replay.events()[claim_index]
      let claim = decode_dispatch_claim_record_v3(
        claim_event.payload().payload(),
      )
      require_dispatch_claim_event_binding_v3(claim, claim_event)
      require_dispatch_invocation_event_binding_v3(started, event, claim)
      require_dispatch_claim_transaction_v3(claim, claim_event, replay)
      1
    }
    value if value == dispatch_observation_event_kind_v3 => {
      let observation = decode_dispatch_observation_record_v3(payload)
      require_dispatch_observation_binding_v3(observation, event, replay)
      1
    }
    value if value == recovery_policy_bound_event_kind_v3 => {
      let policy = decode_recovery_policy_bound_v3(payload)
      require_recovery_policy_bound_binding_v3(policy, event, replay)
      1
    }
    value if value == reconciliation_claim_event_kind_v3 => {
      let claim = decode_reconciliation_claim_record_v3(payload)
      require_reconciliation_claim_event_binding_v3(claim, event)
      require_reconciliation_claim_transaction_v3(claim, event, replay)
      1
    }
    value if value == reconciliation_query_started_event_kind_v3 => {
      let started = decode_reconciliation_query_started_v3(payload)
      guard first(replay.events(), candidate => {
          candidate.event_ref().id() == started.claim_event_id &&
          candidate.payload().envelope_kind() ==
          reconciliation_claim_event_kind_v3
        })
        is Some(claim_event) else {
        raise ReplayBindingViolation(
          field="reconciliation_query_started_v3_claim",
        )
      }
      let claim = decode_reconciliation_claim_record_v3(
        claim_event.payload().payload(),
      )
      require_reconciliation_claim_event_binding_v3(claim, claim_event)
      require_reconciliation_query_started_binding_v3(started, event, claim)
      require_reconciliation_claim_transaction_v3(claim, claim_event, replay)
      1
    }
    value if value == reconciliation_result_event_kind_v3 => {
      let result = decode_reconciliation_result_record_v3(payload)
      require_reconciliation_result_binding_v3(result, event, replay)
      1
    }
    value if value == recovery_backoff_event_kind_v3 => {
      let backoff = decode_recovery_backoff_scheduled_v3(payload)
      require_recovery_backoff_binding_v3(backoff, event, replay)
      1
    }
    value if value == recovery_automation_stopped_event_kind_v3 => {
      let stopped = decode_recovery_automation_stopped_v3(payload)
      require_recovery_automation_stopped_binding_v3(stopped, event, replay)
      1
    }
    value if value == effect_retry_policy_bound_event_kind_v3 ||
      value == recovery_retry_intent_event_kind_v3 ||
      value == recovery_retry_scheduled_event_kind_v3 =>
      recovery_retry_event_consumption_v3(event, replay)
    value if value == recovery_work_terminal_event_kind_v3 =>
      recovery_terminal_event_consumption_v3(event, replay)
    value if value == manual_intervention_hold_event_kind_v3 ||
      value == manual_intervention_resume_event_kind_v3 =>
      manual_intervention_event_consumption_v3(event, replay)
    value if value == quarantine_disposition_event_kind_v1 =>
      quarantine_disposition_event_consumption_v1(event, replay)
    value if value == recovery_callback_evidence_event_kind_v3 =>
      raise RecoveryViolation(field="callback_evidence_on_work_stream_v3")
    _ => {
      if bytes_have_dispatch_claim_magic_v3(payload) ||
        bytes_have_dispatch_invocation_magic_v3(payload) ||
        bytes_have_recovery_activation_magic_v3(payload) ||
        bytes_have_dispatch_observation_magic_v3(payload) ||
        bytes_have_recovery_policy_bound_magic_v3(payload) ||
        bytes_have_reconciliation_claim_magic_v3(payload) ||
        bytes_have_reconciliation_query_started_magic_v3(payload) ||
        bytes_have_reconciliation_result_magic_v3(payload) ||
        bytes_have_recovery_backoff_magic_v3(payload) ||
        bytes_have_recovery_automation_stopped_magic_v3(payload) ||
        bytes_have_recovery_retry_magic_v3(payload) ||
        bytes_have_recovery_terminal_magic_v3(payload) ||
        bytes_have_manual_intervention_magic_v3(payload) ||
        bytes_have_quarantine_disposition_magic_v1(payload) ||
        bytes_have_recovery_callback_record_magic_v3(payload) {
        raise ReplayBindingViolation(field="recovery_v3_unknown_wrapper")
      }
      0
    }
  }
}

///|
fn verified_prefix_v3(
  replay : @storage.ReplayResult,
  revision : Int64,
  field : String,
) -> @storage.ReplayResult raise OrchestrationError {
  replay.verified_prefix(revision) catch {
    _ => raise ReplayBindingViolation(field~)
  }
}

///|
fn require_dispatch_claim_prefix_v3(
  empty : @effects.EffectsProjection,
  claim : DispatchClaimRecordV3,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let work_prefix = verified_prefix_v3(
    work_replay,
    claim.expected_work_revision,
    "dispatch_claim_v3_work_prefix",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    claim.expected_governance_revision,
    "dispatch_claim_v3_governance_prefix",
  )
  if work_prefix.head().last_event_digest() !=
    Some(claim.expected_work_head_digest) ||
    work_prefix.replay_digest() != claim.expected_work_replay_digest ||
    governance_prefix.workflow() != claim.governance_workflow ||
    governance_prefix.head().last_event_digest() !=
    claim.expected_governance_head_digest ||
    governance_prefix.replay_digest() != claim.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="dispatch_claim_v3_prefix_digest")
  }
  let prefix = fold_governed_closed_loop_v2(
    empty, work_prefix, governance_prefix,
  )
  let recovery_prefix = fold_governed_recovery_v3(
    empty, work_prefix, governance_prefix,
  )
  let target = recovery_prefix.dispatch_source_target_v3(claim.intent_ref)
  if target.intent_ref != claim.intent_ref ||
    target.attempt_ref != claim.attempt_ref ||
    target.governed_subject != claim.governed_subject ||
    target.outbox_ref != claim.outbox_ref ||
    target.external_idempotency_key != claim.external_idempotency_key ||
    target.provider_operation != claim.provider_operation ||
    target.capability_ref != claim.capability_ref ||
    target.capability_kind != claim.capability_kind ||
    !same_evidence(target.permitted_evidence, claim.evidence) ||
    target.authoritative_replay_digest != claim.expected_work_replay_digest {
    raise ReplayBindingViolation(field="dispatch_claim_v3_intent_binding")
  }
  guard prefix.committed_lease_authority_receipt_v2() is Some(lease) else {
    raise ReplayBindingViolation(field="dispatch_claim_v3_lease_missing")
  }
  lease.validate_governed_current_v2(prefix, claim.claimed_at)
  if lease.receipt_ref() != claim.lease_receipt_ref ||
    lease.digest() != claim.lease_receipt_digest ||
    lease.lease_claimed_ref() != claim.lease_claimed_ref ||
    lease.lease_claimed_digest() != claim.lease_claimed_digest ||
    lease.owner() != claim.owner ||
    lease.epoch() != claim.lease_epoch ||
    lease.fencing_token() != claim.fencing_token ||
    claim.expires_at > lease.expires_at() {
    raise ReplayBindingViolation(field="dispatch_claim_v3_lease_binding")
  }
}

///|
/// Opaque joint work+governance+recovery view. It is constructed only by one
/// fold over the exact two replays, preventing a stale recovery snapshot from
/// being paired with a newer governed projection.
pub struct CurrentGovernedRecoveryProjectionV3 {
  empty_effects : @effects.EffectsProjection
  current : CurrentGovernedClosedLoopProjectionV2
  work_replay : @storage.ReplayResult
  governance_replay : @storage.ReplayResult
  activations : ReadOnlyArray[RecoveryProtocolActivatedV3]
  claims : ReadOnlyArray[DispatchClaimRecordV3]
  invocation_starts : ReadOnlyArray[DispatchInvocationStartedV3]
  observations : ReadOnlyArray[DispatchObservationRecordV3]
  recovery_policies : ReadOnlyArray[RecoveryPolicyBoundV3]
  reconciliation_claims : ReadOnlyArray[ReconciliationClaimRecordV3]
  reconciliation_query_starts : ReadOnlyArray[ReconciliationQueryStartedV3]
  reconciliation_results : ReadOnlyArray[ReconciliationResultRecordV3]
  recovery_backoffs : ReadOnlyArray[RecoveryBackoffScheduledV3]
  recovery_automation_stops : ReadOnlyArray[RecoveryAutomationStoppedV3]
  state_digest : @contracts.ContentDigest
}

///|
pub fn fold_governed_recovery_v3(
  empty : @effects.EffectsProjection,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> CurrentGovernedRecoveryProjectionV3 raise OrchestrationError {
  // Transaction origin is storage provenance, so validate it before domain
  // folding. This ensures a claim replayed under a substituted guard fails for
  // its stored boundary even when that substituted governance stream is itself
  // semantically invalid for the current V2 policy.
  let activations : Array[RecoveryProtocolActivatedV3] = []
  let claims : Array[DispatchClaimRecordV3] = []
  let invocation_starts : Array[DispatchInvocationStartedV3] = []
  let observations : Array[DispatchObservationRecordV3] = []
  let recovery_policies : Array[RecoveryPolicyBoundV3] = []
  let reconciliation_claims : Array[ReconciliationClaimRecordV3] = []
  let reconciliation_query_starts : Array[ReconciliationQueryStartedV3] = []
  let reconciliation_results : Array[ReconciliationResultRecordV3] = []
  let recovery_backoffs : Array[RecoveryBackoffScheduledV3] = []
  let recovery_automation_stops : Array[RecoveryAutomationStoppedV3] = []
  let mut recovery_terminal_seen = false
  for event in work_replay.events() {
    if recovery_terminal_seen {
      raise RecoveryViolation(field="event_after_recovery_terminal_v3")
    }
    let kind = event.payload().envelope_kind()
    let payload = event.payload().payload()
    let recovery_count = recovery_event_consumption_v3(event, work_replay)
    match kind {
      value if value == recovery_activation_event_kind_v3 => {
        let activation = decode_recovery_protocol_activated_v3(payload)
        if activations.any(prior => {
            prior.activation_ref == activation.activation_ref ||
            (
              prior.capability_ref == activation.capability_ref &&
              prior.capability_kind == activation.capability_kind
            )
          }) {
          raise RecoveryViolation(field="recovery_activation_v3_duplicate")
        }
        activations.push(activation)
      }
      value if value == dispatch_claim_event_kind_v3 => {
        let claim = decode_dispatch_claim_record_v3(payload)
        if claims.any(prior => {
            prior.intent_ref == claim.intent_ref ||
            prior.claim_ref == claim.claim_ref ||
            prior.external_idempotency_key == claim.external_idempotency_key
          }) {
          raise RecoveryViolation(field="dispatch_claim_v3_duplicate")
        }
        claims.push(claim)
      }
      value if value == invocation_started_event_kind_v3 => {
        let started = decode_dispatch_invocation_started_v3(payload)
        if invocation_starts.any(prior => {
            prior.start_ref == started.start_ref ||
            prior.claim_ref == started.claim_ref ||
            prior.intent_ref == started.intent_ref
          }) {
          raise RecoveryViolation(field="dispatch_invocation_v3_duplicate")
        }
        invocation_starts.push(started)
      }
      value if value == dispatch_observation_event_kind_v3 => {
        let observation = decode_dispatch_observation_record_v3(payload)
        if observations.any(prior => {
            prior.observation_ref == observation.observation_ref ||
            prior.claim_ref == observation.claim_ref ||
            prior.intent_ref == observation.intent_ref
          }) {
          raise RecoveryViolation(field="dispatch_observation_v3_duplicate")
        }
        observations.push(observation)
      }
      value if value == recovery_policy_bound_event_kind_v3 => {
        let policy = decode_recovery_policy_bound_v3(payload)
        if recovery_policies.any(prior => {
            prior.binding_ref == policy.binding_ref ||
            prior.intent_ref == policy.intent_ref
          }) {
          raise RecoveryViolation(field="recovery_policy_binding_v3_duplicate")
        }
        recovery_policies.push(policy)
      }
      value if value == reconciliation_claim_event_kind_v3 => {
        let claim = decode_reconciliation_claim_record_v3(payload)
        if reconciliation_claims.any(prior => {
            prior.reconciliation_claim_ref == claim.reconciliation_claim_ref ||
            (
              prior.intent_ref == claim.intent_ref &&
              prior.reconciliation_ordinal == claim.reconciliation_ordinal
            )
          }) {
          raise RecoveryViolation(field="reconciliation_claim_v3_duplicate")
        }
        reconciliation_claims.push(claim)
      }
      value if value == reconciliation_query_started_event_kind_v3 => {
        let started = decode_reconciliation_query_started_v3(payload)
        if reconciliation_query_starts.any(prior => {
            prior.query_start_ref == started.query_start_ref ||
            prior.reconciliation_claim_ref == started.reconciliation_claim_ref
          }) {
          raise RecoveryViolation(
            field="reconciliation_query_started_v3_duplicate",
          )
        }
        reconciliation_query_starts.push(started)
      }
      value if value == reconciliation_result_event_kind_v3 => {
        let result = decode_reconciliation_result_record_v3(payload)
        if reconciliation_results.any(prior => {
            prior.result_ref == result.result_ref ||
            prior.reconciliation_claim_ref == result.reconciliation_claim_ref
          }) {
          raise RecoveryViolation(field="reconciliation_result_v3_duplicate")
        }
        reconciliation_results.push(result)
      }
      value if value == recovery_backoff_event_kind_v3 => {
        let backoff = decode_recovery_backoff_scheduled_v3(payload)
        if recovery_backoffs.any(prior => {
            prior.backoff_ref == backoff.backoff_ref ||
            prior.result_ref == backoff.result_ref
          }) {
          raise RecoveryViolation(field="recovery_backoff_v3_duplicate")
        }
        recovery_backoffs.push(backoff)
      }
      value if value == recovery_automation_stopped_event_kind_v3 => {
        let stopped = decode_recovery_automation_stopped_v3(payload)
        if recovery_automation_stops.any(prior => {
            prior.stopped_ref == stopped.stopped_ref ||
            prior.source_ref == stopped.source_ref
          }) {
          raise RecoveryViolation(
            field="recovery_automation_stopped_v3_duplicate",
          )
        }
        recovery_automation_stops.push(stopped)
      }
      value if value == effect_retry_policy_bound_event_kind_v3 ||
        value == recovery_retry_intent_event_kind_v3 ||
        value == recovery_retry_scheduled_event_kind_v3 =>
        if recovery_count != 1 {
          raise RecoveryViolation(field="recovery_v3_accounting")
        }
      value if value == recovery_work_terminal_event_kind_v3 => {
        if recovery_count != 1 {
          raise RecoveryViolation(field="recovery_v3_accounting")
        }
        recovery_terminal_seen = true
      }
      value if value == manual_intervention_hold_event_kind_v3 ||
        value == manual_intervention_resume_event_kind_v3 =>
        if recovery_count != 1 {
          raise RecoveryViolation(field="recovery_v3_accounting")
        }
      value if value == quarantine_disposition_event_kind_v1 =>
        if recovery_count != 1 {
          raise RecoveryViolation(field="recovery_v3_accounting")
        }
      _ =>
        if recovery_count != 0 {
          raise RecoveryViolation(field="recovery_v3_accounting")
        }
    }
  }
  let current = fold_governed_closed_loop_v2(
    empty, work_replay, governance_replay,
  )
  let strict_effects = @effects.fold_committed_effects_bytes(empty, work_replay) catch {
    _ => raise ReplayBindingViolation(field="recovery_v3_strict_effects")
  }
  let identity_catalog = strict_effects.strict_recovery_intent_catalog_v3() catch {
    _ => raise ReplayBindingViolation(field="v3_effect_identity_catalog")
  }
  let legacy_transitions = strict_effects.strict_legacy_transition_catalog_v3() catch {
    _ => raise ReplayBindingViolation(field="v3_legacy_transition_identity")
  }
  // A capability moves monotonically to V3 ownership at its activation event.
  // Historical V2 facts before that boundary remain valid; any later V2
  // observation/receipt for an owned intent is a protocol-confusion attempt.
  for transition in legacy_transitions {
    guard first(work_replay.events(), event => {
        event.event_ref() == transition.event_ref()
      })
      is Some(event) else {
      raise ReplayBindingViolation(field="v3_legacy_transition_identity")
    }
    guard first(identity_catalog, identity => {
        identity.intent_ref() == transition.intent_ref()
      })
      is Some(identity) else {
      raise ReplayBindingViolation(field="v3_effect_identity_catalog")
    }
    if activations.any(activation => {
        event.revision() > activation.expected_work_revision + 1L &&
        (
          activation.source_intent_ref == transition.intent_ref() ||
          (
            activation.capability_ref == identity.capability_ref() &&
            activation.capability_kind == identity.capability_kind()
          )
        )
      }) {
      raise RecoveryViolation(field="legacy_effect_transition_retired_phase2")
    }
  }
  for activation in activations {
    require_recovery_activation_prefix_v3(
      empty, activation, work_replay, governance_replay,
    )
  }
  for claim in claims {
    require_dispatch_claim_prefix_v3(
      empty, claim, work_replay, governance_replay,
    )
    guard first(activations, activation => {
        activation.activation_ref == claim.activation_ref &&
        activation.digest == claim.activation_digest &&
        activation.profile.digest == claim.provider_profile_digest &&
        activation.capability_ref == claim.capability_ref &&
        activation.capability_kind == claim.capability_kind
      })
      is Some(_) else {
      raise ReplayBindingViolation(field="dispatch_claim_v3_activation")
    }
    if invocation_starts
      .filter(started => {
        started.claim_ref == claim.claim_ref &&
        started.claim_digest == claim.digest
      })
      .length() !=
      1 {
      raise ReplayBindingViolation(field="dispatch_claim_v3_invocation_start")
    }
  }
  for observation in observations {
    guard first(claims, claim => {
        claim.claim_ref == observation.claim_ref &&
        claim.digest == observation.claim_digest
      })
      is Some(claim) else {
      raise ReplayBindingViolation(field="dispatch_observation_v3_claim")
    }
    require_dispatch_observation_governance_v3(observation, governance_replay)
    guard first(activations, activation => {
        activation.activation_ref == claim.activation_ref &&
        activation.digest == claim.activation_digest
      })
      is Some(_) else {
      raise ReplayBindingViolation(field="dispatch_observation_v3_activation")
    }
    // Slice 4 has no replay-verifiable query+tombstone barrier or fence-floor
    // proof. Create-time provider evidence can never establish non-application,
    // even when the activated profile advertises both provider capabilities.
    if observation.outcome == @effects.RecoveryConfirmedNotAppliedV3 {
      raise ReplayBindingViolation(
        field="dispatch_observation_v3_not_applied_proof",
      )
    }
  }
  for policy in recovery_policies {
    require_recovery_policy_prefix_v3(
      empty, policy, work_replay, governance_replay,
    )
  }
  for reconciliation_claim in reconciliation_claims {
    require_reconciliation_claim_prefix_v3(
      empty, reconciliation_claim, work_replay, governance_replay,
    )
    if reconciliation_query_starts
      .filter(started => {
        started.reconciliation_claim_ref ==
        reconciliation_claim.reconciliation_claim_ref &&
        started.reconciliation_claim_digest == reconciliation_claim.digest
      })
      .length() !=
      1 {
      raise ReplayBindingViolation(field="reconciliation_claim_v3_query_start")
    }
  }
  for started in reconciliation_query_starts {
    if reconciliation_claims
      .filter(claim => {
        claim.reconciliation_claim_ref == started.reconciliation_claim_ref &&
        claim.digest == started.reconciliation_claim_digest
      })
      .length() !=
      1 {
      raise ReplayBindingViolation(
        field="reconciliation_query_started_v3_claim",
      )
    }
  }
  for result in reconciliation_results {
    require_reconciliation_result_prefix_v3(
      empty, result, work_replay, governance_replay,
    )
    guard first(reconciliation_claims, claim => {
        claim.reconciliation_claim_ref == result.reconciliation_claim_ref &&
        claim.digest == result.reconciliation_claim_digest
      })
      is Some(reconciliation_claim) else {
      raise ReplayBindingViolation(field="reconciliation_result_v3_claim")
    }
    guard first(recovery_policies, policy => {
        policy.binding_ref == result.policy_binding_ref &&
        policy.digest == result.policy_binding_digest
      })
      is Some(policy_binding) else {
      raise ReplayBindingViolation(field="reconciliation_result_v3_policy")
    }
    guard first(claims, claim => {
        claim.claim_ref == result.dispatch_claim_ref &&
        claim.digest == result.dispatch_claim_digest
      })
      is Some(dispatch_claim) else {
      raise ReplayBindingViolation(field="reconciliation_result_v3_dispatch")
    }
    let matching_backoffs = recovery_backoffs.filter(backoff => {
      backoff.result_ref == result.result_ref &&
      backoff.result_digest == result.digest
    })
    let matching_stops = recovery_automation_stops.filter(stopped => {
      stopped.source_ref == result.result_ref &&
      stopped.source_digest == result.digest
    })
    if result.outcome == ReconciliationUnknownV3 {
      if matching_backoffs.length() + matching_stops.length() != 1 {
        raise ReplayBindingViolation(field="reconciliation_result_v3_auxiliary")
      }
    } else if !matching_backoffs.is_empty() || !matching_stops.is_empty() {
      raise ReplayBindingViolation(field="reconciliation_result_v3_auxiliary")
    }
    let deadline = match
      @decision.recovery_deadline(
        dispatch_claim.claimed_at,
        policy_binding.policy.maximum_elapsed,
      ) {
      @decision.RecoveryDueAt(value) => value
      _ => raise ReplayBindingViolation(field="recovery_deadline_v3_replay")
    }
    for backoff in matching_backoffs {
      let material = @utf8.encode(
        "\{policy_binding.policy.seed.text()}:\{reconciliation_claim.reconciliation_claim_ref.id()}:\{reconciliation_claim.reconciliation_ordinal}",
      )
      let due = match
        @decision.recovery_due_at(
          result.observed_at,
          policy_binding.policy.base_delay,
          policy_binding.policy.maximum_delay,
          policy_binding.policy.backoff_numerator,
          policy_binding.policy.backoff_denominator,
          reconciliation_claim.reconciliation_ordinal,
          policy_binding.policy.jitter_range,
          material,
        ) {
        @decision.RecoveryDueAt(value) => value
        _ => raise ReplayBindingViolation(field="recovery_backoff_v3_timing")
      }
      if backoff.intent_ref != result.intent_ref ||
        backoff.policy_binding_ref != policy_binding.binding_ref ||
        backoff.policy_binding_digest != policy_binding.digest ||
        backoff.reconciliation_ordinal !=
        reconciliation_claim.reconciliation_ordinal ||
        backoff.next_due_at != due ||
        backoff.deadline != deadline ||
        due > deadline {
        raise ReplayBindingViolation(field="recovery_backoff_v3_replay")
      }
    }
    for stopped in matching_stops {
      let exhausted = reconciliation_claim.reconciliation_ordinal >=
        policy_binding.policy.maximum_reconciliation_attempts
      let deadline_reached = result.observed_at >= deadline
      let deadline_would_be_exceeded = if exhausted || deadline_reached {
        false
      } else {
        let material = @utf8.encode(
          "\{policy_binding.policy.seed.text()}:\{reconciliation_claim.reconciliation_claim_ref.id()}:\{reconciliation_claim.reconciliation_ordinal}",
        )
        match
          @decision.recovery_due_at(
            result.observed_at,
            policy_binding.policy.base_delay,
            policy_binding.policy.maximum_delay,
            policy_binding.policy.backoff_numerator,
            policy_binding.policy.backoff_denominator,
            reconciliation_claim.reconciliation_ordinal,
            policy_binding.policy.jitter_range,
            material,
          ) {
          @decision.RecoveryDueAt(value) => value > deadline
          _ => raise ReplayBindingViolation(field="recovery_stop_v3_timing")
        }
      }
      let valid_reason = match stopped.reason {
        RecoveryAttemptsExhaustedV3 => exhausted && !deadline_reached
        RecoveryDeadlineExceededV3 =>
          deadline_reached || deadline_would_be_exceeded
        RecoveryContradictoryEvidenceV3 => true
      }
      if stopped.intent_ref != result.intent_ref ||
        stopped.policy_binding_ref != policy_binding.binding_ref ||
        stopped.policy_binding_digest != policy_binding.digest ||
        stopped.reconciliation_ordinal !=
        reconciliation_claim.reconciliation_ordinal ||
        stopped.stopped_at != result.observed_at ||
        !valid_reason {
        raise ReplayBindingViolation(field="recovery_stop_v3_replay")
      }
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/GOVERNED-RECOVERY-PROJECTION-V3/3.0.0")
  write_ref(writer, work_replay.workflow())
  writer.string(work_replay.replay_digest().text())
  write_ref(writer, governance_replay.workflow())
  writer.string(governance_replay.replay_digest().text())
  writer.count(activations.length())
  for activation in activations {
    writer.bytes(activation.canonical)
  }
  writer.count(claims.length())
  for claim in claims {
    writer.bytes(claim.canonical)
  }
  writer.count(invocation_starts.length())
  for started in invocation_starts {
    writer.bytes(started.canonical)
  }
  writer.count(observations.length())
  for observation in observations {
    writer.bytes(observation.canonical)
  }
  writer.count(recovery_policies.length())
  for policy in recovery_policies {
    writer.bytes(policy.canonical)
  }
  writer.count(reconciliation_claims.length())
  for claim in reconciliation_claims {
    writer.bytes(claim.canonical)
  }
  writer.count(reconciliation_query_starts.length())
  for started in reconciliation_query_starts {
    writer.bytes(started.canonical)
  }
  writer.count(reconciliation_results.length())
  for result in reconciliation_results {
    writer.bytes(result.canonical)
  }
  writer.count(recovery_backoffs.length())
  for backoff in recovery_backoffs {
    writer.bytes(backoff.canonical)
  }
  writer.count(recovery_automation_stops.length())
  for stopped in recovery_automation_stops {
    writer.bytes(stopped.canonical)
  }
  let projection : CurrentGovernedRecoveryProjectionV3 = {
    empty_effects: empty,
    current,
    work_replay,
    governance_replay,
    activations: ReadOnlyArray::from_array(activations),
    claims: ReadOnlyArray::from_array(claims),
    invocation_starts: ReadOnlyArray::from_array(invocation_starts),
    observations: ReadOnlyArray::from_array(observations),
    recovery_policies: ReadOnlyArray::from_array(recovery_policies),
    reconciliation_claims: ReadOnlyArray::from_array(reconciliation_claims),
    reconciliation_query_starts: ReadOnlyArray::from_array(
      reconciliation_query_starts,
    ),
    reconciliation_results: ReadOnlyArray::from_array(reconciliation_results),
    recovery_backoffs: ReadOnlyArray::from_array(recovery_backoffs),
    recovery_automation_stops: ReadOnlyArray::from_array(
      recovery_automation_stops,
    ),
    state_digest: @contracts.sha256_digest(writer.finish()),
  }
  if current.work.work_terminal is Some(_) {
    projection.require_work_terminal_ready_v3()
  }
  projection
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::state_for(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> @effects.EffectRecoveryStateV3 raise OrchestrationError {
  let manual = fold_manual_intervention_v3(self.work_replay)
  if manual.active_hold(intent_ref) is Some(_) {
    return @effects.RecoveryManualInterventionV3
  }
  match self.current_reconciliation_result_v3(intent_ref) {
    Some(result) =>
      match
        first(self.recovery_automation_stops, stopped => {
          stopped.source_ref == result.result_ref &&
          stopped.source_digest == result.digest
        }) {
        Some(stopped) =>
          if stopped.reason == RecoveryContradictoryEvidenceV3 {
            @effects.RecoveryManualInterventionV3
          } else {
            @effects.RecoveryExhaustedV3
          }
        None =>
          match result.outcome {
            ReconciliationAppliedV3 => @effects.RecoveryReconciledSuccessV3
            ReconciliationTerminalFailedV3 =>
              @effects.RecoveryReconciledFailureV3
            ReconciliationConfirmedNotAppliedV3 =>
              @effects.RecoveryConfirmedNotAppliedRetryEligibleV3
            ReconciliationUnknownV3 =>
              if self.recovery_backoffs.any(backoff => {
                  backoff.result_ref == result.result_ref &&
                  backoff.result_digest == result.digest
                }) {
                @effects.RecoveryBackoffPendingV3
              } else {
                raise ReplayBindingViolation(
                  field="reconciliation_result_v3_auxiliary",
                )
              }
          }
      }
    None if self.current_reconciliation_claim_v3(intent_ref) is Some(_) =>
      @effects.RecoveryReconciliationClaimedV3
    None =>
      match first(self.observations, value => value.intent_ref == intent_ref) {
        Some(observation) =>
          match observation.outcome {
            @effects.RecoveryKnownSucceededV3 => @effects.RecoveryKnownSuccessV3
            @effects.RecoveryKnownFailedV3 => @effects.RecoveryKnownFailureV3
            @effects.RecoveryConfirmedNotAppliedV3 =>
              raise ReplayBindingViolation(
                field="dispatch_observation_v3_not_applied_proof",
              )
            @effects.RecoveryStillUnknownV3 =>
              @effects.RecoveryUnknownRequiresReconciliationV3
          }
        None if self.claims.any(value => value.intent_ref == intent_ref) =>
          @effects.RecoveryDispatchAttemptedV3
        None =>
          match self.retry_dispatch_target_v3(intent_ref) {
            Some(_) => @effects.RecoveryDispatchEligibleV3
            None => {
              let intent = self.current.work.effects.strict_intent_state_v2(
                intent_ref,
              ) catch {
                _ => raise ReplayBindingViolation(field="recovery_v3_intent")
              }
              if intent.state() == @effects.DurableIntentDispatchEligible {
                @effects.RecoveryDispatchEligibleV3
              } else {
                raise RecoveryViolation(
                  field="recovery_v3_unimplemented_effect_state",
                )
              }
            }
          }
      }
  }
}

///|
/// Combine the root recovery projection with the independently durable
/// callback/quarantine stream. Manual/conflict evidence always wins. A later
/// root-stream resolution wins over an earlier callback that requested
/// reconciliation; otherwise the latest callback-derived state is current.
pub fn CurrentGovernedRecoveryProjectionV3::state_for_with_recovery_evidence_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> @effects.EffectRecoveryStateV3 raise OrchestrationError {
  let manual = fold_manual_intervention_v3(self.work_replay)
  if manual.active_hold(intent_ref) is Some(_) {
    return @effects.RecoveryManualInterventionV3
  }
  if evidence.bound_workflow() != self.work_replay.workflow() ||
    evidence.bound_work_replay_digest() != self.work_replay.replay_digest() {
    raise ReplayBindingViolation(field="recovery_evidence_work_binding_v3")
  }
  guard callback_recovery_state_v3(evidence, intent_ref) is Some(callback_state) else {
    return self.state_for(intent_ref)
  }
  if callback_state == @effects.RecoveryManualInterventionV3 {
    return callback_state
  }
  guard evidence.entries
    .filter(entry => entry.record.intent_ref == intent_ref)
    .last()
    is Some(latest_callback) else {
    return self.state_for(intent_ref)
  }
  let mut latest_work_resolution_revision = 0L
  match first(self.observations, value => value.intent_ref == intent_ref) {
    Some(value) =>
      latest_work_resolution_revision = value.expected_work_revision + 1L
    None => ()
  }
  match self.current_reconciliation_result_v3(intent_ref) {
    Some(value) => {
      let revision = value.expected_work_revision + 1L
      if revision > latest_work_resolution_revision {
        latest_work_resolution_revision = revision
      }
    }
    None => ()
  }
  if latest_work_resolution_revision >
    latest_callback.record.expected_work_revision {
    self.state_for(intent_ref)
  } else {
    callback_state
  }
}

///|
fn CurrentGovernedRecoveryProjectionV3::activation_for_capability_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  capability_ref : @contracts.RecordRef,
  capability_kind : String,
) -> RecoveryProtocolActivatedV3? {
  first(self.activations, value => {
    value.capability_ref == capability_ref &&
    value.capability_kind == capability_kind
  })
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::current_activation_for(
  self : CurrentGovernedRecoveryProjectionV3,
  capability_ref : @contracts.RecordRef,
  capability_kind : String,
) -> RecoveryProtocolActivatedV3? {
  self.activation_for_capability_v3(capability_ref, capability_kind)
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::current_claim(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> DispatchClaimRecordV3? {
  first(self.claims, value => value.intent_ref == intent_ref)
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_policy_for_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> RecoveryPolicyBoundV3? {
  first(self.recovery_policies, value => value.intent_ref == intent_ref)
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_policies_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> ReadOnlyArray[RecoveryPolicyBoundV3] {
  self.recovery_policies
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::current_reconciliation_claim_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> ReconciliationClaimRecordV3? {
  self.reconciliation_claims
  .filter(value => value.intent_ref == intent_ref)
  .last()
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::current_reconciliation_result_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> ReconciliationResultRecordV3? {
  guard self.current_reconciliation_claim_v3(intent_ref) is Some(claim) else {
    return None
  }
  first(self.reconciliation_results, value => {
    value.reconciliation_claim_ref == claim.reconciliation_claim_ref &&
    value.reconciliation_claim_digest == claim.digest
  })
}

///|
fn CurrentGovernedRecoveryProjectionV3::current_reconciliation_settlement_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> ReconciliationResultRecordV3? {
  match self.current_reconciliation_result_v3(intent_ref) {
    Some(value) if value.outcome != ReconciliationUnknownV3 => Some(value)
    _ => None
  }
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::current_recovery_due_at_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> Int64? {
  guard self.current_reconciliation_result_v3(intent_ref) is Some(result) else {
    return None
  }
  match
    first(self.recovery_backoffs, value => {
      value.result_ref == result.result_ref &&
      value.result_digest == result.digest
    }) {
    Some(value) => Some(value.next_due_at)
    None => None
  }
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::current_recovery_backoff_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> RecoveryBackoffScheduledV3? {
  guard self.current_reconciliation_result_v3(intent_ref) is Some(result) else {
    return None
  }
  first(self.recovery_backoffs, value => {
    value.result_ref == result.result_ref &&
    value.result_digest == result.digest
  })
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::current_recovery_automation_stop_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> RecoveryAutomationStoppedV3? {
  guard self.current_reconciliation_result_v3(intent_ref) is Some(result) else {
    return None
  }
  first(self.recovery_automation_stops, value => {
    value.source_ref == result.result_ref &&
    value.source_digest == result.digest
  })
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::reconciliation_claims_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> ReadOnlyArray[ReconciliationClaimRecordV3] {
  self.reconciliation_claims
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::reconciliation_query_starts_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> ReadOnlyArray[ReconciliationQueryStartedV3] {
  self.reconciliation_query_starts
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::reconciliation_results_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> ReadOnlyArray[ReconciliationResultRecordV3] {
  self.reconciliation_results
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_backoffs_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> ReadOnlyArray[RecoveryBackoffScheduledV3] {
  self.recovery_backoffs
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_automation_stops_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> ReadOnlyArray[RecoveryAutomationStoppedV3] {
  self.recovery_automation_stops
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::current_effect_retry_policy_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> EffectRetryPolicyBoundV3? raise OrchestrationError {
  self.effect_retry_policy_for_v3(intent_ref)
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_retry_schedules_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> ReadOnlyArray[RecoveryRetryScheduledV3] raise OrchestrationError {
  let values : Array[RecoveryRetryScheduledV3] = []
  for event in self.work_replay.events() {
    if event.payload().envelope_kind() == recovery_retry_scheduled_event_kind_v3 {
      values.push(decode_recovery_retry_scheduled_v3(event.payload().payload()))
    }
  }
  ReadOnlyArray::from_array(values)
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::recovery_terminal_outcome_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> RecoveryWorkTerminalOutcomeV3? raise OrchestrationError {
  let values : Array[RecoveryWorkTerminalOutcomeV3] = []
  for event in self.work_replay.events() {
    if event.payload().envelope_kind() == recovery_work_terminal_event_kind_v3 {
      values.push(
        decode_recovery_work_terminal_v3(event.payload().payload()).outcome,
      )
    }
  }
  if values.is_empty() {
    None
  } else {
    Some(values[0])
  }
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::state_digest(
  self : CurrentGovernedRecoveryProjectionV3,
) -> @contracts.ContentDigest {
  self.state_digest
}

///|
pub fn DispatchClaimRecordV3::record_ref(
  self : DispatchClaimRecordV3,
) -> @contracts.RecordRef {
  self.claim_ref
}

///|
pub fn DispatchClaimRecordV3::workflow(
  self : DispatchClaimRecordV3,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn DispatchClaimRecordV3::intent_ref(
  self : DispatchClaimRecordV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn DispatchClaimRecordV3::outbox_ref(
  self : DispatchClaimRecordV3,
) -> @contracts.RecordRef {
  self.outbox_ref
}

///|
pub fn DispatchClaimRecordV3::provider_operation(
  self : DispatchClaimRecordV3,
) -> @contracts.WireEnvelope {
  self.provider_operation
}

///|
pub fn DispatchClaimRecordV3::external_idempotency_key(
  self : DispatchClaimRecordV3,
) -> String {
  self.external_idempotency_key
}

///|
pub fn DispatchClaimRecordV3::dispatch_event_id(
  self : DispatchClaimRecordV3,
) -> String {
  self.dispatch_event_id
}

///|
pub fn DispatchClaimRecordV3::command_idempotency_key(
  self : DispatchClaimRecordV3,
) -> String {
  self.command_idempotency_key
}

///|
pub fn DispatchClaimRecordV3::owner(
  self : DispatchClaimRecordV3,
) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn DispatchClaimRecordV3::lease_epoch(
  self : DispatchClaimRecordV3,
) -> Int64 {
  self.lease_epoch
}

///|
pub fn DispatchClaimRecordV3::fencing_token(
  self : DispatchClaimRecordV3,
) -> Int64 {
  self.fencing_token
}

///|
pub fn DispatchClaimRecordV3::claim_ordinal(
  self : DispatchClaimRecordV3,
) -> Int64 {
  self.claim_ordinal
}

///|
pub fn DispatchClaimRecordV3::claimed_at(self : DispatchClaimRecordV3) -> Int64 {
  self.claimed_at
}

///|
pub fn DispatchClaimRecordV3::expires_at(self : DispatchClaimRecordV3) -> Int64 {
  self.expires_at
}

///|
pub fn DispatchClaimRecordV3::canonical_bytes(
  self : DispatchClaimRecordV3,
) -> Bytes {
  self.canonical
}

///|
pub fn DispatchClaimRecordV3::digest(
  self : DispatchClaimRecordV3,
) -> @contracts.ContentDigest {
  self.digest
}
