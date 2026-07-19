///|
/// Opaque one-head dispatch-claim proposal. Its guarded request is inaccessible
/// outside this package and can only be prepared from a joint recovery view.
priv struct DispatchClaimCommitCandidateV3 {
  claim : DispatchClaimRecordV3
  request : @storage.CommitRequest
  guarded_request : @storage.GuardedCommitRequest
  empty_effects : @effects.EffectsProjection
  governance_replay : @storage.ReplayResult
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
/// Unified package-local dispatch source. Legacy effects are reconstructed by
/// the existing strict effects projection; V3 retries are reconstructed from
/// the exact retry-intent + schedule + outbox transaction. Neither branch is
/// caller-created authority.
struct DispatchSourceTargetV3 {
  intent_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  outbox_ref : @contracts.RecordRef
  provider_operation : @contracts.WireEnvelope
  external_idempotency_key : String
  capability_ref : @contracts.RecordRef
  capability_kind : String
  permitted_evidence : ReadOnlyArray[@contracts.EvidenceRef]
  authoritative_replay_digest : @contracts.ContentDigest
  retry_due_at : Int64?
  retry_deadline : Int64?
}

///|
fn CurrentGovernedRecoveryProjectionV3::retry_dispatch_target_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  retry_intent_ref : @contracts.RecordRef,
) -> DispatchSourceTargetV3? raise OrchestrationError {
  let matches : Array[(RecoveryRetryScheduledV3, @storage.WorkflowEvent)] = []
  for event in self.work_replay.events() {
    if event.payload().envelope_kind() == recovery_retry_scheduled_event_kind_v3 {
      let schedule = decode_recovery_retry_scheduled_v3(
        event.payload().payload(),
      )
      if schedule.retry_intent.retry_intent_ref == retry_intent_ref {
        if recovery_retry_event_consumption_v3(event, self.work_replay) != 1 {
          raise ReplayBindingViolation(field="recovery_retry_dispatch_v3_batch")
        }
        matches.push((schedule, event))
      }
    }
  }
  if matches.length() > 1 {
    raise RecoveryViolation(field="recovery_retry_dispatch_v3_duplicate")
  }
  if matches.is_empty() {
    return None
  }
  let (schedule, _) = matches[0]
  let retry = schedule.retry_intent
  let outboxes = self.work_replay
    .intents()
    .filter(outbox => outbox.intent_ref().id() == schedule.outbox_intent_id)
  if outboxes.length() != 1 {
    raise ReplayBindingViolation(field="recovery_retry_dispatch_v3_outbox")
  }
  let outbox = outboxes[0]
  if outbox.workflow() != retry.workflow ||
    outbox.payload() != retry.requested_work ||
    outbox.idempotency_key() != retry.external_idempotency_key ||
    !same_evidence(outbox.evidence(), retry.evidence) ||
    retry.retry_intent_ref.digest() != retry.digest ||
    retry.workflow != self.work_replay.workflow() {
    raise ReplayBindingViolation(field="recovery_retry_dispatch_v3_binding")
  }
  Some({
    intent_ref: retry.retry_intent_ref,
    // The immutable retry intent is also the V3 attempt identity. Its
    // canonical record carries the source attempt and monotonically derived
    // attempt ordinal, so no legacy retry receipt is required.
    attempt_ref: retry.retry_intent_ref,
    governed_subject: retry.governed_subject,
    outbox_ref: outbox.intent_ref(),
    provider_operation: retry.requested_work,
    external_idempotency_key: retry.external_idempotency_key,
    capability_ref: retry.capability_ref,
    capability_kind: retry.capability_kind,
    permitted_evidence: retry.evidence,
    authoritative_replay_digest: self.work_replay.replay_digest(),
    retry_due_at: Some(retry.due_at),
    retry_deadline: Some(retry.deadline),
  })
}

///|
fn CurrentGovernedRecoveryProjectionV3::dispatch_source_target_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> DispatchSourceTargetV3 raise OrchestrationError {
  match self.retry_dispatch_target_v3(intent_ref) {
    Some(target) => target
    None => {
      let target = self.current.work.effects.strict_recovery_target_v3(
        intent_ref,
      ) catch {
        _ => raise ReplayBindingViolation(field="dispatch_claim_v3_target")
      }
      {
        intent_ref: target.intent_ref(),
        attempt_ref: target.attempt_ref(),
        governed_subject: target.governed_subject(),
        outbox_ref: target.outbox_ref(),
        provider_operation: target.provider_operation(),
        external_idempotency_key: target.external_idempotency_key(),
        capability_ref: target.capability_ref(),
        capability_kind: target.capability_kind(),
        permitted_evidence: target.permitted_evidence(),
        authoritative_replay_digest: target.authoritative_replay_digest(),
        retry_due_at: None,
        retry_deadline: None,
      }
    }
  }
}

///|
pub(all) enum RecoveryRetryDispatchabilityV3 {
  RecoveryNotRetryIntentV3
  RecoveryRetryWaitingV3(Int64)
  RecoveryRetryDispatchReadyV3
  RecoveryRetryDispatchExpiredV3(Int64)
  RecoveryRetryAlreadyClaimedV3
}

///|
pub fn CurrentGovernedRecoveryProjectionV3::retry_dispatchability_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  retry_intent_ref : @contracts.RecordRef,
  now : Int64,
) -> RecoveryRetryDispatchabilityV3 raise OrchestrationError {
  if now < 0L {
    raise MalformedInput(field="recovery_retry_dispatch_v3_now")
  }
  guard self.retry_dispatch_target_v3(retry_intent_ref) is Some(target) else {
    return RecoveryNotRetryIntentV3
  }
  if self.current_claim(retry_intent_ref) is Some(_) {
    return RecoveryRetryAlreadyClaimedV3
  }
  guard target.retry_due_at is Some(due_at) &&
    target.retry_deadline is Some(deadline) else {
    raise ReplayBindingViolation(field="recovery_retry_dispatch_v3_timing")
  }
  if now < due_at {
    RecoveryRetryWaitingV3(due_at)
  } else if now > deadline {
    RecoveryRetryDispatchExpiredV3(deadline)
  } else {
    RecoveryRetryDispatchReadyV3
  }
}

///|
fn prepare_dispatch_claim_event_v3(
  current : CurrentGovernedClosedLoopProjectionV2,
  event_id : String,
  claim : DispatchClaimRecordV3,
) -> @storage.WorkflowEvent raise OrchestrationError {
  require_text(event_id, "dispatch_claim_v3_event_id")
  let evidence = [ for value in claim.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    event_id,
    dispatch_claim_event_kind_v3,
    claim.governed_subject,
    phase1b_effect_schema_v22(dispatch_claim_event_kind_v3),
    claim.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=claim.workflow,
    attempt_ref=claim.attempt_ref,
    correlation_ref=claim.workflow.id(),
    causation_ref=claim.intent_ref.id(),
    idempotency_ref=claim.claim_ref.id(),
    previous_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="dispatch_claim_v3_envelope")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    claim.workflow,
    event_id,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    claim.claim_ref.id(),
    envelope,
    evidence,
    previous_event_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="dispatch_claim_v3_event")
  }
}

///|
/// Prepare a single durable dispatch owner. Provider operation, key, owner,
/// lease epoch/fence, and ordinal are all derived; callers supply only stable
/// record IDs, evidence, and bounded times.
fn CurrentGovernedRecoveryProjectionV3::prepare_dispatch_claim_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
  claim_id : String,
  event_id : String,
  command_idempotency_key : String,
  claimed_at : Int64,
  expires_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
) -> DispatchClaimCommitCandidateV3 raise OrchestrationError {
  // Kept as a package-local compatibility parameter for existing white-box
  // fixtures only. Provider permission evidence is always derived from the
  // strict intent below and never from this argument.
  ignore(evidence)
  require_text(command_idempotency_key, "dispatch_claim_v3_command_key")
  ignore(self.current.open_work_authority())
  if self.current_claim(intent_ref) is Some(_) {
    raise RecoveryViolation(field="dispatch_claim_v3_existing_claim")
  }
  let target = self.dispatch_source_target_v3(intent_ref)
  match (target.retry_due_at, target.retry_deadline) {
    (Some(due_at), Some(deadline)) => {
      if claimed_at < due_at {
        raise OrderingViolation(field="recovery_retry_dispatch_v3_not_due")
      }
      if claimed_at > deadline {
        raise AuthorityExpired(expires_at=deadline, observed_at=claimed_at)
      }
    }
    (None, None) =>
      if self.state_for(intent_ref) != @effects.RecoveryDispatchEligibleV3 {
        raise RecoveryViolation(field="dispatch_claim_v3_existing_claim")
      }
    _ => raise ReplayBindingViolation(field="recovery_retry_dispatch_v3_timing")
  }
  guard self.activation_for_capability_v3(
      target.capability_ref,
      target.capability_kind,
    )
    is Some(activation) else {
    raise RecoveryViolation(field="dispatch_claim_v3_not_activated")
  }
  if !activation.profile.supports_automatic_create() {
    raise RecoveryViolation(field="dispatch_claim_v3_manual_only_profile")
  }
  guard self.current.committed_lease_authority_receipt_v2() is Some(lease) else {
    raise RecoveryViolation(field="dispatch_claim_v3_current_lease")
  }
  lease.validate_governed_current_v2(self.current, claimed_at)
  if expires_at <= claimed_at || expires_at > lease.expires_at() {
    raise AuthorityExpired(
      expires_at=lease.expires_at(),
      observed_at=expires_at,
    )
  }
  let claim = make_dispatch_claim_record_v3(
    claim_id,
    self.work_replay.workflow(),
    target.intent_ref,
    target.attempt_ref,
    target.governed_subject,
    target.outbox_ref,
    target.provider_operation,
    target.external_idempotency_key,
    target.capability_ref,
    target.capability_kind,
    activation.activation_ref,
    activation.digest,
    activation.profile.digest,
    event_id,
    event_id + ":invocation-start",
    command_idempotency_key,
    lease.owner(),
    lease.receipt_ref(),
    lease.digest(),
    lease.lease_claimed_ref(),
    lease.lease_claimed_digest(),
    lease.epoch(),
    lease.fencing_token(),
    1L,
    claimed_at,
    expires_at,
    self.current.work_revision,
    self.current.work_head_digest,
    self.current.work_replay_digest,
    self.governance_replay.workflow(),
    self.current.governance_revision,
    self.current.governance_head_digest,
    self.current.governance_replay_digest,
    [
      for value in target.permitted_evidence => value
    ],
  )
  let event = prepare_dispatch_claim_event_v3(self.current, event_id, claim)
  let invocation_event = dispatch_invocation_started_event_v3(claim, event)
  let request = @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    claim.workflow,
    self.current.work_revision,
    command_idempotency_key,
    [event, invocation_event],
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="dispatch_claim_v3_request")
  }
  let guarded_request = guarded_lifecycle_commit_request_v22(
    self.current,
    request,
  )
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/DISPATCH-CLAIM-COMMIT-CANDIDATE-V3/3.0.0")
  writer.bytes(claim.canonical)
  writer.bytes(guarded_request.canonical_bytes())
  let canonical = writer.finish()
  {
    claim,
    request,
    guarded_request,
    empty_effects: self.empty_effects,
    governance_replay: self.governance_replay,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
fn DispatchClaimCommitCandidateV3::claim(
  self : DispatchClaimCommitCandidateV3,
) -> DispatchClaimRecordV3 {
  self.claim
}

///|
fn DispatchClaimCommitCandidateV3::canonical_bytes(
  self : DispatchClaimCommitCandidateV3,
) -> Bytes {
  self.canonical
}

///|
fn DispatchClaimCommitCandidateV3::digest(
  self : DispatchClaimCommitCandidateV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Replay-minted durable ownership evidence. It is explicitly not a reusable
/// provider-call permit; Slice 4 must keep `FreshlyApplied` local to one API.
pub struct CommittedDispatchClaimReceiptV3 {
  receipt_ref : @contracts.RecordRef
  claim : DispatchClaimRecordV3
  committed_event_ref : @contracts.RecordRef
  command_idempotency_key : String
  batch_digest : @contracts.ContentDigest
  committed_work_revision : Int64
  committed_work_replay_digest : @contracts.ContentDigest
  governance_prefix_replay_digest : @contracts.ContentDigest
  recovery_state_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub struct DispatchClaimRaceLossReceiptV3 {
  receipt_ref : @contracts.RecordRef
  claim_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  expected_revision : Int64
  winning_command_key : String
  winning_event_refs : ReadOnlyArray[@contracts.RecordRef]
  winning_event_kinds : ReadOnlyArray[String]
  winning_batch_digest : @contracts.ContentDigest
  winner_prefix_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub struct StaleGovernanceDispatchClaimReceiptV3 {
  receipt_ref : @contracts.RecordRef
  claim_ref : @contracts.RecordRef
  conflict : @storage.GuardConflictReceipt
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
/// Freshness is diagnostic and intentionally carries no invocation token.
priv enum DispatchClaimCommitOutcomeV3 {
  DispatchClaimFreshlyCommittedV3(CommittedDispatchClaimReceiptV3)
  DispatchClaimAlreadyCommittedV3(CommittedDispatchClaimReceiptV3)
  DispatchClaimLostV3(DispatchClaimRaceLossReceiptV3)
  DispatchClaimStaleGovernanceV3(StaleGovernanceDispatchClaimReceiptV3)
}

///|
fn require_dispatch_claim_result_binding_v3(
  candidate : DispatchClaimCommitCandidateV3,
  result : @storage.CommitResult,
) -> Unit raise OrchestrationError {
  if result.workflow() != candidate.request.workflow() ||
    result.command_idempotency_key() !=
    candidate.request.command_idempotency_key() ||
    candidate.request.command_idempotency_key() !=
    candidate.claim.command_idempotency_key ||
    candidate.request.events().length() != 2 ||
    candidate.request.events()[0].event_ref().id() !=
    candidate.claim.dispatch_event_id ||
    candidate.request.events()[1].event_ref().id() !=
    candidate.claim.invocation_event_id {
    raise RecoveryViolation(field="dispatch_claim_v3_commit_result")
  }
}

///|
fn mint_committed_dispatch_claim_receipt_v3(
  store : &@storage.RegistryBoundGuardedStoragePort,
  candidate : DispatchClaimCommitCandidateV3,
  result : @storage.CommitResult,
) -> CommittedDispatchClaimReceiptV3 raise {
  require_dispatch_claim_result_binding_v3(candidate, result)
  let work_replay = store.replay(candidate.claim.workflow)
  // The exact governance replay is part of the opaque joint projection that
  // prepared the candidate. The atomic guard checks this exact digest at the
  // publication linearization point. A filesystem mutation capability cannot
  // and must not read across into the separately registered guard root.
  let governance_replay = candidate.governance_replay
  let committed_revision = candidate.claim.expected_work_revision + 2L
  let work_prefix = verified_prefix_v3(
    work_replay, committed_revision, "dispatch_claim_v3_committed_prefix",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    candidate.claim.expected_governance_revision,
    "dispatch_claim_v3_committed_governance_prefix",
  )
  let projection = fold_governed_recovery_v3(
    candidate.empty_effects,
    work_prefix,
    governance_prefix,
  )
  guard projection.current_claim(candidate.claim.intent_ref) is Some(replayed) else {
    raise RecoveryViolation(field="dispatch_claim_v3_committed_missing")
  }
  if replayed.canonical != candidate.claim.canonical ||
    replayed.digest != candidate.claim.digest {
    raise RecoveryViolation(field="dispatch_claim_v3_committed_bytes")
  }
  let matching = work_prefix
    .committed_batches()
    .filter(batch => {
      batch.expected_revision() == candidate.claim.expected_work_revision &&
      batch.command_idempotency_key() == candidate.claim.command_idempotency_key &&
      batch.event_refs().length() == 2 &&
      batch.event_refs()[0].id() == candidate.claim.dispatch_event_id &&
      batch.event_refs()[1].id() == candidate.claim.invocation_event_id &&
      batch.intent_refs().is_empty()
    })
  if matching.length() != 1 ||
    matching[0].batch_digest() != result.batch_digest() ||
    result.workflow_revision() != committed_revision {
    raise RecoveryViolation(field="dispatch_claim_v3_committed_batch")
  }
  let event_ref = matching[0].event_refs()[0]
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-DISPATCH-CLAIM-RECEIPT-V3/3.0.0")
  write_ref(writer, candidate.claim.claim_ref)
  writer.bytes(candidate.claim.canonical)
  write_ref(writer, event_ref)
  writer.string(candidate.request.command_idempotency_key())
  writer.string(result.batch_digest().text())
  writer.int64(committed_revision)
  writer.string(work_prefix.replay_digest().text())
  writer.string(governance_prefix.replay_digest().text())
  writer.string(projection.state_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref_v3(
      "orchestration-committed-dispatch-claim-receipt-v3",
      candidate.claim.claim_ref.id(),
      digest,
    ),
    claim: candidate.claim,
    committed_event_ref: event_ref,
    command_idempotency_key: candidate.request.command_idempotency_key(),
    batch_digest: result.batch_digest(),
    committed_work_revision: committed_revision,
    committed_work_replay_digest: work_prefix.replay_digest(),
    governance_prefix_replay_digest: governance_prefix.replay_digest(),
    recovery_state_digest: projection.state_digest,
    canonical,
    digest,
  }
}

///|
fn dispatch_claim_race_loss_receipt_v3(
  candidate : DispatchClaimCommitCandidateV3,
  replay : @storage.ReplayResult,
) -> DispatchClaimRaceLossReceiptV3 raise OrchestrationError {
  guard @replay.lifecycle_contest(
      replay,
      candidate.claim.expected_work_revision,
      Some(candidate.claim.expected_work_head_digest),
    )
    is Some(contest) else {
    raise RecoveryViolation(field="dispatch_claim_v3_race_batch")
  }
  let batch = contest.batch()
  let kinds = [
    for event in contest.events() => event.payload().envelope_kind()
  ]
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/DISPATCH-CLAIM-RACE-LOSS-RECEIPT-V3/3.0.0")
  write_ref(writer, candidate.claim.claim_ref)
  write_ref(writer, candidate.claim.workflow)
  writer.int64(candidate.claim.expected_work_revision)
  writer.string(batch.command_key())
  writer.string(batch.batch_digest().text())
  writer.count(batch.event_refs().length())
  for event_ref in batch.event_refs() {
    write_ref(writer, event_ref)
  }
  writer.count(kinds.length())
  for kind in kinds {
    writer.string(kind)
  }
  writer.string(contest.winner_prefix_replay_digest().text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref_v3(
      "orchestration-dispatch-claim-race-loss-receipt-v3",
      candidate.claim.claim_ref.id(),
      digest,
    ),
    claim_ref: candidate.claim.claim_ref,
    workflow: candidate.claim.workflow,
    expected_revision: candidate.claim.expected_work_revision,
    winning_command_key: batch.command_key(),
    winning_event_refs: batch.event_refs(),
    winning_event_kinds: ReadOnlyArray::from_array(kinds),
    winning_batch_digest: batch.batch_digest(),
    winner_prefix_replay_digest: contest.winner_prefix_replay_digest(),
    canonical,
    digest,
  }
}

///|
fn stale_governance_dispatch_claim_receipt_v3(
  candidate : DispatchClaimCommitCandidateV3,
  conflict : @storage.GuardConflictReceipt,
) -> StaleGovernanceDispatchClaimReceiptV3 raise OrchestrationError {
  if conflict.request_digest() != candidate.guarded_request.digest() ||
    conflict.mutation_workflow() != candidate.claim.workflow ||
    conflict.command_idempotency_key() !=
    candidate.request.command_idempotency_key() {
    raise ReplayBindingViolation(field="dispatch_claim_v3_guard_conflict")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/STALE-GOVERNANCE-DISPATCH-CLAIM-RECEIPT-V3/3.0.0")
  write_ref(writer, candidate.claim.claim_ref)
  writer.bytes(conflict.canonical_bytes())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref_v3(
      "orchestration-stale-governance-dispatch-claim-receipt-v3",
      candidate.claim.claim_ref.id(),
      digest,
    ),
    claim_ref: candidate.claim.claim_ref,
    conflict,
    canonical,
    digest,
  }
}

///|
/// Commit one dispatch owner with classified publication freshness. Neither
/// successful branch is a provider-call API or reusable invocation permit.
fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_dispatch_claim_v3(
  store : S,
  candidate : DispatchClaimCommitCandidateV3,
) -> DispatchClaimCommitOutcomeV3 raise {
  require_phase2_governance_guard_profile_v3(store, candidate.guarded_request)
  try {
    match store.classified_guarded_commit(candidate.guarded_request) {
      @storage.FreshlyApplied(result) =>
        DispatchClaimFreshlyCommittedV3(
          mint_committed_dispatch_claim_receipt_v3(store, candidate, result),
        )
      @storage.AlreadyCommitted(result) =>
        DispatchClaimAlreadyCommittedV3(
          mint_committed_dispatch_claim_receipt_v3(store, candidate, result),
        )
      @storage.GuardRejected(conflict) =>
        DispatchClaimStaleGovernanceV3(
          stale_governance_dispatch_claim_receipt_v3(candidate, conflict),
        )
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) =>
      DispatchClaimLostV3(
        dispatch_claim_race_loss_receipt_v3(
          candidate,
          store.replay(candidate.claim.workflow),
        ),
      )
    error => raise error
  }
}

///|
pub fn CommittedDispatchClaimReceiptV3::record_ref(
  self : CommittedDispatchClaimReceiptV3,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn CommittedDispatchClaimReceiptV3::claim(
  self : CommittedDispatchClaimReceiptV3,
) -> DispatchClaimRecordV3 {
  self.claim
}

///|
pub fn CommittedDispatchClaimReceiptV3::canonical_bytes(
  self : CommittedDispatchClaimReceiptV3,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedDispatchClaimReceiptV3::digest(
  self : CommittedDispatchClaimReceiptV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Validate historical ownership against both exact committed prefixes.
pub fn CommittedDispatchClaimReceiptV3::validate_replay_binding(
  self : CommittedDispatchClaimReceiptV3,
  empty : @effects.EffectsProjection,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  if @contracts.sha256_digest(self.canonical) != self.digest ||
    self.receipt_ref.digest() != self.digest {
    raise DigestMismatch(field="dispatch_claim_v3_receipt_integrity")
  }
  let work_prefix = verified_prefix_v3(
    work_replay,
    self.committed_work_revision,
    "dispatch_claim_v3_receipt_work_prefix",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    self.claim.expected_governance_revision,
    "dispatch_claim_v3_receipt_governance_prefix",
  )
  let projection = fold_governed_recovery_v3(
    empty, work_prefix, governance_prefix,
  )
  guard projection.current_claim(self.claim.intent_ref) is Some(claim) else {
    raise ReplayBindingViolation(field="dispatch_claim_v3_receipt_claim")
  }
  if claim.canonical != self.claim.canonical ||
    work_prefix.replay_digest() != self.committed_work_replay_digest ||
    governance_prefix.replay_digest() != self.governance_prefix_replay_digest ||
    projection.state_digest != self.recovery_state_digest ||
    !work_prefix
    .events()
    .any(event => event.event_ref() == self.committed_event_ref) {
    raise ReplayBindingViolation(field="dispatch_claim_v3_receipt_binding")
  }
}

///|
/// Validate current ownership. This proves only that recovery ownership is
/// live; it deliberately does not authorize a provider call.
pub fn CommittedDispatchClaimReceiptV3::validate_current(
  self : CommittedDispatchClaimReceiptV3,
  current : CurrentGovernedRecoveryProjectionV3,
  now : Int64,
) -> Unit raise OrchestrationError {
  self.validate_replay_binding(
    current.empty_effects,
    current.work_replay,
    current.governance_replay,
  )
  guard current.current_claim(self.claim.intent_ref) is Some(claim) else {
    raise RecoveryViolation(field="dispatch_claim_v3_not_current")
  }
  if claim.canonical != self.claim.canonical ||
    now < claim.claimed_at ||
    now >= claim.expires_at {
    raise RecoveryViolation(field="dispatch_claim_v3_not_current")
  }
  guard current.current.committed_lease_authority_receipt_v2() is Some(lease) else {
    raise RecoveryViolation(field="dispatch_claim_v3_lease_not_current")
  }
  lease.validate_governed_current_v2(current.current, now)
  if lease.lease_claimed_ref() != claim.lease_claimed_ref ||
    lease.lease_claimed_digest() != claim.lease_claimed_digest ||
    lease.owner() != claim.owner ||
    lease.epoch() != claim.lease_epoch ||
    lease.fencing_token() != claim.fencing_token {
    raise RecoveryViolation(field="dispatch_claim_v3_lease_not_current")
  }
}

///|
pub fn DispatchClaimRaceLossReceiptV3::winning_event_kinds(
  self : DispatchClaimRaceLossReceiptV3,
) -> ReadOnlyArray[String] {
  self.winning_event_kinds
}

///|
pub fn DispatchClaimRaceLossReceiptV3::canonical_bytes(
  self : DispatchClaimRaceLossReceiptV3,
) -> Bytes {
  self.canonical
}

///|
pub fn StaleGovernanceDispatchClaimReceiptV3::canonical_bytes(
  self : StaleGovernanceDispatchClaimReceiptV3,
) -> Bytes {
  self.canonical
}
