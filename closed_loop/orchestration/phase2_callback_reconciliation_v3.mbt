///|
let callback_reconciliation_candidate_magic_v3 = b"FLOW7/CALLBACK-RECONCILIATION-CANDIDATE-V3/3.0.0"

///|
pub struct CallbackReconciliationCandidateV3 {
  candidate_ref : @contracts.RecordRef
  dispatch : DispatchClaimRecordV3
  claim : ReconciliationClaimRecordV3
  started : ReconciliationQueryStartedV3
  callback_record_ref : @contracts.RecordRef
  callback_record_digest : @contracts.ContentDigest
  callback_integration_digest : @contracts.ContentDigest
  callback_disposition : RecoveryCallbackDispositionV3
  evidence_binding_ref : @contracts.RecordRef
  evidence_binding_digest : @contracts.ContentDigest
  evidence_workflow : @contracts.RecordRef
  evidence_revision : Int64
  evidence_head_digest : @contracts.ContentDigest?
  evidence_replay_digest : @contracts.ContentDigest
  evidence_state_digest : @contracts.ContentDigest
  recovery_state_digest : @contracts.ContentDigest
  policy_binding_ref : @contracts.RecordRef
  policy_binding_digest : @contracts.ContentDigest
  lease_receipt_ref : @contracts.RecordRef
  lease_receipt_digest : @contracts.ContentDigest
  owner : @contracts.RecordRef
  lease_epoch : Int64
  fencing_token : Int64
  request : @storage.CommitRequest
  guarded : @storage.GuardedCommitRequest
  empty_effects : @effects.EffectsProjection
  governance_replay : @storage.ReplayResult
  evidence_binding : RecoveryEvidenceStreamBindingV3
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn callback_reconciliation_evidence_marker_v3(
  entry : RecoveryCallbackProjectionEntryV3,
  binding : RecoveryEvidenceStreamBindingV3,
) -> @contracts.EvidenceRef raise OrchestrationError {
  @contracts.EvidenceRef::new(
    entry.record.callback_ref,
    binding.binding_ref,
    entry.record.digest.text(),
    media_type="application/vnd.moonflow.recovery-callback.v3",
  ) catch {
    _ => raise MalformedInput(field="callback_reconciliation_evidence_v3")
  }
}

///|
fn callback_reconciliation_claim_has_marker_v3(
  claim : ReconciliationClaimRecordV3,
) -> Bool {
  claim.evidence.any(value => {
    value.record().kind() == "orchestration-recovery-callback-v3" &&
    value.provenance_ref().kind() ==
    "orchestration-recovery-evidence-stream-binding-v3"
  })
}

///|
fn latest_effective_callback_integration_v3(
  projection : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> (RecoveryCallbackProjectionEntryV3, CallbackRecoveryIntegrationV3) raise OrchestrationError {
  let entries = projection.entries.filter(entry => {
    entry.record.intent_ref == intent_ref
  })
  let integrations = callback_recovery_integrations_v3(projection, intent_ref)
  if entries.length() != integrations.length() || entries.is_empty() {
    raise RecoveryViolation(field="callback_reconciliation_integration_v3")
  }
  let entry = entries[entries.length() - 1]
  let integration = integrations[integrations.length() - 1]
  if integration.record_ref != entry.record.callback_ref ||
    integration.intent_ref != intent_ref ||
    !integration.authoritative_reconciliation ||
    integration.manual_intervention ||
    integration.settlement_eligible {
    raise RecoveryViolation(field="callback_reconciliation_not_required_v3")
  }
  (entry, integration)
}

///|
fn callback_reconciliation_candidate_signing_bytes_v3(
  candidate_id : String,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  entry : RecoveryCallbackProjectionEntryV3,
  integration : CallbackRecoveryIntegrationV3,
  claim : ReconciliationClaimRecordV3,
  started : ReconciliationQueryStartedV3,
  policy : RecoveryPolicyBoundV3,
  lease : CommittedLeaseAuthorityReceiptV2,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(callback_reconciliation_candidate_magic_v3)
  writer.string("3.0.0")
  writer.string(candidate_id)
  write_ref(writer, current.work_replay.workflow())
  writer.int64(current.current.work_revision)
  writer.string(current.current.work_head_digest.text())
  writer.string(current.current.work_replay_digest.text())
  write_ref(writer, current.governance_replay.workflow())
  writer.int64(current.current.governance_revision)
  writer.optional_digest(current.current.governance_head_digest)
  writer.string(current.current.governance_replay_digest.text())
  write_ref(writer, evidence.binding.binding_ref)
  writer.string(evidence.binding.digest.text())
  write_ref(writer, evidence.binding.evidence_workflow)
  writer.int64(evidence.replay.head().revision())
  writer.optional_digest(evidence.replay.head().last_event_digest())
  writer.string(evidence.replay.replay_digest().text())
  writer.string(evidence.state_digest.text())
  write_ref(writer, entry.record.callback_ref)
  writer.string(entry.record.digest.text())
  writer.string(integration.digest.text())
  writer.string(recovery_callback_disposition_wire_v3(entry.disposition))
  write_ref(writer, policy.binding_ref)
  writer.string(policy.digest.text())
  write_ref(writer, lease.receipt_ref())
  writer.string(lease.digest().text())
  write_ref(writer, lease.owner())
  writer.int64(lease.epoch())
  writer.int64(lease.fencing_token())
  writer.bytes(claim.canonical)
  writer.bytes(started.canonical)
  writer.finish()
}

///|
fn require_callback_reconciliation_transition_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  proposed : ReconciliationClaimRecordV3,
  policy : RecoveryPolicyBoundV3,
) -> Unit raise OrchestrationError {
  if current.current.work.work_terminal is Some(_) {
    raise RecoveryViolation(field="callback_reconciliation_terminal_v3")
  }
  if proposed.claimed_at > int64_max - policy.policy.claim_ttl ||
    proposed.expires_at != proposed.claimed_at + policy.policy.claim_ttl ||
    proposed.reconciliation_ordinal >
    policy.policy.maximum_reconciliation_attempts {
    raise RecoveryViolation(field="callback_reconciliation_policy_v3")
  }
  match current.current_reconciliation_claim_v3(proposed.intent_ref) {
    None =>
      if proposed.reconciliation_ordinal != 1L {
        raise RecoveryViolation(field="callback_reconciliation_ordinal_v3")
      }
    Some(prior) => {
      if prior.reconciliation_ordinal >=
        policy.policy.maximum_reconciliation_attempts ||
        proposed.reconciliation_ordinal != prior.reconciliation_ordinal + 1L ||
        proposed.claimed_at < prior.expires_at ||
        proposed.lease_epoch <= prior.lease_epoch ||
        proposed.fencing_token <= prior.fencing_token {
        raise RecoveryViolation(field="callback_reconciliation_takeover_v3")
      }
      match current.current_reconciliation_result_v3(proposed.intent_ref) {
        Some(result) if result.outcome == ReconciliationUnknownV3 => {
          guard current.current_recovery_due_at_v3(proposed.intent_ref)
            is Some(due_at) else {
            raise RecoveryViolation(field="callback_reconciliation_backoff_v3")
          }
          if proposed.claimed_at < due_at {
            raise RecoveryViolation(field="callback_reconciliation_backoff_v3")
          }
        }
        _ => ()
      }
    }
  }
}

///|
pub fn prepare_callback_reconciliation_candidate_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
  candidate_id : String,
  claim_id : String,
  claim_event_id : String,
  query_started_event_id : String,
  command_idempotency_key : String,
  claimed_at : Int64,
) -> CallbackReconciliationCandidateV3 raise OrchestrationError {
  require_text(candidate_id, "callback_reconciliation_candidate_id_v3")
  require_text(claim_id, "callback_reconciliation_claim_id_v3")
  require_text(claim_event_id, "callback_reconciliation_claim_event_v3")
  require_text(query_started_event_id, "callback_reconciliation_query_event_v3")
  require_text(command_idempotency_key, "callback_reconciliation_command_v3")
  if claimed_at < 0L ||
    claim_event_id == query_started_event_id ||
    evidence.binding.work_workflow != current.work_replay.workflow() ||
    evidence.bound_work_replay.workflow() != current.work_replay.workflow() ||
    evidence.bound_work_replay.head().revision() !=
    current.work_replay.head().revision() ||
    evidence.bound_work_replay.head().last_event_digest() !=
    current.work_replay.head().last_event_digest() ||
    evidence.bound_work_replay.replay_digest() !=
    current.work_replay.replay_digest() {
    raise ReplayBindingViolation(
      field="callback_reconciliation_three_stream_v3",
    )
  }
  let (entry, integration) = latest_effective_callback_integration_v3(
    evidence, intent_ref,
  )
  guard current.current_claim(intent_ref) is Some(dispatch) else {
    raise RecoveryViolation(field="callback_reconciliation_dispatch_v3")
  }
  guard first(current.invocation_starts, value => {
      value.claim_ref == dispatch.claim_ref
    })
    is Some(invocation) else {
    raise RecoveryViolation(field="callback_reconciliation_invocation_v3")
  }
  guard current.recovery_policy_for_v3(intent_ref) is Some(policy) else {
    raise RecoveryViolation(field="callback_reconciliation_policy_v3")
  }
  guard current.current.work.orchestration.committed_lease_authority_receipt()
    is Some(lease) else {
    raise RecoveryViolation(field="callback_reconciliation_lease_v3")
  }
  lease.validate_current(current.current.work.orchestration, claimed_at)
  let ordinal = match current.current_reconciliation_claim_v3(intent_ref) {
    None => 1L
    Some(prior) => prior.reconciliation_ordinal + 1L
  }
  if claimed_at > int64_max - policy.policy.claim_ttl {
    raise ArithmeticOverflow(field="callback_reconciliation_expiry_v3")
  }
  let expires_at = claimed_at + policy.policy.claim_ttl
  let evidence_values = [ for value in dispatch.evidence => value ]
  for value in entry.record.callback.evidence {
    if !evidence_values.any(prior => prior == value) {
      evidence_values.push(value)
    }
  }
  let marker = callback_reconciliation_evidence_marker_v3(
    entry,
    evidence.binding,
  )
  evidence_values.push(marker)
  let claim_canonical = reconciliation_claim_signing_bytes_v3(
    claim_id,
    dispatch.workflow,
    dispatch.intent_ref,
    dispatch.governed_subject,
    dispatch.claim_ref,
    dispatch.digest,
    invocation.start_ref,
    invocation.digest,
    dispatch.external_idempotency_key,
    dispatch.capability_ref,
    dispatch.capability_kind,
    dispatch.activation_ref,
    dispatch.activation_digest,
    dispatch.provider_profile_digest,
    policy.binding_ref,
    policy.digest,
    claim_event_id,
    query_started_event_id,
    command_idempotency_key,
    lease.owner(),
    lease.receipt_ref(),
    lease.digest(),
    lease.lease_claimed_ref(),
    lease.lease_claimed_digest(),
    lease.epoch(),
    lease.fencing_token(),
    ordinal,
    claimed_at,
    expires_at,
    current.current.work_revision,
    current.current.work_head_digest,
    current.current.work_replay_digest,
    current.governance_replay.workflow(),
    current.current.governance_revision,
    current.current.governance_head_digest,
    current.current.governance_replay_digest,
    evidence_values,
  )
  let claim_digest = @contracts.sha256_digest(claim_canonical)
  let claim : ReconciliationClaimRecordV3 = {
    reconciliation_claim_ref: self_ref_v3(
      "orchestration-reconciliation-claim-v3", claim_id, claim_digest,
    ),
    workflow: dispatch.workflow,
    intent_ref: dispatch.intent_ref,
    governed_subject: dispatch.governed_subject,
    dispatch_claim_ref: dispatch.claim_ref,
    dispatch_claim_digest: dispatch.digest,
    invocation_start_ref: invocation.start_ref,
    invocation_start_digest: invocation.digest,
    external_idempotency_key: dispatch.external_idempotency_key,
    capability_ref: dispatch.capability_ref,
    capability_kind: dispatch.capability_kind,
    activation_ref: dispatch.activation_ref,
    activation_digest: dispatch.activation_digest,
    provider_profile_digest: dispatch.provider_profile_digest,
    policy_binding_ref: policy.binding_ref,
    policy_binding_digest: policy.digest,
    claim_event_id,
    query_started_event_id,
    command_idempotency_key,
    owner: lease.owner(),
    lease_receipt_ref: lease.receipt_ref(),
    lease_receipt_digest: lease.digest(),
    lease_claimed_ref: lease.lease_claimed_ref(),
    lease_claimed_digest: lease.lease_claimed_digest(),
    lease_epoch: lease.epoch(),
    fencing_token: lease.fencing_token(),
    reconciliation_ordinal: ordinal,
    claimed_at,
    expires_at,
    expected_work_revision: current.current.work_revision,
    expected_work_head_digest: current.current.work_head_digest,
    expected_work_replay_digest: current.current.work_replay_digest,
    governance_workflow: current.governance_replay.workflow(),
    expected_governance_revision: current.current.governance_revision,
    expected_governance_head_digest: current.current.governance_head_digest,
    expected_governance_replay_digest: current.current.governance_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence_values),
    canonical: claim_canonical,
    digest: claim_digest,
  }
  require_callback_reconciliation_transition_v3(current, claim, policy)
  let claim_event = reconciliation_claim_event_v3(current.current, claim)
  let started = make_reconciliation_query_started_v3(claim)
  let query_event = reconciliation_query_started_event_v3(claim, claim_event)
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    claim.workflow,
    claim.expected_work_revision,
    claim.command_idempotency_key,
    [claim_event, query_event],
    [],
  ) catch {
    _ => raise MalformedInput(field="callback_reconciliation_commit_request_v3")
  }
  let guarded = @storage.GuardedCommitRequest::new(request, [
    @storage.WorkflowHeadGuard::new(
      claim.governance_workflow,
      claim.expected_governance_revision,
      claim.expected_governance_head_digest,
      claim.expected_governance_replay_digest,
    ),
    @storage.WorkflowHeadGuard::new(
      evidence.binding.evidence_workflow,
      evidence.replay.head().revision(),
      evidence.replay.head().last_event_digest(),
      evidence.replay.replay_digest(),
    ),
  ]) catch {
    _ =>
      raise MalformedInput(field="callback_reconciliation_guarded_request_v3")
  }
  let canonical = callback_reconciliation_candidate_signing_bytes_v3(
    candidate_id, current, evidence, entry, integration, claim, started, policy,
    lease,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    candidate_ref: self_ref_v3(
      "orchestration-callback-reconciliation-candidate-v3", candidate_id, digest,
    ),
    dispatch,
    claim,
    started,
    callback_record_ref: entry.record.callback_ref,
    callback_record_digest: entry.record.digest,
    callback_integration_digest: integration.digest,
    callback_disposition: entry.disposition,
    evidence_binding_ref: evidence.binding.binding_ref,
    evidence_binding_digest: evidence.binding.digest,
    evidence_workflow: evidence.binding.evidence_workflow,
    evidence_revision: evidence.replay.head().revision(),
    evidence_head_digest: evidence.replay.head().last_event_digest(),
    evidence_replay_digest: evidence.replay.replay_digest(),
    evidence_state_digest: evidence.state_digest,
    recovery_state_digest: current.state_digest,
    policy_binding_ref: policy.binding_ref,
    policy_binding_digest: policy.digest,
    lease_receipt_ref: lease.receipt_ref(),
    lease_receipt_digest: lease.digest(),
    owner: lease.owner(),
    lease_epoch: lease.epoch(),
    fencing_token: lease.fencing_token(),
    request,
    guarded,
    empty_effects: current.empty_effects,
    governance_replay: current.governance_replay,
    evidence_binding: evidence.binding,
    canonical,
    digest,
  }
}

///|
fn try_require_callback_reconciliation_claim_transaction_v3(
  claim : ReconciliationClaimRecordV3,
  claim_event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Bool raise OrchestrationError {
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().any(value => value == claim_event.event_ref())
    })
  if batches.length() != 1 || batches[0].guards().length() != 2 {
    return false
  }
  if !callback_reconciliation_claim_has_marker_v3(claim) ||
    batches[0].expected_revision() != claim.expected_work_revision ||
    batches[0].command_idempotency_key() != claim.command_idempotency_key ||
    batches[0].event_refs().length() != 2 ||
    batches[0].event_refs()[0] != claim_event.event_ref() ||
    !batches[0].intent_refs().is_empty() {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_transaction_v3",
    )
  }
  guard first(replay.events(), event => {
      event.event_ref() == batches[0].event_refs()[1]
    })
    is Some(start_event) else {
    raise ReplayBindingViolation(field="callback_reconciliation_query_start_v3")
  }
  let started = decode_reconciliation_query_started_v3(
    start_event.payload().payload(),
  )
  require_reconciliation_query_started_binding_v3(started, start_event, claim)
  let governance = batches[0].guards()[0]
  let callback_evidence = batches[0].guards()[1]
  if governance.workflow() != claim.governance_workflow ||
    governance.expected_revision() != claim.expected_governance_revision ||
    governance.expected_head_digest() != claim.expected_governance_head_digest ||
    governance.expected_replay_digest() !=
    claim.expected_governance_replay_digest ||
    callback_evidence.workflow() == claim.workflow ||
    callback_evidence.workflow() == claim.governance_workflow {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_guards_v3",
    )
  }
  true
}

///|
fn try_require_callback_reconciliation_claim_prefix_v3(
  empty : @effects.EffectsProjection,
  claim : ReconciliationClaimRecordV3,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> Bool raise OrchestrationError {
  if !callback_reconciliation_claim_has_marker_v3(claim) {
    return false
  }
  guard first(work_replay.events(), event => {
      event.event_ref().id() == claim.claim_event_id
    })
    is Some(claim_event) else {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_prefix_event_v3",
    )
  }
  if !try_require_callback_reconciliation_claim_transaction_v3(
      claim, claim_event, work_replay,
    ) {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_prefix_transaction_v3",
    )
  }
  let work_prefix = verified_prefix_v3(
    work_replay,
    claim.expected_work_revision,
    "callback_reconciliation_claim_work_prefix_v3",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    claim.expected_governance_revision,
    "callback_reconciliation_claim_governance_prefix_v3",
  )
  if work_prefix.head().last_event_digest() !=
    Some(claim.expected_work_head_digest) ||
    work_prefix.replay_digest() != claim.expected_work_replay_digest ||
    governance_prefix.workflow() != claim.governance_workflow ||
    governance_prefix.head().last_event_digest() !=
    claim.expected_governance_head_digest ||
    governance_prefix.replay_digest() != claim.expected_governance_replay_digest {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_prefix_v3",
    )
  }
  let prefix = fold_governed_recovery_v3(empty, work_prefix, governance_prefix)
  guard prefix.current_claim(claim.intent_ref) is Some(dispatch) else {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_dispatch_v3",
    )
  }
  guard first(prefix.invocation_starts, value => {
      value.start_ref == claim.invocation_start_ref
    })
    is Some(invocation) else {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_invocation_v3",
    )
  }
  guard prefix.recovery_policy_for_v3(claim.intent_ref) is Some(policy) else {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_policy_v3",
    )
  }
  guard prefix.current.work.orchestration.committed_lease_authority_receipt()
    is Some(lease) else {
    raise ReplayBindingViolation(field="callback_reconciliation_claim_lease_v3")
  }
  lease.validate_current(prefix.current.work.orchestration, claim.claimed_at)
  if dispatch.claim_ref != claim.dispatch_claim_ref ||
    dispatch.digest != claim.dispatch_claim_digest ||
    invocation.digest != claim.invocation_start_digest ||
    dispatch.external_idempotency_key != claim.external_idempotency_key ||
    dispatch.capability_ref != claim.capability_ref ||
    dispatch.capability_kind != claim.capability_kind ||
    dispatch.activation_ref != claim.activation_ref ||
    dispatch.activation_digest != claim.activation_digest ||
    dispatch.provider_profile_digest != claim.provider_profile_digest ||
    policy.binding_ref != claim.policy_binding_ref ||
    policy.digest != claim.policy_binding_digest ||
    lease.receipt_ref() != claim.lease_receipt_ref ||
    lease.digest() != claim.lease_receipt_digest ||
    lease.lease_claimed_ref() != claim.lease_claimed_ref ||
    lease.lease_claimed_digest() != claim.lease_claimed_digest ||
    lease.owner() != claim.owner ||
    lease.epoch() != claim.lease_epoch ||
    lease.fencing_token() != claim.fencing_token ||
    claim.expires_at > lease.expires_at() {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_source_v3",
    )
  }
  require_callback_reconciliation_transition_v3(prefix, claim, policy)
  true
}

///|
fn try_require_callback_reconciliation_result_transaction_v3(
  record : ReconciliationResultRecordV3,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Bool raise OrchestrationError {
  let batches = replay
    .committed_batches()
    .filter(batch => batch.event_refs().any(value => value == event.event_ref()))
  if batches.length() != 1 || batches[0].guards().length() != 2 {
    return false
  }
  guard first(replay.events(), candidate => {
      candidate.payload().envelope_kind() == reconciliation_claim_event_kind_v3 &&
      candidate.payload().idempotency_ref() ==
      Some(record.reconciliation_claim_ref.id())
    })
    is Some(claim_event) else {
    raise ReplayBindingViolation(
      field="callback_reconciliation_result_claim_v3",
    )
  }
  let claim = decode_reconciliation_claim_record_v3(
    claim_event.payload().payload(),
  )
  if claim.reconciliation_claim_ref != record.reconciliation_claim_ref ||
    claim.digest != record.reconciliation_claim_digest ||
    !try_require_callback_reconciliation_claim_transaction_v3(
      claim, claim_event, replay,
    ) {
    raise ReplayBindingViolation(
      field="callback_reconciliation_result_claim_v3",
    )
  }
  let expected_events = if record.outcome == ReconciliationUnknownV3 {
    2
  } else {
    1
  }
  if batches[0].expected_revision() != record.expected_work_revision ||
    batches[0].command_idempotency_key() != record.command_idempotency_key ||
    batches[0].event_refs().length() != expected_events ||
    batches[0].event_refs()[0] != event.event_ref() ||
    !batches[0].intent_refs().is_empty() {
    raise ReplayBindingViolation(
      field="callback_reconciliation_result_transaction_v3",
    )
  }
  let governance = batches[0].guards()[0]
  let callback_evidence = batches[0].guards()[1]
  let claim_batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().any(value => value == claim_event.event_ref())
    })
  if claim_batches.length() != 1 ||
    claim_batches[0].guards().length() != 2 ||
    governance.workflow() != record.governance_workflow ||
    governance.expected_revision() != record.expected_governance_revision ||
    governance.expected_head_digest() != record.expected_governance_head_digest ||
    governance.expected_replay_digest() !=
    record.expected_governance_replay_digest ||
    callback_evidence.workflow() != claim_batches[0].guards()[1].workflow() {
    raise ReplayBindingViolation(
      field="callback_reconciliation_result_guards_v3",
    )
  }
  true
}

///|
fn require_callback_reconciliation_candidate_replay_v3(
  candidate : CallbackReconciliationCandidateV3,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
  evidence_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  guard first(work_replay.events(), event => {
      event.event_ref().id() == candidate.claim.claim_event_id
    })
    is Some(claim_event) else {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_replay_v3",
    )
  }
  require_reconciliation_claim_event_binding_v3(candidate.claim, claim_event)
  if !try_require_callback_reconciliation_claim_transaction_v3(
      candidate.claim,
      claim_event,
      work_replay,
    ) {
    raise ReplayBindingViolation(
      field="callback_reconciliation_claim_replay_v3",
    )
  }
  let work_prefix = verified_prefix_v3(
    work_replay,
    candidate.claim.expected_work_revision,
    "callback_reconciliation_work_prefix_v3",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    candidate.claim.expected_governance_revision,
    "callback_reconciliation_governance_prefix_v3",
  )
  let evidence_prefix = verified_prefix_v3(
    evidence_replay,
    candidate.evidence_revision,
    "callback_reconciliation_evidence_prefix_v3",
  )
  if work_prefix.head().last_event_digest() !=
    Some(candidate.claim.expected_work_head_digest) ||
    work_prefix.replay_digest() != candidate.claim.expected_work_replay_digest ||
    governance_prefix.workflow() != candidate.claim.governance_workflow ||
    governance_prefix.head().last_event_digest() !=
    candidate.claim.expected_governance_head_digest ||
    governance_prefix.replay_digest() !=
    candidate.claim.expected_governance_replay_digest ||
    evidence_prefix.workflow() != candidate.evidence_workflow ||
    evidence_prefix.head().last_event_digest() != candidate.evidence_head_digest ||
    evidence_prefix.replay_digest() != candidate.evidence_replay_digest {
    raise ReplayBindingViolation(field="callback_reconciliation_prefix_v3")
  }
  let evidence_projection = fold_recovery_evidence_stream_v3(
    candidate.evidence_binding,
    evidence_prefix,
    work_prefix,
  )
  let (entry, integration) = latest_effective_callback_integration_v3(
    evidence_projection,
    candidate.claim.intent_ref,
  )
  if entry.record.callback_ref != candidate.callback_record_ref ||
    entry.record.digest != candidate.callback_record_digest ||
    integration.digest != candidate.callback_integration_digest ||
    entry.disposition != candidate.callback_disposition ||
    evidence_projection.state_digest != candidate.evidence_state_digest {
    raise ReplayBindingViolation(
      field="callback_reconciliation_integration_replay_v3",
    )
  }
}

///|
fn require_callback_reconciliation_claim_evidence_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  claim : ReconciliationClaimRecordV3,
) -> @contracts.RecordRef raise OrchestrationError {
  if evidence.binding.work_workflow != current.work_replay.workflow() ||
    evidence.bound_work_replay.workflow() != current.work_replay.workflow() {
    raise ReplayBindingViolation(
      field="callback_reconciliation_validation_stream_v3",
    )
  }
  guard first(current.work_replay.events(), event => {
      event.event_ref().id() == claim.claim_event_id
    })
    is Some(claim_event) else {
    raise ReplayBindingViolation(
      field="callback_reconciliation_validation_claim_v3",
    )
  }
  if !try_require_callback_reconciliation_claim_transaction_v3(
      claim,
      claim_event,
      current.work_replay,
    ) {
    raise ReplayBindingViolation(
      field="callback_reconciliation_validation_claim_v3",
    )
  }
  guard first(current.work_replay.committed_batches(), batch => {
      batch.event_refs().any(value => value == claim_event.event_ref())
    })
    is Some(batch) else {
    raise ReplayBindingViolation(
      field="callback_reconciliation_validation_batch_v3",
    )
  }
  let evidence_guard = batch.guards()[1]
  if evidence_guard.workflow() != evidence.binding.evidence_workflow {
    raise ReplayBindingViolation(
      field="callback_reconciliation_validation_guard_v3",
    )
  }
  let work_prefix = verified_prefix_v3(
    current.work_replay,
    claim.expected_work_revision,
    "callback_reconciliation_validation_work_v3",
  )
  let evidence_prefix = verified_prefix_v3(
    evidence.replay,
    evidence_guard.expected_revision(),
    "callback_reconciliation_validation_evidence_v3",
  )
  if evidence_prefix.head().last_event_digest() !=
    evidence_guard.expected_head_digest() ||
    evidence_prefix.replay_digest() != evidence_guard.expected_replay_digest() {
    raise ReplayBindingViolation(
      field="callback_reconciliation_validation_evidence_v3",
    )
  }
  let guarded_projection = fold_recovery_evidence_stream_v3(
    evidence.binding,
    evidence_prefix,
    work_prefix,
  )
  let (entry, integration) = latest_effective_callback_integration_v3(
    guarded_projection,
    claim.intent_ref,
  )
  guard first(claim.evidence, value => {
      value.record().kind() == "orchestration-recovery-callback-v3" &&
      value.provenance_ref() == evidence.binding.binding_ref
    })
    is Some(marker) else {
    raise ReplayBindingViolation(
      field="callback_reconciliation_validation_marker_v3",
    )
  }
  if marker.record() != entry.record.callback_ref ||
    marker.observed_digest() != entry.record.digest ||
    integration.record_ref != entry.record.callback_ref ||
    !integration.authoritative_reconciliation ||
    integration.manual_intervention ||
    integration.settlement_eligible {
    raise ReplayBindingViolation(
      field="callback_reconciliation_validation_integration_v3",
    )
  }
  entry.record.callback_ref
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::validate_callback_reconciliation_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> @contracts.RecordRef? raise OrchestrationError {
  guard self.current_reconciliation_claim_v3(intent_ref) is Some(claim) else {
    return None
  }
  if !callback_reconciliation_claim_has_marker_v3(claim) {
    return None
  }
  Some(require_callback_reconciliation_claim_evidence_v3(self, evidence, claim))
}

///|
priv enum CallbackReconciliationCommitOutcomeV3 {
  CallbackReconciliationFreshV3
  CallbackReconciliationAlreadyCommittedV3
  CallbackReconciliationRaceLostV3
  CallbackReconciliationGuardRejectedV3
}

///|
fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_callback_reconciliation_candidate_v3(
  store : S,
  candidate : CallbackReconciliationCandidateV3,
) -> CallbackReconciliationCommitOutcomeV3 raise {
  require_phase2_recovery_evidence_guard_profile_v3(store, candidate.guarded)
  try {
    match store.classified_guarded_commit(candidate.guarded) {
      @storage.FreshlyApplied(_) => CallbackReconciliationFreshV3
      @storage.AlreadyCommitted(_) => CallbackReconciliationAlreadyCommittedV3
      @storage.GuardRejected(_) => CallbackReconciliationGuardRejectedV3
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) => CallbackReconciliationRaceLostV3
    error => raise error
  }
}

///|
fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_callback_reconciliation_result_v3(
  store : S,
  candidate : CallbackReconciliationCandidateV3,
  outcome : ReconciliationOutcomeV3,
  provider_evidence : ProviderQueryEvidenceV3?,
  result_id : String,
  event_id : String,
  auxiliary_event_id : String,
  observed_at : Int64,
) -> Bool {
  try {
    require_phase2_recovery_evidence_guard_profile_v3(store, candidate.guarded)
    let work = store.replay(candidate.claim.workflow)
    let governance = store.replay_registered_guard(
      candidate.claim.governance_workflow,
    )
    let callback_evidence = store.replay_registered_guard(
      candidate.evidence_workflow,
    )
    require_callback_reconciliation_candidate_replay_v3(
      candidate, work, governance, callback_evidence,
    )
    let current = fold_governed_recovery_v3(
      candidate.empty_effects,
      work,
      governance,
    )
    guard current.current_reconciliation_claim_v3(candidate.claim.intent_ref)
      is Some(claim) else {
      return false
    }
    if claim.reconciliation_claim_ref !=
      candidate.claim.reconciliation_claim_ref {
      return false
    }
    guard first(current.reconciliation_query_starts, value => {
        value.reconciliation_claim_ref == claim.reconciliation_claim_ref
      })
      is Some(started) else {
      return false
    }
    guard current.recovery_policy_for_v3(claim.intent_ref) is Some(policy) else {
      return false
    }
    guard current.current_claim(claim.intent_ref) is Some(dispatch) else {
      return false
    }
    let command = claim.command_idempotency_key + ":result"
    let result = make_reconciliation_result_record_v3(
      current, dispatch, claim, started, policy, outcome, provider_evidence, result_id,
      event_id, command, observed_at,
    )
    let first_event = recovery_auxiliary_event_v3(
      result.workflow,
      result.governed_subject,
      result.reconciliation_claim_ref,
      result.result_ref,
      reconciliation_result_event_kind_v3,
      result.event_id,
      result.canonical,
      current.current.work_sequence + 1L,
      current.current.work_revision + 1L,
      current.current.work_head_digest,
    )
    let events : Array[@storage.WorkflowEvent] = [first_event]
    if outcome == ReconciliationUnknownV3 {
      let deadline = match
        @decision.recovery_deadline(
          dispatch.claimed_at,
          policy.policy.maximum_elapsed,
        ) {
        @decision.RecoveryDueAt(value) => value
        _ => return false
      }
      let exhausted = claim.reconciliation_ordinal >=
        policy.policy.maximum_reconciliation_attempts ||
        observed_at >= deadline
      if exhausted {
        let reason = if observed_at >= deadline {
          RecoveryDeadlineExceededV3
        } else {
          RecoveryAttemptsExhaustedV3
        }
        let stopped = recovery_automation_stopped_record_v3(
          result, policy, claim, reason, observed_at, auxiliary_event_id,
        )
        events.push(
          recovery_auxiliary_event_v3(
            stopped.workflow,
            result.governed_subject,
            result.result_ref,
            stopped.stopped_ref,
            recovery_automation_stopped_event_kind_v3,
            stopped.event_id,
            stopped.canonical,
            first_event.sequence() + 1L,
            first_event.revision() + 1L,
            first_event.event_ref().digest(),
          ),
        )
      } else {
        let material = @utf8.encode(
          "\{policy.policy.seed.text()}:\{claim.reconciliation_claim_ref.id()}:\{claim.reconciliation_ordinal}",
        )
        let due = match
          @decision.recovery_due_at(
            observed_at,
            policy.policy.base_delay,
            policy.policy.maximum_delay,
            policy.policy.backoff_numerator,
            policy.policy.backoff_denominator,
            claim.reconciliation_ordinal,
            policy.policy.jitter_range,
            material,
          ) {
          @decision.RecoveryDueAt(value) => value
          _ => return false
        }
        if due > deadline {
          let stopped = recovery_automation_stopped_record_v3(
            result,
            policy,
            claim,
            RecoveryDeadlineExceededV3,
            observed_at,
            auxiliary_event_id,
          )
          events.push(
            recovery_auxiliary_event_v3(
              stopped.workflow,
              result.governed_subject,
              result.result_ref,
              stopped.stopped_ref,
              recovery_automation_stopped_event_kind_v3,
              stopped.event_id,
              stopped.canonical,
              first_event.sequence() + 1L,
              first_event.revision() + 1L,
              first_event.event_ref().digest(),
            ),
          )
        } else {
          let backoff = recovery_backoff_record_v3(
            result, policy, claim, due, deadline, auxiliary_event_id,
          )
          events.push(
            recovery_auxiliary_event_v3(
              backoff.workflow,
              result.governed_subject,
              result.result_ref,
              backoff.backoff_ref,
              recovery_backoff_event_kind_v3,
              backoff.event_id,
              backoff.canonical,
              first_event.sequence() + 1L,
              first_event.revision() + 1L,
              first_event.event_ref().digest(),
            ),
          )
        }
      }
    }
    let request = @storage.CommitRequest::new(
      orchestration_record_version,
      orchestration_schema_version,
      result.workflow,
      result.expected_work_revision,
      result.command_idempotency_key,
      events,
      [],
    )
    let guarded = @storage.GuardedCommitRequest::new(request, [
      @storage.WorkflowHeadGuard::new(
        governance.workflow(),
        governance.head().revision(),
        governance.head().last_event_digest(),
        governance.replay_digest(),
      ),
      @storage.WorkflowHeadGuard::new(
        callback_evidence.workflow(),
        callback_evidence.head().revision(),
        callback_evidence.head().last_event_digest(),
        callback_evidence.replay_digest(),
      ),
    ])
    match store.classified_guarded_commit(guarded) {
      @storage.FreshlyApplied(_) | @storage.AlreadyCommitted(_) => true
      @storage.GuardRejected(_) => false
    }
  } catch {
    _ => false
  }
}

///|
pub(all) enum CallbackGuardedRecoveryQueryDispositionV3 {
  CallbackGuardedRecoveryQueryObservedV3(ReconciliationOutcomeV3)
  CallbackGuardedRecoveryQueryAlreadyCommittedV3
  CallbackGuardedRecoveryQueryRaceLostNoCallV3
  CallbackGuardedRecoveryQueryGuardChangedNoCallV3
} derive(Eq, Debug)

///|
pub struct CallbackGuardedRecoveryQueryResultV3 {
  disposition : CallbackGuardedRecoveryQueryDispositionV3
  reconciliation_claim_ref : @contracts.RecordRef?
  query_start_ref : @contracts.RecordRef?
  callback_record_ref : @contracts.RecordRef?
  provider_evidence : ProviderQueryEvidenceV3?
  result_persisted : Bool
}

///|
pub fn[
  S : @storage.ClassifiedRegistryBoundGuardedStoragePort,
  P : GuardedRecoveryQueryPortV3,
] reconcile_callback_evidence_v3(
  store : S,
  current : CurrentGovernedRecoveryProjectionV3,
  callback_evidence : CurrentRecoveryEvidenceProjectionV3,
  port : P,
  intent_ref : @contracts.RecordRef,
  candidate_id : String,
  claim_id : String,
  claim_event_id : String,
  query_started_event_id : String,
  command_idempotency_key : String,
  result_id : String,
  result_event_id : String,
  auxiliary_event_id : String,
  claimed_at : Int64,
  observed_at : Int64,
) -> CallbackGuardedRecoveryQueryResultV3 raise {
  require_text(result_id, "callback_reconciliation_result_id_v3")
  require_text(result_event_id, "callback_reconciliation_result_event_v3")
  require_text(auxiliary_event_id, "callback_reconciliation_aux_event_v3")
  if observed_at < claimed_at {
    raise OrderingViolation(field="callback_reconciliation_result_time_v3")
  }
  match current.current_reconciliation_claim_v3(intent_ref) {
    Some(existing) if existing.command_idempotency_key ==
      command_idempotency_key => {
      if existing.reconciliation_claim_ref.id() != claim_id ||
        existing.claim_event_id != claim_event_id ||
        existing.query_started_event_id != query_started_event_id ||
        existing.claimed_at != claimed_at ||
        !callback_reconciliation_claim_has_marker_v3(existing) {
        raise IdempotencyConflict(key=command_idempotency_key)
      }
      guard first(current.reconciliation_query_starts, value => {
          value.reconciliation_claim_ref == existing.reconciliation_claim_ref &&
          value.reconciliation_claim_digest == existing.digest
        })
        is Some(started) else {
        raise ReplayBindingViolation(
          field="callback_reconciliation_query_start_missing_v3",
        )
      }
      let committed = current.current_reconciliation_result_v3(intent_ref)
      let callback_record_ref = Some(
        require_callback_reconciliation_claim_evidence_v3(
          current, callback_evidence, existing,
        ),
      )
      return {
        disposition: CallbackGuardedRecoveryQueryAlreadyCommittedV3,
        reconciliation_claim_ref: Some(existing.reconciliation_claim_ref),
        query_start_ref: Some(started.query_start_ref),
        callback_record_ref,
        provider_evidence: match committed {
          Some(value) => value.provider_evidence
          None => None
        },
        result_persisted: committed is Some(_),
      }
    }
    _ => ()
  }
  let candidate = prepare_callback_reconciliation_candidate_v3(
    current, callback_evidence, intent_ref, candidate_id, claim_id, claim_event_id,
    query_started_event_id, command_idempotency_key, claimed_at,
  )
  let profile = port.recovery_profile()
  if profile.digest != candidate.claim.provider_profile_digest ||
    !profile.supports_authoritative_query() {
    raise RecoveryViolation(field="callback_reconciliation_profile_v3")
  }
  match commit_callback_reconciliation_candidate_v3(store, candidate) {
    CallbackReconciliationAlreadyCommittedV3 =>
      {
        disposition: CallbackGuardedRecoveryQueryAlreadyCommittedV3,
        reconciliation_claim_ref: Some(candidate.claim.reconciliation_claim_ref),
        query_start_ref: Some(candidate.started.query_start_ref),
        callback_record_ref: Some(candidate.callback_record_ref),
        provider_evidence: None,
        result_persisted: false,
      }
    CallbackReconciliationRaceLostV3 =>
      {
        disposition: CallbackGuardedRecoveryQueryRaceLostNoCallV3,
        reconciliation_claim_ref: None,
        query_start_ref: None,
        callback_record_ref: Some(candidate.callback_record_ref),
        provider_evidence: None,
        result_persisted: false,
      }
    CallbackReconciliationGuardRejectedV3 =>
      {
        disposition: CallbackGuardedRecoveryQueryGuardChangedNoCallV3,
        reconciliation_claim_ref: None,
        query_start_ref: None,
        callback_record_ref: Some(candidate.callback_record_ref),
        provider_evidence: None,
        result_persisted: false,
      }
    CallbackReconciliationFreshV3 => {
      let durable_work = store.replay(candidate.claim.workflow)
      let durable_governance = store.replay_registered_guard(
        candidate.claim.governance_workflow,
      )
      let durable_evidence = store.replay_registered_guard(
        candidate.evidence_workflow,
      )
      require_callback_reconciliation_candidate_replay_v3(
        candidate, durable_work, durable_governance, durable_evidence,
      )
      let call = guarded_recovery_query_call_v3(
        candidate.dispatch,
        candidate.claim,
        candidate.started,
        durable_work.replay_digest(),
      )
      let (normalized_outcome, normalized_evidence) = normalize_provider_query_result_v3(
        port.query_guarded_effect(call),
        candidate.dispatch,
        candidate.claim,
        observed_at,
      ) catch {
        _ => (ReconciliationUnknownV3, None)
      }
      let (outcome, evidence) = if normalized_outcome ==
        ReconciliationConfirmedNotAppliedV3 &&
        !profile.supports_authoritative_tombstone() {
        (ReconciliationUnknownV3, None)
      } else {
        (normalized_outcome, normalized_evidence)
      }
      let persisted = persist_callback_reconciliation_result_v3(
        store, candidate, outcome, evidence, result_id, result_event_id, auxiliary_event_id,
        observed_at,
      )
      {
        disposition: CallbackGuardedRecoveryQueryObservedV3(outcome),
        reconciliation_claim_ref: Some(candidate.claim.reconciliation_claim_ref),
        query_start_ref: Some(candidate.started.query_start_ref),
        callback_record_ref: Some(candidate.callback_record_ref),
        provider_evidence: evidence,
        result_persisted: persisted,
      }
    }
  }
}

///|
pub fn CallbackReconciliationCandidateV3::record_ref(
  self : CallbackReconciliationCandidateV3,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn CallbackReconciliationCandidateV3::claim_ref(
  self : CallbackReconciliationCandidateV3,
) -> @contracts.RecordRef {
  self.claim.reconciliation_claim_ref
}

///|
pub fn CallbackReconciliationCandidateV3::query_start_ref(
  self : CallbackReconciliationCandidateV3,
) -> @contracts.RecordRef {
  self.started.query_start_ref
}

///|
pub fn CallbackReconciliationCandidateV3::callback_record_ref(
  self : CallbackReconciliationCandidateV3,
) -> @contracts.RecordRef {
  self.callback_record_ref
}

///|
pub fn CallbackReconciliationCandidateV3::evidence_workflow(
  self : CallbackReconciliationCandidateV3,
) -> @contracts.RecordRef {
  self.evidence_workflow
}

///|
pub fn CallbackReconciliationCandidateV3::owner(
  self : CallbackReconciliationCandidateV3,
) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn CallbackReconciliationCandidateV3::fencing_token(
  self : CallbackReconciliationCandidateV3,
) -> Int64 {
  self.fencing_token
}

///|
pub fn CallbackReconciliationCandidateV3::canonical_bytes(
  self : CallbackReconciliationCandidateV3,
) -> Bytes {
  self.canonical
}

///|
pub fn CallbackReconciliationCandidateV3::digest(
  self : CallbackReconciliationCandidateV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn CallbackGuardedRecoveryQueryResultV3::disposition(
  self : CallbackGuardedRecoveryQueryResultV3,
) -> CallbackGuardedRecoveryQueryDispositionV3 {
  self.disposition
}

///|
pub fn CallbackGuardedRecoveryQueryResultV3::reconciliation_claim_ref(
  self : CallbackGuardedRecoveryQueryResultV3,
) -> @contracts.RecordRef? {
  self.reconciliation_claim_ref
}

///|
pub fn CallbackGuardedRecoveryQueryResultV3::query_start_ref(
  self : CallbackGuardedRecoveryQueryResultV3,
) -> @contracts.RecordRef? {
  self.query_start_ref
}

///|
pub fn CallbackGuardedRecoveryQueryResultV3::callback_record_ref(
  self : CallbackGuardedRecoveryQueryResultV3,
) -> @contracts.RecordRef? {
  self.callback_record_ref
}

///|
pub fn CallbackGuardedRecoveryQueryResultV3::provider_evidence(
  self : CallbackGuardedRecoveryQueryResultV3,
) -> ProviderQueryEvidenceV3? {
  self.provider_evidence
}

///|
pub fn CallbackGuardedRecoveryQueryResultV3::result_persisted(
  self : CallbackGuardedRecoveryQueryResultV3,
) -> Bool {
  self.result_persisted
}
