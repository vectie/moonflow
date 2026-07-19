///|
fn recovery_state_blocks_work_terminal_v3(
  state : @effects.EffectRecoveryStateV3,
) -> Bool {
  match state {
    @effects.RecoveryDispatchEligibleV3
    | @effects.RecoveryDispatchClaimedV3
    | @effects.RecoveryDispatchAttemptedV3
    | @effects.RecoveryUnknownRequiresReconciliationV3
    | @effects.RecoveryReconciliationClaimedV3
    | @effects.RecoveryBackoffPendingV3
    | @effects.RecoveryExhaustedV3
    | @effects.RecoveryManualInterventionV3 => true
    @effects.RecoveryKnownSuccessV3
    | @effects.RecoveryKnownFailureV3
    | @effects.RecoveryReconciledSuccessV3
    | @effects.RecoveryReconciledFailureV3
    | @effects.RecoveryConfirmedNotAppliedRetryEligibleV3 => false
  }
}

///|
/// Verify the only suffix that can follow a Phase-2 historical cancellation
/// authorization: one same-intent claim and its invocation-start in the same
/// guarded transaction. When `cancellation_event` is present it must be the
/// immediately following event; no activation, unrelated work, or other
/// recovery event can be inserted into the authorized suffix.
fn require_claim_first_cancellation_suffix_v3(
  replay : @storage.ReplayResult,
  authorization_work_sequence : Int64,
  authorization_work_revision : Int64,
  authorization_work_head_digest : @contracts.ContentDigest,
  authorization_work_replay_digest : @contracts.ContentDigest,
  source_intent_ref : @contracts.RecordRef,
  cancellation_event : @storage.WorkflowEvent?,
) -> Unit raise OrchestrationError {
  let prefix = replay.verified_prefix(authorization_work_revision) catch {
    _ => raise ReplayBindingViolation(field="cancellation_claim_first_prefix")
  }
  if prefix.head().sequence() != authorization_work_sequence ||
    prefix.head().revision() != authorization_work_revision ||
    prefix.head().last_event_digest() != Some(authorization_work_head_digest) ||
    prefix.replay_digest() != authorization_work_replay_digest {
    raise ReplayBindingViolation(field="cancellation_claim_first_prefix")
  }
  let suffix_end_revision = match cancellation_event {
    None => replay.head().revision()
    Some(cancellation) => cancellation.revision()
  }
  let suffix = [
    for event in replay.events() if event.revision() >
    authorization_work_revision &&
    event.revision() <= suffix_end_revision => event
  ]
  let required_count = if cancellation_event is Some(_) { 3 } else { 2 }
  if suffix.length() != required_count ||
    suffix[0].payload().envelope_kind() != dispatch_claim_event_kind_v3 ||
    suffix[1].payload().envelope_kind() != invocation_started_event_kind_v3 {
    raise ReplayBindingViolation(field="cancellation_claim_first_suffix")
  }
  let claim = decode_dispatch_claim_record_v3(suffix[0].payload().payload())
  let started = decode_dispatch_invocation_started_v3(
    suffix[1].payload().payload(),
  )
  require_dispatch_claim_event_binding_v3(claim, suffix[0])
  require_dispatch_invocation_event_binding_v3(started, suffix[1], claim)
  require_dispatch_claim_transaction_v3(claim, suffix[0], replay)
  if claim.intent_ref != source_intent_ref ||
    started.intent_ref != source_intent_ref ||
    suffix[0].sequence() != authorization_work_sequence + 1L ||
    suffix[0].revision() != authorization_work_revision + 1L ||
    suffix[0].previous_event_digest() != Some(authorization_work_head_digest) ||
    suffix[1].sequence() != authorization_work_sequence + 2L ||
    suffix[1].revision() != authorization_work_revision + 2L ||
    suffix[1].previous_event_digest() != Some(suffix[0].event_ref().digest()) {
    raise ReplayBindingViolation(field="cancellation_claim_first_suffix")
  }
  match cancellation_event {
    None => ()
    Some(cancellation) =>
      if suffix[2].event_ref() != cancellation.event_ref() ||
        cancellation.sequence() != authorization_work_sequence + 3L ||
        cancellation.revision() != authorization_work_revision + 3L ||
        cancellation.previous_event_digest() !=
        Some(suffix[1].event_ref().digest()) {
        raise ReplayBindingViolation(field="cancellation_claim_first_suffix")
      }
  }
}

///|
/// Authorize a cancellation proposal at an activated pre-claim head without
/// rewriting its historical provenance. The normal V2 authorization path
/// remains strictly current-head-bound.
pub fn CurrentGovernedRecoveryProjectionV3::authorize_claim_first_cancellation_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  proposal : CancellationProposalV2,
  authorization_id : String,
  request_id : String,
) -> CancellationRequestV2 raise OrchestrationError {
  if self.current.work.cancellation is Some(_) ||
    self.current.work.work_terminal is Some(_) {
    raise CancellationPrecedenceViolation(
      field="work_terminal_already_committed",
    )
  }
  guard proposal.source_intent_ref is Some(source_intent_ref) else {
    raise ReplayBindingViolation(field="cancellation_source_lineage")
  }
  if self.claims.any(claim => claim.intent_ref == source_intent_ref) ||
    self.invocation_starts.any(started => {
      started.intent_ref == source_intent_ref
    }) ||
    self.observations.any(observation => {
      observation.intent_ref == source_intent_ref
    }) {
    raise ReplayBindingViolation(field="cancellation_claim_first_preclaim")
  }
  let proposal_replay = self.work_replay.verified_prefix(
    proposal.prefix_revision,
  ) catch {
    _ => raise ReplayBindingViolation(field="cancellation_head_binding")
  }
  let proposal_current = fold_governed_closed_loop_v2(
    self.empty_effects,
    proposal_replay,
    self.governance_replay,
  )
  require_proposal_current_v22(proposal, proposal_current)
  let target = self.current.work.effects.strict_recovery_target_v3(
    source_intent_ref,
  ) catch {
    _ => raise ReplayBindingViolation(field="cancellation_source_lineage")
  }
  guard self.current_activation_for(
      target.capability_ref(),
      target.capability_kind(),
    )
    is Some(_) else {
    raise RecoveryViolation(field="cancellation_claim_first_activation")
  }
  if self.state_for(source_intent_ref) != @effects.RecoveryDispatchEligibleV3 {
    raise RecoveryViolation(field="cancellation_claim_first_preclaim")
  }
  let receipt = self.current.mint_committed_cancellation_governance_receipt_v22(
    proposal,
  )
  let authorization = CancellationAuthorizationV2::from_historical_proposal_v3(
    authorization_id,
    receipt,
    proposal,
    self.current,
    proposal_current,
  )
  CancellationRequestV2::new(request_id, proposal, authorization)
}

///|
fn CurrentGovernedRecoveryProjectionV3::prepare_claim_first_cancellation_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  request : CancellationRequestV2,
) -> PreparedCancellationV2 raise OrchestrationError {
  guard request.proposal.source_intent_ref is Some(source_intent_ref) else {
    raise ReplayBindingViolation(field="cancellation_source_lineage")
  }
  let authorization_revision = request.authorization.governance_receipt.work_revision
  let authorization_replay = self.work_replay.verified_prefix(
    authorization_revision,
  ) catch {
    _ => raise ReplayBindingViolation(field="cancellation_claim_first_prefix")
  }
  let authorization_current = fold_governed_recovery_v3(
    self.empty_effects,
    authorization_replay,
    self.governance_replay,
  )
  let proposal_replay = self.work_replay.verified_prefix(
    request.proposal.prefix_revision,
  ) catch {
    _ => raise ReplayBindingViolation(field="cancellation_head_binding")
  }
  let proposal_current = fold_governed_closed_loop_v2(
    self.empty_effects,
    proposal_replay,
    self.governance_replay,
  )
  let decoded = decode_historical_cancellation_request_v3(
    request.request_ref,
    request.canonical,
    authorization_current.current,
    proposal_current,
  )
  if decoded.request_ref != request.request_ref ||
    decoded.canonical != request.canonical ||
    decoded.digest != request.digest {
    raise ReplayBindingViolation(field="cancellation_request_composite_binding")
  }
  require_claim_first_cancellation_suffix_v3(
    self.work_replay,
    request.authorization.governance_receipt.work_sequence,
    authorization_revision,
    request.authorization.governance_receipt.work_head_digest,
    request.authorization.governance_receipt.work_replay_digest,
    source_intent_ref,
    None,
  )
  let event = prepare_phase1b_work_event_v22(
    request.proposal.workflow,
    self.current.work_sequence + 1L,
    self.current.work_revision + 1L,
    self.current.work_head_digest,
    request.request_ref.id(),
    cancellation_requested_event_kind_v22,
    request.request_ref,
    request.canonical,
    request.proposal.governed_subject,
    [
      for value in request.proposal.evidence => value
    ],
    request.proposal.causation,
    request.proposal.event_idempotency_key,
  )
  let commit_request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    request.proposal.workflow,
    self.current.work_revision,
    request.proposal.command_idempotency_key,
    [event],
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="work_batch_boundary_shape")
  }
  { request, terminal_outcome: None, commit_request }
}

///|
fn CurrentGovernedRecoveryProjectionV3::v3_owned_intent_refs(
  self : CurrentGovernedRecoveryProjectionV3,
) -> Array[@contracts.RecordRef] raise OrchestrationError {
  let values : Array[@contracts.RecordRef] = []
  // Seed the exact activation source, then enumerate the authoritative catalog
  // by capability. Ownership never disappears when a later state transition
  // makes a strict dispatch target ineligible.
  for activation in self.activations {
    if !values.any(value => value == activation.source_intent_ref) {
      values.push(activation.source_intent_ref)
    }
  }
  // V3 retry intents are native orchestration records rather than legacy
  // EffectIntent values. A durable scheduled retry is already owned work even
  // before its due time or dispatch claim, so terminal readiness must include
  // every replay-validated schedule and cannot strand its outbox.
  for schedule in self.recovery_retry_schedules_v3() {
    let retry_ref = schedule.retry_intent.retry_intent_ref
    if !values.any(value => value == retry_ref) {
      values.push(retry_ref)
    }
  }
  // Claims remain an explicit ownership source as a fail-closed cross-check
  // for both legacy effects and native retry intents.
  for claim in self.claims {
    if !values.any(value => value == claim.intent_ref) {
      values.push(claim.intent_ref)
    }
  }
  let catalog = self.current.work.effects.strict_recovery_intent_catalog_v3() catch {
    _ => raise ReplayBindingViolation(field="v3_terminal_intent_catalog")
  }
  for identity in catalog {
    if self.activations.any(activation => {
        activation.capability_ref == identity.capability_ref() &&
        activation.capability_kind == identity.capability_kind()
      }) &&
      !values.any(value => value == identity.intent_ref()) {
      values.push(identity.intent_ref())
    }
  }
  values
}

///|
/// Fail closed while any V3-owned effect can still be in flight or require
/// recovery. This is a direct check on the exact joint projection and returns
/// no reusable readiness capability.
fn CurrentGovernedRecoveryProjectionV3::require_work_terminal_ready_v3(
  self : CurrentGovernedRecoveryProjectionV3,
) -> Unit raise OrchestrationError {
  let owned = self.v3_owned_intent_refs()
  for intent_ref in owned {
    if recovery_state_blocks_work_terminal_v3(self.state_for(intent_ref)) {
      raise RecoveryViolation(field="work_terminal_requires_recovery_v3")
    }
  }
  // This gate protects legacy V2 terminal candidates only. V3-owned effects
  // terminalize through RecoverySettlementSetV3 and the separately guarded
  // recovery-evidence head, never through a V2 effect-terminal source.
  if !owned.is_empty() {
    raise RecoveryViolation(field="work_terminal_requires_v3_settlement")
  }
}

///|
/// Public V3 cancellation entrypoint. Pending cancellation remains legal while
/// recovery is unresolved; an immediate cancellation terminal is gated.
pub fn prepare_lifecycle_cancellation_candidate_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  request : CancellationRequestV2,
) -> LifecycleCommitCandidateV2 raise OrchestrationError {
  require_lifecycle_cancellation_identity_v22(current.current, request)
  let prepared = if request.authorization.governance_receipt.work_revision ==
    request.proposal.prefix_revision {
    prepare_cancellation_v2(current.current, request)
  } else {
    current.prepare_claim_first_cancellation_v3(request)
  }
  if prepared.terminal_outcome() is Some(_) {
    current.require_work_terminal_ready_v3()
  }
  lifecycle_candidate_from_prepared_cancellation_v22(prepared, current.current)
}

///|
pub fn prepare_lifecycle_succeeded_work_terminal_candidate_v3(
  current : CurrentThreeStreamRecoverySettlementV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  current.prepare_succeeded_terminal()
}

///|
pub fn prepare_lifecycle_cancelled_after_reconciled_not_applied_work_terminal_candidate_v3(
  current : CurrentThreeStreamRecoverySettlementV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  current.prepare_cancelled_terminal()
}

///|
pub fn prepare_lifecycle_failed_work_terminal_candidate_v3(
  current : CurrentThreeStreamRecoverySettlementV3,
) -> RecoveryLifecycleTerminalCandidateV3 raise OrchestrationError {
  current.prepare_failed_terminal()
}
