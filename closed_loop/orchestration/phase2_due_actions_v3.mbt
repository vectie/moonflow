///|
/// Domain-neutral work a host may surface from the exact Phase-2 replay. These
/// values are inert projections: enumerating them performs no provider call,
/// mutation, scheduling, or policy choice.
pub(all) enum RecoveryDueActionKindV3 {
  RecoveryPolicyBindingRequiredActionV3
  EffectRetryPolicyBindingRequiredActionV3
  InitialReconciliationDueActionV3
  ReconciliationTakeoverDueActionV3
  RetryDispatchReadyActionV3
  RetryDispatchExpiredActionV3
  ManualInterventionHeldActionV3
  RecoverySettlementReadyActionV3
  RecoveryTerminalReadyActionV3
} derive(Eq, Debug)

///|
fn RecoveryDueActionKindV3::wire(self : RecoveryDueActionKindV3) -> String {
  match self {
    RecoveryPolicyBindingRequiredActionV3 =>
      "recovery_policy_binding_required_v3"
    EffectRetryPolicyBindingRequiredActionV3 =>
      "effect_retry_policy_binding_required_v3"
    InitialReconciliationDueActionV3 => "initial_reconciliation_due_v3"
    ReconciliationTakeoverDueActionV3 => "reconciliation_takeover_due_v3"
    RetryDispatchReadyActionV3 => "retry_dispatch_ready_v3"
    RetryDispatchExpiredActionV3 => "retry_dispatch_expired_v3"
    ManualInterventionHeldActionV3 => "manual_intervention_held_v3"
    RecoverySettlementReadyActionV3 => "recovery_settlement_ready_v3"
    RecoveryTerminalReadyActionV3 => "recovery_terminal_ready_v3"
  }
}

///|
pub struct RecoveryDueActionV3 {
  action_ref : @contracts.RecordRef
  stable_key : String
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef?
  kind : RecoveryDueActionKindV3
  source_ref : @contracts.RecordRef
  source_digest : @contracts.ContentDigest
  due_at : Int64
  deadline : Int64?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_recovery_due_action_v3(
  workflow : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef?,
  kind : RecoveryDueActionKindV3,
  source_ref : @contracts.RecordRef,
  source_digest : @contracts.ContentDigest,
  due_at : Int64,
  deadline : Int64?,
) -> RecoveryDueActionV3 raise OrchestrationError {
  if source_ref.digest() != source_digest || due_at < 0L {
    raise ReplayBindingViolation(field="recovery_due_action_source_v3")
  }
  match deadline {
    Some(value) if value < due_at && kind != RetryDispatchExpiredActionV3 =>
      raise OrderingViolation(field="recovery_due_action_deadline_v3")
    _ => ()
  }
  let intent_key = match intent_ref {
    None => "workflow"
    Some(value) => value.id()
  }
  let stable_key = "{workflow.id()}:{intent_key}:{kind.wire()}:{source_ref.id()}"
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/RECOVERY-DUE-ACTION-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(stable_key)
  write_ref(writer, workflow)
  match intent_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
  }
  writer.string(kind.wire())
  write_ref(writer, source_ref)
  writer.string(source_digest.text())
  writer.int64(due_at)
  writer.optional_int64(deadline)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    action_ref: self_ref_v3(
      "orchestration-recovery-due-action-v3", stable_key, digest,
    ),
    stable_key,
    workflow,
    intent_ref,
    kind,
    source_ref,
    source_digest,
    due_at,
    deadline,
    canonical,
    digest,
  }
}

///|
fn append_recovery_due_action_v3(
  values : Array[RecoveryDueActionV3],
  workflow : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef?,
  kind : RecoveryDueActionKindV3,
  source_ref : @contracts.RecordRef,
  source_digest : @contracts.ContentDigest,
  due_at : Int64,
  deadline : Int64?,
) -> Unit raise OrchestrationError {
  let value = make_recovery_due_action_v3(
    workflow, intent_ref, kind, source_ref, source_digest, due_at, deadline,
  )
  if values.any(prior => prior.stable_key == value.stable_key) {
    raise ReplayBindingViolation(field="recovery_due_action_duplicate_v3")
  }
  values.push(value)
}

///|
fn CurrentGovernedRecoveryProjectionV3::latest_recovery_fact_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> (@contracts.RecordRef, @contracts.ContentDigest, Int64) raise OrchestrationError {
  match self.current_reconciliation_result_v3(intent_ref) {
    Some(result) => (result.result_ref, result.digest, result.observed_at)
    None =>
      match first(self.observations, value => value.intent_ref == intent_ref) {
        Some(observation) =>
          (
            observation.observation_ref,
            observation.digest,
            observation.observed_at,
          )
        None =>
          match self.current_claim(intent_ref) {
            Some(claim) => (claim.claim_ref, claim.digest, claim.claimed_at)
            None =>
              match self.retry_dispatch_target_v3(intent_ref) {
                Some(target) =>
                  match
                    self
                    .recovery_retry_schedules_v3()
                    .filter(schedule => {
                      schedule.retry_intent.retry_intent_ref ==
                      target.intent_ref
                    })
                    .last() {
                    Some(schedule) =>
                      (
                        schedule.schedule_ref,
                        schedule.digest,
                        schedule.retry_intent.created_at,
                      )
                    None =>
                      raise ReplayBindingViolation(
                        field="recovery_due_action_retry_source_v3",
                      )
                  }
                None =>
                  raise ReplayBindingViolation(
                    field="recovery_due_action_fact_v3",
                  )
              }
          }
      }
  }
}

///|
fn max_due_at_v3(left : Int64, right : Int64) -> Int64 {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn latest_callback_due_fact_v3(
  evidence : CurrentRecoveryEvidenceProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> (@contracts.RecordRef, @contracts.ContentDigest, Int64)? {
  guard evidence
    .entries()
    .filter(entry => entry.record().intent_ref() == intent_ref)
    .last()
    is Some(entry) else {
    return None
  }
  let record = entry.record()
  Some((record.record_ref(), record.digest(), record.retrieved_at()))
}

///|
fn CurrentGovernedRecoveryProjectionV3::recovery_due_actions_core_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  recovery_evidence : CurrentRecoveryEvidenceProjectionV3?,
  now : Int64,
) -> Array[RecoveryDueActionV3] raise OrchestrationError {
  if now < 0L {
    raise MalformedInput(field="recovery_due_actions_now_v3")
  }
  let values : Array[RecoveryDueActionV3] = []
  if self.current.work.work_terminal is Some(_) ||
    self.recovery_terminal_outcome_v3() is Some(_) {
    return values
  }
  let manual = fold_manual_intervention_v3(self.work_replay)
  let owned = self.v3_owned_intent_refs()
  for intent_ref in owned {
    match manual.active_hold(intent_ref) {
      Some(hold) => {
        append_recovery_due_action_v3(
          values,
          self.work_replay.workflow(),
          Some(intent_ref),
          ManualInterventionHeldActionV3,
          hold.record_ref,
          hold.digest,
          hold.authored_at,
          None,
        )
        continue
      }
      None => ()
    }
    match self.retry_dispatch_target_v3(intent_ref) {
      Some(target) if self.current_claim(intent_ref) is None => {
        guard target.retry_due_at is Some(due_at) &&
          target.retry_deadline is Some(deadline) else {
          raise ReplayBindingViolation(field="recovery_due_action_retry_v3")
        }
        guard self
          .recovery_retry_schedules_v3()
          .filter(schedule => {
            schedule.retry_intent.retry_intent_ref == intent_ref
          })
          .last()
          is Some(schedule) else {
          raise ReplayBindingViolation(field="recovery_due_action_retry_v3")
        }
        if now > deadline {
          append_recovery_due_action_v3(
            values,
            self.work_replay.workflow(),
            Some(intent_ref),
            RetryDispatchExpiredActionV3,
            schedule.schedule_ref,
            schedule.digest,
            deadline,
            Some(deadline),
          )
        } else if now >= due_at && self.current.work.cancellation is None {
          append_recovery_due_action_v3(
            values,
            self.work_replay.workflow(),
            Some(intent_ref),
            RetryDispatchReadyActionV3,
            schedule.schedule_ref,
            schedule.digest,
            due_at,
            Some(deadline),
          )
        }
        continue
      }
      _ => ()
    }
    let root_state = self.state_for(intent_ref)
    let (state, callback_fact) = match recovery_evidence {
      None => (root_state, None)
      Some(evidence) => {
        let combined = self.state_for_with_recovery_evidence_v3(
          evidence, intent_ref,
        )
        let fact = if combined == root_state {
          None
        } else {
          latest_callback_due_fact_v3(evidence, intent_ref)
        }
        (combined, fact)
      }
    }
    match state {
      @effects.RecoveryDispatchAttemptedV3
      | @effects.RecoveryUnknownRequiresReconciliationV3 => {
        guard self.current_claim(intent_ref) is Some(claim) else {
          raise ReplayBindingViolation(field="recovery_due_action_claim_v3")
        }
        if self.current_reconciliation_claim_v3(intent_ref) is None {
          let missing_recovery = self.recovery_policy_for_v3(intent_ref) is None
          let missing_retry = self.effect_retry_policy_for_v3(intent_ref)
            is None &&
            self.current.work.cancellation is None
          if missing_recovery {
            append_recovery_due_action_v3(
              values,
              self.work_replay.workflow(),
              Some(intent_ref),
              RecoveryPolicyBindingRequiredActionV3,
              claim.claim_ref,
              claim.digest,
              claim.claimed_at,
              Some(claim.expires_at),
            )
          }
          if missing_retry {
            append_recovery_due_action_v3(
              values,
              self.work_replay.workflow(),
              Some(intent_ref),
              EffectRetryPolicyBindingRequiredActionV3,
              claim.claim_ref,
              claim.digest,
              claim.claimed_at,
              Some(claim.expires_at),
            )
          }
          let due_at = match callback_fact {
            Some((_, _, retrieved_at)) => retrieved_at
            None =>
              match state {
                @effects.RecoveryDispatchAttemptedV3 => claim.expires_at
                _ =>
                  match
                    first(self.observations, value => {
                      value.intent_ref == intent_ref
                    }) {
                    Some(observation) => observation.observed_at
                    None => claim.claimed_at
                  }
              }
          }
          if !missing_recovery && !missing_retry && now >= due_at {
            append_recovery_due_action_v3(
              values,
              self.work_replay.workflow(),
              Some(intent_ref),
              InitialReconciliationDueActionV3,
              claim.claim_ref,
              claim.digest,
              due_at,
              None,
            )
          }
        }
      }
      @effects.RecoveryReconciliationClaimedV3 => {
        guard self.current_reconciliation_claim_v3(intent_ref) is Some(claim) else {
          raise ReplayBindingViolation(
            field="recovery_due_action_reconciliation_v3",
          )
        }
        if self.current_reconciliation_result_v3(intent_ref) is None &&
          now >= claim.expires_at {
          append_recovery_due_action_v3(
            values,
            self.work_replay.workflow(),
            Some(intent_ref),
            ReconciliationTakeoverDueActionV3,
            claim.reconciliation_claim_ref,
            claim.digest,
            claim.expires_at,
            None,
          )
        }
      }
      @effects.RecoveryBackoffPendingV3 => {
        guard self.current_reconciliation_claim_v3(intent_ref) is Some(claim) &&
          self.current_recovery_backoff_v3(intent_ref) is Some(backoff) else {
          raise ReplayBindingViolation(field="recovery_due_action_backoff_v3")
        }
        let due_at = max_due_at_v3(backoff.next_due_at, claim.expires_at)
        if now >= due_at {
          append_recovery_due_action_v3(
            values,
            self.work_replay.workflow(),
            Some(intent_ref),
            ReconciliationTakeoverDueActionV3,
            backoff.backoff_ref,
            backoff.digest,
            due_at,
            Some(backoff.deadline),
          )
        }
      }
      @effects.RecoveryKnownSuccessV3
      | @effects.RecoveryKnownFailureV3
      | @effects.RecoveryReconciledSuccessV3
      | @effects.RecoveryReconciledFailureV3
      | @effects.RecoveryConfirmedNotAppliedRetryEligibleV3 => {
        let (source_ref, source_digest, settled_at) = match callback_fact {
          Some(value) => value
          None => self.latest_recovery_fact_v3(intent_ref)
        }
        append_recovery_due_action_v3(
          values,
          self.work_replay.workflow(),
          Some(intent_ref),
          RecoverySettlementReadyActionV3,
          source_ref,
          source_digest,
          settled_at,
          None,
        )
      }
      @effects.RecoveryDispatchEligibleV3 | @effects.RecoveryExhaustedV3 => ()
      @effects.RecoveryManualInterventionV3 =>
        match callback_fact {
          Some((source_ref, source_digest, due_at)) =>
            append_recovery_due_action_v3(
              values,
              self.work_replay.workflow(),
              Some(intent_ref),
              ManualInterventionHeldActionV3,
              source_ref,
              source_digest,
              due_at,
              None,
            )
          None => ()
        }
      @effects.RecoveryDispatchClaimedV3 => ()
    }
  }
  values
}

///|
/// Stable replay-order host view for work-stream recovery only.
pub fn CurrentGovernedRecoveryProjectionV3::recovery_due_actions_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  now : Int64,
) -> ReadOnlyArray[RecoveryDueActionV3] raise OrchestrationError {
  ReadOnlyArray::from_array(self.recovery_due_actions_core_v3(None, now))
}

///|
/// Callback-aware host view. The evidence projection must be bound to this
/// exact work replay; stale evidence cannot influence action enumeration.
pub fn CurrentGovernedRecoveryProjectionV3::recovery_due_actions_with_evidence_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
  now : Int64,
) -> ReadOnlyArray[RecoveryDueActionV3] raise OrchestrationError {
  if evidence.bound_workflow() != self.work_replay.workflow() ||
    evidence.bound_work_replay_digest() != self.work_replay.replay_digest() {
    raise ReplayBindingViolation(field="recovery_due_actions_evidence_v3")
  }
  ReadOnlyArray::from_array(
    self.recovery_due_actions_core_v3(Some(evidence), now),
  )
}

///|
/// A successfully joined three-stream settlement proves terminal readiness.
/// The per-intent actions remain available first, followed by one workflow
/// terminal action, producing deterministic ordering for MoonDesk.
pub fn CurrentThreeStreamRecoverySettlementV3::recovery_due_actions_v3(
  self : CurrentThreeStreamRecoverySettlementV3,
  now : Int64,
) -> ReadOnlyArray[RecoveryDueActionV3] raise OrchestrationError {
  let values = self.governed.recovery_due_actions_core_v3(
    Some(self.evidence),
    now,
  )
  let mut terminal_due_at = 0L
  for source in self.settlements.sources {
    terminal_due_at = max_due_at_v3(terminal_due_at, source.settled_at)
  }
  append_recovery_due_action_v3(
    values,
    self.workflow(),
    None,
    RecoveryTerminalReadyActionV3,
    self.settlements.set_ref,
    self.settlements.digest,
    terminal_due_at,
    None,
  )
  ReadOnlyArray::from_array(values)
}

///|
pub fn RecoveryDueActionV3::record_ref(
  self : RecoveryDueActionV3,
) -> @contracts.RecordRef {
  self.action_ref
}

///|
pub fn RecoveryDueActionV3::stable_key(self : RecoveryDueActionV3) -> String {
  self.stable_key
}

///|
pub fn RecoveryDueActionV3::intent_ref(
  self : RecoveryDueActionV3,
) -> @contracts.RecordRef? {
  self.intent_ref
}

///|
pub fn RecoveryDueActionV3::kind(
  self : RecoveryDueActionV3,
) -> RecoveryDueActionKindV3 {
  self.kind
}

///|
pub fn RecoveryDueActionV3::source_ref(
  self : RecoveryDueActionV3,
) -> @contracts.RecordRef {
  self.source_ref
}

///|
pub fn RecoveryDueActionV3::due_at(self : RecoveryDueActionV3) -> Int64 {
  self.due_at
}

///|
pub fn RecoveryDueActionV3::deadline(self : RecoveryDueActionV3) -> Int64? {
  self.deadline
}

///|
pub fn RecoveryDueActionV3::canonical_bytes(
  self : RecoveryDueActionV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryDueActionV3::digest(
  self : RecoveryDueActionV3,
) -> @contracts.ContentDigest {
  self.digest
}
