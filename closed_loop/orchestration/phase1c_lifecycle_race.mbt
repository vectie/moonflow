///|
/// Exact, non-overlapping lifecycle batch categories. Terminal cases preserve
/// every `WorkTerminalOutcomeV2` value.
pub(all) enum LifecycleCandidateCategoryV2 {
  CancellationRequestCandidateV2
  LeaseClaimCandidateV2
  SucceededTerminalCandidateV2
  FailedNonRetryableTerminalCandidateV2
  FailedRetryExhaustedTerminalCandidateV2
  FailedCancellationStoppedRetryTerminalCandidateV2
  CancelledBeforeEffectIntentTerminalCandidateV2
  CancelledAfterReconciledNotAppliedTerminalCandidateV2
  ReconciliationRequestCandidateV2
  ReconciliationResolutionCandidateV2
  AtomicRetryCommitCandidateV2
  LeaseExpiryCandidateV2
  LeaseReclaimCandidateV2
} derive(Eq, Debug)

///|
/// Stable reason derived from the complete durable winning batch.
pub(all) enum LifecycleRaceLossReasonV2 {
  LostToCancellationRequestV2
  LostToLeaseClaimV2
  LostToSucceededTerminalV2
  LostToFailedNonRetryableTerminalV2
  LostToFailedRetryExhaustedTerminalV2
  LostToFailedCancellationStoppedRetryTerminalV2
  LostToCancelledBeforeEffectIntentTerminalV2
  LostToCancelledAfterReconciledNotAppliedTerminalV2
  LostToReconciliationRequestV2
  LostToReconciliationResolutionV2
  LostToAtomicRetryCommitV2
  LostToLeaseExpiryV2
  LostToLeaseReclaimV2
  LostToDurableAdvanceV2
} derive(Eq, Debug)

///|
fn LifecycleCandidateCategoryV2::wire(
  self : LifecycleCandidateCategoryV2,
) -> String {
  match self {
    CancellationRequestCandidateV2 => "cancellation_request_v2"
    LeaseClaimCandidateV2 => "lease_claim_v2"
    SucceededTerminalCandidateV2 => "succeeded_terminal_v2"
    FailedNonRetryableTerminalCandidateV2 => "failed_non_retryable_terminal_v2"
    FailedRetryExhaustedTerminalCandidateV2 =>
      "failed_retry_exhausted_terminal_v2"
    FailedCancellationStoppedRetryTerminalCandidateV2 =>
      "failed_cancellation_stopped_retry_terminal_v2"
    CancelledBeforeEffectIntentTerminalCandidateV2 =>
      "cancelled_before_effect_intent_terminal_v2"
    CancelledAfterReconciledNotAppliedTerminalCandidateV2 =>
      "cancelled_after_reconciled_not_applied_terminal_v2"
    ReconciliationRequestCandidateV2 => "reconciliation_request_v2"
    ReconciliationResolutionCandidateV2 => "reconciliation_resolution_v2"
    AtomicRetryCommitCandidateV2 => "atomic_retry_commit_v2"
    LeaseExpiryCandidateV2 => "lease_expiry_v2"
    LeaseReclaimCandidateV2 => "lease_reclaim_v2"
  }
}

///|
fn LifecycleRaceLossReasonV2::wire(self : LifecycleRaceLossReasonV2) -> String {
  match self {
    LostToCancellationRequestV2 => "lost_to_cancellation_request_v2"
    LostToLeaseClaimV2 => "lost_to_lease_claim_v2"
    LostToSucceededTerminalV2 => "lost_to_succeeded_terminal_v2"
    LostToFailedNonRetryableTerminalV2 =>
      "lost_to_failed_non_retryable_terminal_v2"
    LostToFailedRetryExhaustedTerminalV2 =>
      "lost_to_failed_retry_exhausted_terminal_v2"
    LostToFailedCancellationStoppedRetryTerminalV2 =>
      "lost_to_failed_cancellation_stopped_retry_terminal_v2"
    LostToCancelledBeforeEffectIntentTerminalV2 =>
      "lost_to_cancelled_before_effect_intent_terminal_v2"
    LostToCancelledAfterReconciledNotAppliedTerminalV2 =>
      "lost_to_cancelled_after_reconciled_not_applied_terminal_v2"
    LostToReconciliationRequestV2 => "lost_to_reconciliation_request_v2"
    LostToReconciliationResolutionV2 => "lost_to_reconciliation_resolution_v2"
    LostToAtomicRetryCommitV2 => "lost_to_atomic_retry_commit_v2"
    LostToLeaseExpiryV2 => "lost_to_lease_expiry_v2"
    LostToLeaseReclaimV2 => "lost_to_lease_reclaim_v2"
    LostToDurableAdvanceV2 => "lost_to_durable_advance_v2"
  }
}

///|
fn public_lifecycle_category_v2(
  kind : @decision.LifecycleBatchKind,
) -> LifecycleCandidateCategoryV2? {
  match kind {
    CancellationRequest => Some(CancellationRequestCandidateV2)
    LeaseClaim => Some(LeaseClaimCandidateV2)
    SucceededTerminal => Some(SucceededTerminalCandidateV2)
    FailedNonRetryableTerminal => Some(FailedNonRetryableTerminalCandidateV2)
    FailedRetryExhaustedTerminal =>
      Some(FailedRetryExhaustedTerminalCandidateV2)
    FailedCancellationStoppedRetryTerminal =>
      Some(FailedCancellationStoppedRetryTerminalCandidateV2)
    CancelledBeforeEffectIntentTerminal =>
      Some(CancelledBeforeEffectIntentTerminalCandidateV2)
    CancelledAfterReconciledNotAppliedTerminal =>
      Some(CancelledAfterReconciledNotAppliedTerminalCandidateV2)
    ReconciliationRequest => Some(ReconciliationRequestCandidateV2)
    ReconciliationResolution => Some(ReconciliationResolutionCandidateV2)
    AtomicRetryCommit => Some(AtomicRetryCommitCandidateV2)
    LeaseExpiry => Some(LeaseExpiryCandidateV2)
    LeaseReclaim => Some(LeaseReclaimCandidateV2)
    OtherDurableAdvance => None
  }
}

///|
fn public_lifecycle_loss_v2(
  kind : @decision.LifecycleLossKind,
) -> LifecycleRaceLossReasonV2 {
  match kind {
    CancellationCommitted => LostToCancellationRequestV2
    ClaimCommitted => LostToLeaseClaimV2
    SucceededTerminalCommitted => LostToSucceededTerminalV2
    FailedNonRetryableTerminalCommitted => LostToFailedNonRetryableTerminalV2
    FailedRetryExhaustedTerminalCommitted =>
      LostToFailedRetryExhaustedTerminalV2
    FailedCancellationStoppedRetryTerminalCommitted =>
      LostToFailedCancellationStoppedRetryTerminalV2
    CancelledBeforeEffectIntentTerminalCommitted =>
      LostToCancelledBeforeEffectIntentTerminalV2
    CancelledAfterReconciledNotAppliedTerminalCommitted =>
      LostToCancelledAfterReconciledNotAppliedTerminalV2
    ReconciliationRequestCommitted => LostToReconciliationRequestV2
    ReconciliationResolutionCommitted => LostToReconciliationResolutionV2
    RetryCommitted => LostToAtomicRetryCommitV2
    LeaseExpiryCommitted => LostToLeaseExpiryV2
    LeaseReclaimCommitted => LostToLeaseReclaimV2
    OtherDurableAdvanceCommitted => LostToDurableAdvanceV2
  }
}

///|
fn terminal_outcome_for_events_v2(
  events : ArrayView[@storage.WorkflowEvent],
) -> String? raise OrchestrationError {
  for event in events {
    if event.payload().envelope_kind() == work_terminal_event_kind_v22 {
      let terminal = decode_work_terminal_record_v22(
        event.payload().subject(),
        event.payload().payload(),
      )
      return Some(terminal.outcome.wire())
    }
  }
  None
}

///|
fn classify_lifecycle_events_v2(
  events : ArrayView[@storage.WorkflowEvent],
) -> @decision.LifecycleBatchKind raise OrchestrationError {
  let kinds = [ for event in events => event.payload().envelope_kind() ]
  @decision.classify_lifecycle_batch(
    kinds,
    terminal_outcome_for_events_v2(events),
  )
}

///|
/// Opaque sealed candidate. Public callers obtain one only from an existing
/// reviewed/guarded domain preparer; raw commit requests cannot be sealed.
pub struct LifecycleCommitCandidateV2 {
  candidate_ref : @contracts.RecordRef
  category : LifecycleCandidateCategoryV2
  request : @storage.CommitRequest
  guarded_request : @storage.GuardedCommitRequest
  expected_head_digest : @contracts.ContentDigest?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn seal_lifecycle_candidate_v2(
  category : LifecycleCandidateCategoryV2,
  guarded_request : @storage.GuardedCommitRequest,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  let request = guarded_request.mutation()
  let actual = classify_lifecycle_events_v2(request.events())
  guard public_lifecycle_category_v2(actual) is Some(reviewed) &&
    reviewed == category else {
    raise ReplayBindingViolation(field="lifecycle_candidate_batch_shape")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LIFECYCLE-COMMIT-CANDIDATE-V2/2.2.0")
  writer.string(category.wire())
  writer.bytes(guarded_request.canonical_bytes())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    candidate_ref: self_ref_v22(
      "orchestration-lifecycle-commit-candidate-v2",
      request.command_idempotency_key(),
      digest,
    ),
    category,
    request,
    guarded_request,
    expected_head_digest: request.events()[0].previous_event_digest(),
    canonical,
    digest,
  }
}

///|
/// Bind every authority-bearing lifecycle mutation to the exact governance
/// replay from which its governed currentness was derived.
fn guarded_lifecycle_commit_request_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  request : @storage.CommitRequest,
) -> @storage.GuardedCommitRequest raise OrchestrationError {
  let workflow = current.root_binding.workflow
  let governed_subject = current.root_binding.registration
    .schedule()
    .admission()
    .governance()
    .governed_subject()
  if request.workflow() != current.root_binding.workflow ||
    request.expected_revision() != current.work_revision ||
    request.events().is_empty() ||
    request.events()[0].previous_event_digest() !=
    Some(current.work_head_digest) {
    raise ReplayBindingViolation(field="lifecycle_candidate_work_current")
  }
  for event in request.events() {
    if event.workflow() != workflow ||
      event.payload().run_ref() != Some(workflow) ||
      event.payload().correlation_ref() != Some(workflow.id()) {
      raise WorkflowMismatch(field="lifecycle_candidate_workflow")
    }
  }
  // This value is deliberately derived here from the same current that
  // provides both storage heads. Family-specific factories below compare
  // their typed source to it before the guarded request can be sealed.
  ignore(governed_subject)
  let head_guard = @storage.WorkflowHeadGuard::new(
    current.root_binding.governance_stream_ref(),
    current.governance_revision,
    current.governance_head_digest,
    current.governance_replay_digest,
  ) catch {
    _ => raise ReplayBindingViolation(field="lifecycle_governance_guard")
  }
  @storage.GuardedCommitRequest::new(request, [head_guard]) catch {
    _ => raise ReplayBindingViolation(field="lifecycle_governance_guard")
  }
}

///|
fn lifecycle_current_governed_subject_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
) -> @contracts.RecordRef {
  current.root_binding.registration
  .schedule()
  .admission()
  .governance()
  .governed_subject()
}

///|
fn require_lifecycle_cancellation_identity_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  request : CancellationRequestV2,
) -> Unit raise OrchestrationError {
  if request.workflow() != current.root_binding.workflow ||
    request.governed_subject() !=
    lifecycle_current_governed_subject_v22(current) {
    raise ReplayBindingViolation(field="lifecycle_candidate_governed_subject")
  }
}

///|
fn require_lifecycle_terminal_identity_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  prepared : PreparedWorkTerminalV2,
) -> Unit raise OrchestrationError {
  let events = prepared.commit_request.events()
  guard events.length() == 1 else {
    raise ReplayBindingViolation(field="lifecycle_candidate_batch_shape")
  }
  let terminal = decode_work_terminal_record_v22(
    events[0].payload().subject(),
    events[0].payload().payload(),
  )
  if terminal.workflow != current.root_binding.workflow ||
    terminal.governed_subject != lifecycle_current_governed_subject_v22(current) ||
    terminal.prefix_revision != current.work_revision ||
    terminal.previous_digest != current.work_head_digest {
    raise ReplayBindingViolation(field="lifecycle_candidate_governed_subject")
  }
}

///|
fn require_lifecycle_atomic_retry_identity_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  admission : AdmissionV2,
  governance : @effects.GovernanceBinding,
  requested_work : @contracts.WireEnvelope,
) -> Unit raise OrchestrationError {
  let workflow = current.root_binding.workflow
  let governed_subject = lifecycle_current_governed_subject_v22(current)
  if governance.workflow() != workflow ||
    governance.governed_subject() != governed_subject ||
    admission.planned().workflow() != workflow ||
    admission.planned().subject() != governed_subject ||
    requested_work.subject() != governed_subject {
    raise ReplayBindingViolation(field="lifecycle_candidate_governed_subject")
  }
}

///|
fn lifecycle_candidate_from_prepared_cancellation_v22(
  prepared : PreparedCancellationV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  seal_lifecycle_candidate_v2(
    CancellationRequestCandidateV2,
    guarded_lifecycle_commit_request_v22(current, prepared.commit_request),
  )
}

///|
fn lifecycle_terminal_category_v22(
  outcome : WorkTerminalOutcomeV2,
) -> LifecycleCandidateCategoryV2 {
  match outcome {
    SucceededV2 => SucceededTerminalCandidateV2
    FailedNonRetryableV2 => FailedNonRetryableTerminalCandidateV2
    FailedRetryExhaustedV2 => FailedRetryExhaustedTerminalCandidateV2
    FailedCancellationStoppedRetryV2 =>
      FailedCancellationStoppedRetryTerminalCandidateV2
    CancelledBeforeEffectIntentV2 =>
      CancelledBeforeEffectIntentTerminalCandidateV2
    CancelledAfterReconciledNotAppliedV2 =>
      CancelledAfterReconciledNotAppliedTerminalCandidateV2
  }
}

///|
fn lifecycle_candidate_from_prepared_terminal_v22(
  prepared : PreparedWorkTerminalV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  seal_lifecycle_candidate_v2(
    lifecycle_terminal_category_v22(prepared.outcome()),
    guarded_lifecycle_commit_request_v22(current, prepared.commit_request),
  )
}

///|
fn lifecycle_candidate_from_guarded_atomic_retry_v22(
  guarded : GuardedAtomicRetryV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  guarded.authorization.require_current_scope(
    current,
    current.open_work_authority(),
    "retry.commit",
    guarded.prepared.registration().record_ref(),
  )
  seal_lifecycle_candidate_v2(
    AtomicRetryCommitCandidateV2,
    guarded_lifecycle_commit_request_v22(current, guarded.prepared.request()),
  )
}

///|
/// Prepare, governance-guard, and seal cancellation from one exact governed
/// current. The prepared mutation never crosses the public API boundary.
fn prepare_lifecycle_cancellation_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  request : CancellationRequestV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  require_lifecycle_cancellation_identity_v22(current, request)
  lifecycle_candidate_from_prepared_cancellation_v22(
    prepare_cancellation_v2(current, request),
    current,
  )
}

///|
fn prepare_lifecycle_succeeded_work_terminal_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  source : @effects.CommittedEffectTerminalSourceV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  let prepared = prepare_succeeded_work_terminal_v2(current, source)
  require_lifecycle_terminal_identity_v22(current, prepared)
  lifecycle_candidate_from_prepared_terminal_v22(prepared, current)
}

///|
fn prepare_lifecycle_cancelled_after_reconciled_not_applied_work_terminal_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  source : @effects.CommittedEffectTerminalSourceV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  let prepared = prepare_cancelled_after_reconciled_not_applied_work_terminal_v2(
    current, source,
  )
  require_lifecycle_terminal_identity_v22(current, prepared)
  lifecycle_candidate_from_prepared_terminal_v22(prepared, current)
}

///|
fn prepare_lifecycle_failed_work_terminal_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  source : @effects.CommittedEffectTerminalSourceV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  let prepared = prepare_failed_work_terminal_v2(current, source)
  require_lifecycle_terminal_identity_v22(current, prepared)
  lifecycle_candidate_from_prepared_terminal_v22(prepared, current)
}

///|
fn prepare_lifecycle_retry_proven_failure_work_terminal_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  let prepared = prepare_retry_proven_failure_work_terminal_v2(current, receipt)
  require_lifecycle_terminal_identity_v22(current, prepared)
  lifecycle_candidate_from_prepared_terminal_v22(prepared, current)
}

///|
fn prepare_lifecycle_retry_exhausted_work_terminal_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  let prepared = prepare_retry_exhausted_work_terminal_v2(current, receipt)
  require_lifecycle_terminal_identity_v22(current, prepared)
  lifecycle_candidate_from_prepared_terminal_v22(prepared, current)
}

///|
/// Prepare the target-bound atomic retry and seal its exact mutation under the
/// governance head of the same current. A prebuilt `GuardedAtomicRetryV2`
/// cannot be supplied by callers.
pub fn prepare_lifecycle_atomic_retry_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  guarded_request : GuardedRetryScheduleRequestV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
  policy : RetryPolicyV2,
  admission : AdmissionV2,
  governance : @effects.GovernanceBinding,
  plan_id : String,
  attempt_id : String,
  attempt_event_id : String,
  attempt_idempotency_key : String,
  requested_work : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  created_at : Int64,
  schedule_id : String,
  schedule_idempotency_key : String,
  schedule_deadline : Int64,
  schedule_event_id : String,
  registration_id : String,
  command_idempotency_key : String,
) -> LifecycleCommitCandidateV2 raise {
  require_lifecycle_atomic_retry_identity_v22(
    current, admission, governance, requested_work,
  )
  let guarded = prepare_guarded_atomic_retry_v2(
    current, open, guarded_request, receipt, policy, admission, governance, plan_id,
    attempt_id, attempt_event_id, attempt_idempotency_key, requested_work, evidence,
    created_at, schedule_id, schedule_idempotency_key, schedule_deadline, schedule_event_id,
    registration_id, command_idempotency_key,
  )
  lifecycle_candidate_from_guarded_atomic_retry_v22(guarded, current)
}

///|
/// Guard and seal a lease claim without exposing a raw-request sealing path.
pub fn prepare_lifecycle_lease_claim_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  authorization : OpenWorkOperationAuthorizationV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  claimed : LeaseClaimedV2,
) -> LifecycleCommitCandidateV2 raise {
  let request = prepare_guarded_lease_claimed_v2(
    current, open, authorization, event_id, event_idempotency_key, command_idempotency_key,
    claimed,
  )
  seal_lifecycle_candidate_v2(
    LeaseClaimCandidateV2,
    guarded_lifecycle_commit_request_v22(current, request),
  )
}

///|
pub fn prepare_lifecycle_reconciliation_request_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : InFlightResolutionAuthorityV2,
  event_id : String,
  command_idempotency_key : String,
  request : @effects.ReconciliationRequest,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  seal_lifecycle_candidate_v2(
    ReconciliationRequestCandidateV2,
    guarded_lifecycle_commit_request_v22(
      current,
      prepare_guarded_reconciliation_request_v2(
        current, authorization, event_id, command_idempotency_key, request,
      ),
    ),
  )
}

///|
pub fn prepare_lifecycle_reconciliation_resolution_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : InFlightResolutionAuthorityV2,
  event_id : String,
  command_idempotency_key : String,
  reconciliation : @effects.ReconciliationRecord,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  seal_lifecycle_candidate_v2(
    ReconciliationResolutionCandidateV2,
    guarded_lifecycle_commit_request_v22(
      current,
      prepare_guarded_reconciliation_resolution_v2(
        current, authorization, event_id, command_idempotency_key, reconciliation,
      ),
    ),
  )
}

///|
pub fn prepare_lifecycle_lease_expiry_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : LeaseSettlementAuthorizationV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  expiry : LeaseExpiryV2,
) -> LifecycleCommitCandidateV2 raise {
  seal_lifecycle_candidate_v2(
    LeaseExpiryCandidateV2,
    guarded_lifecycle_commit_request_v22(
      current,
      prepare_guarded_lease_expired_v2(
        current, authorization, event_id, event_idempotency_key, command_idempotency_key,
        expiry,
      ),
    ),
  )
}

///|
pub fn prepare_lifecycle_lease_reclaim_candidate_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  authorization : OpenWorkOperationAuthorizationV2,
  event_id : String,
  event_idempotency_key : String,
  command_idempotency_key : String,
  reclaim : LeaseReclaimV2,
) -> LifecycleCommitCandidateV2 raise {
  seal_lifecycle_candidate_v2(
    LeaseReclaimCandidateV2,
    guarded_lifecycle_commit_request_v22(
      current,
      prepare_guarded_lease_reclaimed_v2(
        current, open, authorization, event_id, event_idempotency_key, command_idempotency_key,
        reclaim,
      ),
    ),
  )
}

///|
pub(all) enum RetryPreparationStatusV2 {
  RetryPreparationCurrentV2
  RetryPreparationStaleAfterCancellationV2
  RetryPreparationStaleAfterTerminalV2
  RetryPreparationStaleAfterDurableAdvanceV2
} derive(Eq, Debug)

///|
/// Diagnostic currentness for a pure retry preparation. It carries no commit
/// request and cannot grant or mint later authority.
pub struct RetryPreparationCurrentnessV2 {
  request_ref : @contracts.RecordRef
  open : OpenWorkAuthorityV2
  authorization : OpenWorkOperationAuthorizationV2
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn GuardedRetryScheduleRequestV2::retry_preparation_currentness(
  self : GuardedRetryScheduleRequestV2,
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
) -> RetryPreparationCurrentnessV2 raise OrchestrationError {
  self.authorization.require_current_scope(
    current,
    open,
    "retry.request",
    self.request.request_ref(),
  )
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/RETRY-PREPARATION-CURRENTNESS-V2/2.2.0")
  write_ref(writer, self.request.request_ref())
  writer.int64(current.work_revision)
  writer.string(current.work_head_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    request_ref: self.request.request_ref(),
    open,
    authorization: self.authorization,
    work_revision: current.work_revision,
    work_head_digest: current.work_head_digest,
    canonical,
    digest,
  }
}

///|
pub fn RetryPreparationCurrentnessV2::validate_current(
  self : RetryPreparationCurrentnessV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> RetryPreparationStatusV2 raise OrchestrationError {
  if current.root_binding.workflow != self.open.workflow {
    raise WorkflowMismatch(field="retry_preparation_currentness_workflow")
  }
  if current.work_revision == self.work_revision &&
    current.work_head_digest == self.work_head_digest {
    self.authorization.require_current_scope(
      current,
      self.open,
      "retry.request",
      self.request_ref,
    )
    return RetryPreparationCurrentV2
  }
  if current.work.cancellation is Some(_) {
    return RetryPreparationStaleAfterCancellationV2
  }
  if current.work.work_terminal is Some(_) {
    return RetryPreparationStaleAfterTerminalV2
  }
  try
    self.authorization.require_current_scope(
      current,
      self.open,
      "retry.request",
      self.request_ref,
    )
  catch {
    CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
      RetryPreparationStaleAfterDurableAdvanceV2
    error => raise error
  } noraise {
    _ => RetryPreparationCurrentV2
  }
}

///|
pub fn RetryPreparationCurrentnessV2::canonical_bytes(
  self : RetryPreparationCurrentnessV2,
) -> Bytes {
  self.canonical
}

///|
pub fn RetryPreparationCurrentnessV2::digest(
  self : RetryPreparationCurrentnessV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn LifecycleCommitCandidateV2::record_ref(
  self : LifecycleCommitCandidateV2,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn LifecycleCommitCandidateV2::category(
  self : LifecycleCommitCandidateV2,
) -> LifecycleCandidateCategoryV2 {
  self.category
}

///|
pub fn LifecycleCommitCandidateV2::canonical_bytes(
  self : LifecycleCommitCandidateV2,
) -> Bytes {
  self.canonical
}

///|
pub fn LifecycleCommitCandidateV2::digest(
  self : LifecycleCommitCandidateV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct CommittedLifecycleCandidateReceiptV2 {
  candidate_ref : @contracts.RecordRef
  category : LifecycleCandidateCategoryV2
  workflow : @contracts.RecordRef
  expected_revision : Int64
  expected_head_digest : @contracts.ContentDigest?
  first_sequence : Int64
  last_sequence : Int64
  committed_revision : Int64
  event_refs : ReadOnlyArray[@contracts.RecordRef]
  batch_digest : @contracts.ContentDigest
  committed_prefix_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub struct LifecycleRaceLossReceiptV2 {
  receipt_ref : @contracts.RecordRef
  candidate_ref : @contracts.RecordRef
  losing_category : LifecycleCandidateCategoryV2
  reason : LifecycleRaceLossReasonV2
  winning_category : LifecycleCandidateCategoryV2?
  workflow : @contracts.RecordRef
  expected_revision : Int64
  expected_head_digest : @contracts.ContentDigest?
  winner_first_sequence : Int64
  winner_last_sequence : Int64
  winner_start_revision : Int64
  winner_end_revision : Int64
  observed_head_revision : Int64
  observed_head_digest : @contracts.ContentDigest?
  winner_command_key : String
  winner_event_refs : ReadOnlyArray[@contracts.RecordRef]
  winner_event_kinds : ReadOnlyArray[String]
  winner_batch_digest : @contracts.ContentDigest
  source_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
/// Non-durable, non-authorizing observation that the exact governance replay
/// bound into a sealed lifecycle candidate was no longer current at the
/// storage linearization point.
pub struct StaleGovernanceLifecycleReceiptV2 {
  receipt_ref : @contracts.RecordRef
  candidate_ref : @contracts.RecordRef
  category : LifecycleCandidateCategoryV2
  conflict : @storage.GuardConflictReceipt
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub(all) enum LifecycleCommitOutcomeV2 {
  LifecycleCommittedV2(CommittedLifecycleCandidateReceiptV2)
  LifecycleLostV2(LifecycleRaceLossReceiptV2)
  LifecycleStaleGovernanceV2(StaleGovernanceLifecycleReceiptV2)
}

///|
fn require_lifecycle_replay_workflow_v2(
  candidate : LifecycleCommitCandidateV2,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  if replay.workflow() != candidate.request.workflow() ||
    replay.head().workflow() != candidate.request.workflow() {
    raise WorkflowMismatch(field="lifecycle_commit_replay_workflow")
  }
}

///|
fn stale_governance_lifecycle_receipt_v2(
  candidate : LifecycleCommitCandidateV2,
  conflict : @storage.GuardConflictReceipt,
) -> StaleGovernanceLifecycleReceiptV2 raise OrchestrationError {
  if conflict.request_digest() != candidate.guarded_request.digest() ||
    conflict.mutation_workflow() != candidate.request.workflow() ||
    conflict.command_idempotency_key() !=
    candidate.request.command_idempotency_key() {
    raise ReplayBindingViolation(field="lifecycle_governance_conflict_binding")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/STALE-GOVERNANCE-LIFECYCLE-RECEIPT-V2/2.2.0")
  write_ref(writer, candidate.candidate_ref)
  writer.string(candidate.category.wire())
  writer.string(conflict.digest().text())
  writer.bytes(conflict.canonical_bytes())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  let id = "\{candidate.candidate_ref.id()}:stale-governance:\{conflict.digest().text()}"
  {
    receipt_ref: self_ref_v22(
      "orchestration-stale-governance-lifecycle-receipt-v2", id, digest,
    ),
    candidate_ref: candidate.candidate_ref,
    category: candidate.category,
    conflict,
    canonical,
    digest,
  }
}

///|
fn committed_lifecycle_receipt_v2(
  candidate : LifecycleCommitCandidateV2,
  result : @storage.CommitResult,
  replay : @storage.ReplayResult,
) -> CommittedLifecycleCandidateReceiptV2 raise OrchestrationError {
  require_lifecycle_replay_workflow_v2(candidate, replay)
  if result.workflow() != candidate.request.workflow() ||
    result.command_idempotency_key() !=
    candidate.request.command_idempotency_key() {
    raise RecoveryViolation(field="committed_lifecycle_result_binding")
  }
  guard @replay.lifecycle_contest(
      replay,
      candidate.request.expected_revision(),
      candidate.expected_head_digest,
    )
    is Some(contest) else {
    raise RecoveryViolation(field="committed_lifecycle_batch_missing")
  }
  let batch = contest.batch()
  let events = contest.events()
  if result.batch_digest() != batch.batch_digest() ||
    result.workflow_revision() != contest.winner_head_revision() {
    raise RecoveryViolation(field="committed_lifecycle_batch_binding")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-LIFECYCLE-CANDIDATE-RECEIPT-V2/2.2.0")
  write_ref(writer, candidate.candidate_ref)
  writer.string(candidate.category.wire())
  write_ref(writer, candidate.request.workflow())
  writer.int64(candidate.request.expected_revision())
  writer.optional_digest(candidate.expected_head_digest)
  writer.int64(events[0].sequence())
  writer.int64(events[events.length() - 1].sequence())
  writer.int64(result.workflow_revision())
  writer.string(result.batch_digest().text())
  writer.count(batch.event_refs().length())
  for event_ref in batch.event_refs() {
    write_ref(writer, event_ref)
  }
  writer.string(contest.winner_prefix_replay_digest().text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    candidate_ref: candidate.candidate_ref,
    category: candidate.category,
    workflow: candidate.request.workflow(),
    expected_revision: candidate.request.expected_revision(),
    expected_head_digest: candidate.expected_head_digest,
    first_sequence: events[0].sequence(),
    last_sequence: events[events.length() - 1].sequence(),
    committed_revision: result.workflow_revision(),
    event_refs: batch.event_refs(),
    batch_digest: result.batch_digest(),
    committed_prefix_replay_digest: contest.winner_prefix_replay_digest(),
    canonical,
    digest,
  }
}

///|
fn lifecycle_loss_receipt_v2(
  candidate : LifecycleCommitCandidateV2,
  replay : @storage.ReplayResult,
) -> LifecycleRaceLossReceiptV2 raise OrchestrationError {
  require_lifecycle_replay_workflow_v2(candidate, replay)
  guard @replay.lifecycle_contest(
      replay,
      candidate.request.expected_revision(),
      candidate.expected_head_digest,
    )
    is Some(contest) else {
    raise RecoveryViolation(field="lifecycle_race_winner_batch_missing")
  }
  let batch = contest.batch()
  let events = contest.events()
  let winning_kind = classify_lifecycle_events_v2(events)
  let reason = public_lifecycle_loss_v2(@decision.loss_for_winner(winning_kind))
  let winning_category = public_lifecycle_category_v2(winning_kind)
  let kinds = [ for event in events => event.payload().envelope_kind() ]
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LIFECYCLE-RACE-LOSS-RECEIPT-V2/2.2.0")
  write_ref(writer, candidate.candidate_ref)
  writer.string(candidate.category.wire())
  writer.string(reason.wire())
  writer.string(winning_category.map(value => value.wire()).unwrap_or("none"))
  write_ref(writer, candidate.request.workflow())
  writer.int64(candidate.request.expected_revision())
  writer.optional_digest(candidate.expected_head_digest)
  writer.int64(events[0].sequence())
  writer.int64(events[events.length() - 1].sequence())
  writer.int64(events[0].revision())
  writer.int64(events[events.length() - 1].revision())
  writer.int64(contest.winner_head_revision())
  writer.optional_digest(contest.winner_head_digest())
  writer.string(batch.command_key())
  writer.count(events.length())
  for event in events {
    write_ref(writer, event.event_ref())
    writer.string(event.payload().envelope_kind())
  }
  writer.string(batch.batch_digest().text())
  writer.string(contest.winner_prefix_replay_digest().text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  let receipt_id = "\{candidate.candidate_ref.id()}:lost:\{batch.batch_digest().text()}"
  {
    receipt_ref: self_ref_v22(
      "orchestration-lifecycle-race-loss-receipt-v2", receipt_id, digest,
    ),
    candidate_ref: candidate.candidate_ref,
    losing_category: candidate.category,
    reason,
    winning_category,
    workflow: candidate.request.workflow(),
    expected_revision: candidate.request.expected_revision(),
    expected_head_digest: candidate.expected_head_digest,
    winner_first_sequence: events[0].sequence(),
    winner_last_sequence: events[events.length() - 1].sequence(),
    winner_start_revision: events[0].revision(),
    winner_end_revision: events[events.length() - 1].revision(),
    observed_head_revision: contest.winner_head_revision(),
    observed_head_digest: contest.winner_head_digest(),
    winner_command_key: batch.command_key(),
    winner_event_refs: batch.event_refs(),
    winner_event_kinds: ReadOnlyArray::from_array(kinds),
    winner_batch_digest: batch.batch_digest(),
    source_replay_digest: contest.winner_prefix_replay_digest(),
    canonical,
    digest,
  }
}

///|
/// Single public mutation path for sealed lifecycle candidates. A CAS loss is
/// classified exclusively from the replayed durable batch at the contested slot.
pub fn[S : @storage.RegistryBoundGuardedStoragePort] commit_lifecycle_candidate_v2(
  store : S,
  candidate : LifecycleCommitCandidateV2,
) -> LifecycleCommitOutcomeV2 raise {
  try {
    match store.guarded_commit(candidate.guarded_request) {
      @storage.GuardedCommitSucceeded(result) => {
        let replay = store.replay(candidate.request.workflow())
        require_lifecycle_replay_workflow_v2(candidate, replay)
        LifecycleCommittedV2(
          committed_lifecycle_receipt_v2(candidate, result, replay),
        )
      }
      @storage.GuardedCommitRejected(conflict) =>
        LifecycleStaleGovernanceV2(
          stale_governance_lifecycle_receipt_v2(candidate, conflict),
        )
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) => {
      let replay = store.replay(candidate.request.workflow())
      require_lifecycle_replay_workflow_v2(candidate, replay)
      LifecycleLostV2(lifecycle_loss_receipt_v2(candidate, replay))
    }
    @storage.IdempotencyConflict(key~) => raise IdempotencyConflict(key~)
    error => raise error
  }
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::record_ref(
  self : StaleGovernanceLifecycleReceiptV2,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::candidate_ref(
  self : StaleGovernanceLifecycleReceiptV2,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::category(
  self : StaleGovernanceLifecycleReceiptV2,
) -> LifecycleCandidateCategoryV2 {
  self.category
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::governance_workflow(
  self : StaleGovernanceLifecycleReceiptV2,
) -> @contracts.RecordRef {
  self.conflict.guard_workflow()
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::expected_revision(
  self : StaleGovernanceLifecycleReceiptV2,
) -> Int64 {
  self.conflict.expected_revision()
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::expected_head_digest(
  self : StaleGovernanceLifecycleReceiptV2,
) -> @contracts.ContentDigest? {
  self.conflict.expected_head_digest()
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::expected_replay_digest(
  self : StaleGovernanceLifecycleReceiptV2,
) -> @contracts.ContentDigest {
  self.conflict.expected_replay_digest()
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::actual_revision(
  self : StaleGovernanceLifecycleReceiptV2,
) -> Int64 {
  self.conflict.actual_revision()
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::actual_head_digest(
  self : StaleGovernanceLifecycleReceiptV2,
) -> @contracts.ContentDigest? {
  self.conflict.actual_head_digest()
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::actual_replay_digest(
  self : StaleGovernanceLifecycleReceiptV2,
) -> @contracts.ContentDigest {
  self.conflict.actual_replay_digest()
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::canonical_bytes(
  self : StaleGovernanceLifecycleReceiptV2,
) -> Bytes {
  self.canonical
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::digest(
  self : StaleGovernanceLifecycleReceiptV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn StaleGovernanceLifecycleReceiptV2::validate_current(
  self : StaleGovernanceLifecycleReceiptV2,
  governance_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  self.conflict.validate_current(governance_replay) catch {
    _ => raise RecoveryViolation(field="stale_governance_receipt_not_current")
  }
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::candidate_ref(
  self : CommittedLifecycleCandidateReceiptV2,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::category(
  self : CommittedLifecycleCandidateReceiptV2,
) -> LifecycleCandidateCategoryV2 {
  self.category
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::workflow(
  self : CommittedLifecycleCandidateReceiptV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::expected_revision(
  self : CommittedLifecycleCandidateReceiptV2,
) -> Int64 {
  self.expected_revision
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::committed_revision(
  self : CommittedLifecycleCandidateReceiptV2,
) -> Int64 {
  self.committed_revision
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::event_refs(
  self : CommittedLifecycleCandidateReceiptV2,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.event_refs
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::batch_digest(
  self : CommittedLifecycleCandidateReceiptV2,
) -> @contracts.ContentDigest {
  self.batch_digest
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::canonical_bytes(
  self : CommittedLifecycleCandidateReceiptV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::digest(
  self : CommittedLifecycleCandidateReceiptV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn CommittedLifecycleCandidateReceiptV2::validate_replay_binding(
  self : CommittedLifecycleCandidateReceiptV2,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  if replay.workflow() != self.workflow {
    raise WorkflowMismatch(field="committed_lifecycle_receipt_workflow")
  }
  guard @replay.contested_batch(replay, self.expected_revision) is Some(batch) else {
    raise RecoveryViolation(field="committed_lifecycle_receipt_batch")
  }
  guard @replay.contested_events(replay, batch) is Some(events) else {
    raise RecoveryViolation(field="committed_lifecycle_receipt_events")
  }
  if batch.event_refs() != self.event_refs ||
    batch.batch_digest() != self.batch_digest ||
    events[0].previous_event_digest() != self.expected_head_digest ||
    events[0].sequence() != self.first_sequence ||
    events[events.length() - 1].sequence() != self.last_sequence ||
    events[events.length() - 1].revision() != self.committed_revision {
    raise RecoveryViolation(field="committed_lifecycle_receipt_batch")
  }
  let prefix = replay.verified_prefix(self.committed_revision) catch {
    _ => raise RecoveryViolation(field="committed_lifecycle_receipt_prefix")
  }
  if prefix.replay_digest() != self.committed_prefix_replay_digest {
    raise RecoveryViolation(field="committed_lifecycle_receipt_prefix")
  }
}

///|
pub fn LifecycleRaceLossReceiptV2::record_ref(
  self : LifecycleRaceLossReceiptV2,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn LifecycleRaceLossReceiptV2::losing_category(
  self : LifecycleRaceLossReceiptV2,
) -> LifecycleCandidateCategoryV2 {
  self.losing_category
}

///|
pub fn LifecycleRaceLossReceiptV2::reason(
  self : LifecycleRaceLossReceiptV2,
) -> LifecycleRaceLossReasonV2 {
  self.reason
}

///|
pub fn LifecycleRaceLossReceiptV2::winning_category(
  self : LifecycleRaceLossReceiptV2,
) -> LifecycleCandidateCategoryV2? {
  self.winning_category
}

///|
pub fn LifecycleRaceLossReceiptV2::workflow(
  self : LifecycleRaceLossReceiptV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn LifecycleRaceLossReceiptV2::expected_revision(
  self : LifecycleRaceLossReceiptV2,
) -> Int64 {
  self.expected_revision
}

///|
pub fn LifecycleRaceLossReceiptV2::winner_start_revision(
  self : LifecycleRaceLossReceiptV2,
) -> Int64 {
  self.winner_start_revision
}

///|
pub fn LifecycleRaceLossReceiptV2::winner_end_revision(
  self : LifecycleRaceLossReceiptV2,
) -> Int64 {
  self.winner_end_revision
}

///|
pub fn LifecycleRaceLossReceiptV2::winner_first_sequence(
  self : LifecycleRaceLossReceiptV2,
) -> Int64 {
  self.winner_first_sequence
}

///|
pub fn LifecycleRaceLossReceiptV2::winner_last_sequence(
  self : LifecycleRaceLossReceiptV2,
) -> Int64 {
  self.winner_last_sequence
}

///|
pub fn LifecycleRaceLossReceiptV2::winner_command_key(
  self : LifecycleRaceLossReceiptV2,
) -> String {
  self.winner_command_key
}

///|
pub fn LifecycleRaceLossReceiptV2::winner_batch_digest(
  self : LifecycleRaceLossReceiptV2,
) -> @contracts.ContentDigest {
  self.winner_batch_digest
}

///|
pub fn LifecycleRaceLossReceiptV2::winner_event_refs(
  self : LifecycleRaceLossReceiptV2,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.winner_event_refs
}

///|
pub fn LifecycleRaceLossReceiptV2::winner_event_kinds(
  self : LifecycleRaceLossReceiptV2,
) -> ReadOnlyArray[String] {
  self.winner_event_kinds
}

///|
pub fn LifecycleRaceLossReceiptV2::canonical_bytes(
  self : LifecycleRaceLossReceiptV2,
) -> Bytes {
  self.canonical
}

///|
pub fn LifecycleRaceLossReceiptV2::digest(
  self : LifecycleRaceLossReceiptV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Historical proof: later legal appends do not invalidate the contested batch.
pub fn LifecycleRaceLossReceiptV2::validate_replay_binding(
  self : LifecycleRaceLossReceiptV2,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  if replay.workflow() != self.workflow {
    raise WorkflowMismatch(field="lifecycle_race_receipt_workflow")
  }
  guard @replay.lifecycle_contest(
      replay,
      self.expected_revision,
      self.expected_head_digest,
    )
    is Some(contest) else {
    raise RecoveryViolation(field="lifecycle_race_receipt_contest")
  }
  let batch = contest.batch()
  let events = contest.events()
  let winning_kind = classify_lifecycle_events_v2(events)
  let category = public_lifecycle_category_v2(winning_kind)
  let reason = public_lifecycle_loss_v2(@decision.loss_for_winner(winning_kind))
  let kinds = [ for event in events => event.payload().envelope_kind() ]
  if batch.command_key() != self.winner_command_key ||
    batch.event_refs() != self.winner_event_refs ||
    batch.batch_digest() != self.winner_batch_digest ||
    events[0].previous_event_digest() != self.expected_head_digest ||
    events[0].sequence() != self.winner_first_sequence ||
    events[events.length() - 1].sequence() != self.winner_last_sequence ||
    events[0].revision() != self.winner_start_revision ||
    events[events.length() - 1].revision() != self.winner_end_revision ||
    contest.winner_prefix_replay_digest() != self.source_replay_digest ||
    contest.winner_head_revision() != self.observed_head_revision ||
    contest.winner_head_digest() != self.observed_head_digest ||
    ReadOnlyArray::from_array(kinds) != self.winner_event_kinds ||
    category != self.winning_category ||
    reason != self.reason {
    raise RecoveryViolation(field="lifecycle_race_receipt_batch")
  }
}

///|
/// Diagnostic freshness only. This receipt never grants operational authority.
pub fn LifecycleRaceLossReceiptV2::validate_current(
  self : LifecycleRaceLossReceiptV2,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  self.validate_replay_binding(replay)
  let head = replay.head()
  if head.revision() != self.observed_head_revision ||
    head.last_event_digest() != self.observed_head_digest ||
    replay.replay_digest() != self.source_replay_digest {
    raise RecoveryViolation(field="lifecycle_race_receipt_not_current")
  }
}
