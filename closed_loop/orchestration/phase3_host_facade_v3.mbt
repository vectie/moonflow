///|
/// One strictly refolded host view after a committed time observation. All
/// decision APIs below consume this value and therefore cannot accept ambient
/// wall-clock time.
pub struct Phase3HostFacadeV3 {
  time_workflow : @contracts.RecordRef
  scheduler_workflow : @contracts.RecordRef
  time_commit_receipt : TimeObservationCommitReceiptV3
  time : TimeEvidenceProjectionV3
  scheduler : SchedulerProjectionV3
  actions : ReadOnlyArray[ScheduledActionV3]
  views : ReadOnlyArray[SchedulerActionViewV3]
  due_actions : ReadOnlyArray[SchedulerActionViewV3]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_phase3_host_facade_v3(
  time_commit_receipt : TimeObservationCommitReceiptV3,
  time : TimeEvidenceProjectionV3,
  scheduler : SchedulerProjectionV3,
  actions : Array[ScheduledActionV3],
) -> Phase3HostFacadeV3 raise OrchestrationError {
  let views = scheduler_action_views_v3(actions, scheduler, time)
  let due_actions = views.filter(value => value.state() == SchedulerDueV3)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/PHASE3-HOST-FACADE-V3/3.0.0")
  writer.string("3.0.0")
  write_ref(writer, time.workflow())
  write_ref(writer, scheduler.workflow())
  writer.string(time_commit_receipt.digest().text())
  writer.string(time.digest().text())
  writer.string(scheduler.digest().text())
  writer.count(actions.length())
  for action in actions {
    writer.string(action.digest().text())
  }
  writer.count(views.length())
  for view in views {
    writer.string(view.digest().text())
  }
  writer.count(due_actions.length())
  for view in due_actions {
    writer.string(view.digest().text())
  }
  let canonical = writer.finish()
  {
    time_workflow: time.workflow(),
    scheduler_workflow: scheduler.workflow(),
    time_commit_receipt,
    time,
    scheduler,
    actions: ReadOnlyArray::from_array(actions.copy()),
    views: ReadOnlyArray::from_array(views),
    due_actions: ReadOnlyArray::from_array(due_actions),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
/// Commit one external clock observation, immediately refold the authoritative
/// time bytes, refold the scheduler stream, and enumerate due actions. The
/// external adapter supplies an observed UTC instant plus evidence; no replay
/// or decision method reads a system clock or accepts `now`.
pub fn[T : @storage.StoragePort, S : @storage.StoragePort] run_phase3_host_cycle_v3(
  time_store : T,
  scheduler_store : S,
  time_workflow : @contracts.RecordRef,
  scheduler_workflow : @contracts.RecordRef,
  observation_id : String,
  observation_event_id : String,
  observation_command_idempotency_key : String,
  source_ref : @contracts.RecordRef,
  source_timezone_id : String,
  source_instant : UtcInstantV3,
  observation_evidence : Array[@contracts.EvidenceRef],
  actions : Array[ScheduledActionV3],
  resolved_boundary? : ResolvedCivilTimeV3,
) -> Phase3HostFacadeV3 raise {
  let before = replay_time_evidence_v3(time_store, time_workflow)
  let plan = prepare_time_observation_commit_v3(
    before,
    observation_id,
    observation_event_id,
    observation_command_idempotency_key,
    source_ref,
    source_timezone_id,
    source_instant,
    observation_evidence,
    resolved_boundary?,
  )
  let receipt = commit_time_observation_v3(time_store, plan)
  let time = replay_time_evidence_v3(time_store, time_workflow)
  guard time.latest() is Some(committed) else {
    raise ReplayBindingViolation(field="phase3_host_time_refold_missing_v3")
  }
  if committed.record_ref() != plan.observation().record_ref() ||
    committed.digest() != plan.observation().digest() ||
    time.replay.head().revision() != receipt.workflow_revision() {
    raise ReplayBindingViolation(field="phase3_host_time_refold_v3")
  }
  let scheduler = replay_scheduler_v3(scheduler_store, scheduler_workflow)
  make_phase3_host_facade_v3(receipt, time, scheduler, actions)
}

///|
pub fn Phase3HostFacadeV3::time_workflow(
  self : Phase3HostFacadeV3,
) -> @contracts.RecordRef {
  self.time_workflow
}

///|
pub fn Phase3HostFacadeV3::scheduler_workflow(
  self : Phase3HostFacadeV3,
) -> @contracts.RecordRef {
  self.scheduler_workflow
}

///|
pub fn Phase3HostFacadeV3::time_projection(
  self : Phase3HostFacadeV3,
) -> TimeEvidenceProjectionV3 {
  self.time
}

///|
pub fn Phase3HostFacadeV3::scheduler_projection(
  self : Phase3HostFacadeV3,
) -> SchedulerProjectionV3 {
  self.scheduler
}

///|
pub fn Phase3HostFacadeV3::actions(
  self : Phase3HostFacadeV3,
) -> ReadOnlyArray[ScheduledActionV3] {
  self.actions
}

///|
pub fn Phase3HostFacadeV3::views(
  self : Phase3HostFacadeV3,
) -> ReadOnlyArray[SchedulerActionViewV3] {
  self.views
}

///|
pub fn Phase3HostFacadeV3::due_actions(
  self : Phase3HostFacadeV3,
) -> ReadOnlyArray[SchedulerActionViewV3] {
  self.due_actions
}

///|
/// Existing Phase-2 recovery work can be surfaced through the same committed
/// time view without changing the frozen recovery projection.
pub fn Phase3HostFacadeV3::recovery_due_actions(
  self : Phase3HostFacadeV3,
  recovery : CurrentGovernedRecoveryProjectionV3,
) -> ReadOnlyArray[RecoveryDueActionV3] raise OrchestrationError {
  recovery.recovery_due_actions_from_time_evidence_v3(self.time)
}

///|
pub fn Phase3HostFacadeV3::recovery_due_actions_with_evidence(
  self : Phase3HostFacadeV3,
  recovery : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
) -> ReadOnlyArray[RecoveryDueActionV3] raise OrchestrationError {
  recovery.recovery_due_actions_with_committed_evidence_time_v3(
    evidence,
    self.time,
  )
}

///|
pub fn Phase3HostFacadeV3::three_stream_recovery_due_actions(
  self : Phase3HostFacadeV3,
  recovery : CurrentThreeStreamRecoverySettlementV3,
) -> ReadOnlyArray[RecoveryDueActionV3] raise OrchestrationError {
  recovery.recovery_due_actions_from_time_evidence_v3(self.time)
}

///|
pub fn Phase3HostFacadeV3::canonical_bytes(self : Phase3HostFacadeV3) -> Bytes {
  self.canonical
}

///|
pub fn Phase3HostFacadeV3::digest(
  self : Phase3HostFacadeV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
fn Phase3HostFacadeV3::require_action(
  self : Phase3HostFacadeV3,
  action_ref : @contracts.RecordRef,
) -> ScheduledActionV3 raise OrchestrationError {
  let matches = self.actions.filter(value => value.record_ref() == action_ref)
  if matches.length() != 1 {
    raise IdentityMismatch(field="phase3_host_action_v3")
  }
  matches[0]
}

///|
fn phase3_mutation_outcome_binding_v3(
  outcome : @storage.ClassifiedGuardedCommitOutcome,
) -> (String, @contracts.ContentDigest) {
  match outcome {
    @storage.FreshlyApplied(value) => ("freshly-applied", value.batch_digest())
    @storage.AlreadyCommitted(value) =>
      ("already-committed", value.batch_digest())
    @storage.GuardRejected(value) => ("guard-rejected", value.digest())
  }
}

///|
pub struct Phase3HostSchedulerMutationV3 {
  outcome : @storage.ClassifiedGuardedCommitOutcome
  facade : Phase3HostFacadeV3
  claim_ref : @contracts.RecordRef?
  receipt_ref : @contracts.RecordRef?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_phase3_host_scheduler_mutation_v3(
  prior : Phase3HostFacadeV3,
  scheduler : SchedulerProjectionV3,
  outcome : @storage.ClassifiedGuardedCommitOutcome,
  claim_ref : @contracts.RecordRef?,
  receipt_ref : @contracts.RecordRef?,
) -> Phase3HostSchedulerMutationV3 raise OrchestrationError {
  let facade = make_phase3_host_facade_v3(
    prior.time_commit_receipt,
    prior.time,
    scheduler,
    [
      for action in prior.actions => action
    ],
  )
  let (outcome_tag, outcome_digest) = phase3_mutation_outcome_binding_v3(
    outcome,
  )
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/PHASE3-HOST-SCHEDULER-MUTATION-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(prior.digest.text())
  writer.string(outcome_tag)
  writer.string(outcome_digest.text())
  writer.string(facade.digest.text())
  match claim_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
  }
  match receipt_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
  }
  let canonical = writer.finish()
  {
    outcome,
    facade,
    claim_ref,
    receipt_ref,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
/// Claim exactly one action from the committed-time facade. The selected
/// registry-bound store enforces the scheduler→time profile atomically.
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] phase3_host_claim_action_v3(
  store : S,
  current : Phase3HostFacadeV3,
  action_ref : @contracts.RecordRef,
  claim_id : String,
  event_id : String,
  command_idempotency_key : String,
  owner_ref : @contracts.RecordRef,
  ttl_millis : Int64,
  evidence : Array[@contracts.EvidenceRef],
) -> Phase3HostSchedulerMutationV3 raise {
  let action = current.require_action(action_ref)
  if !current.due_actions.any(value => value.action().record_ref() == action_ref) {
    raise ScheduleStateViolation(field="phase3_host_claim_not_due_v3")
  }
  let plan = prepare_scheduler_claim_v3(
    current.scheduler,
    current.time,
    action,
    claim_id,
    event_id,
    command_idempotency_key,
    owner_ref,
    ttl_millis,
    evidence,
  )
  let outcome = commit_scheduler_claim_v3(store, plan)
  let scheduler = fold_scheduler_v3(store.replay(current.scheduler_workflow))
  match outcome {
    @storage.FreshlyApplied(_) | @storage.AlreadyCommitted(_) =>
      if !scheduler
        .claims()
        .any(value => {
          value.record_ref() == plan.claim().record_ref() &&
          value.digest() == plan.claim().digest()
        }) {
        raise ReplayBindingViolation(field="phase3_host_claim_refold_v3")
      }
    @storage.GuardRejected(_) => ()
  }
  make_phase3_host_scheduler_mutation_v3(
    current,
    scheduler,
    outcome,
    Some(plan.claim().record_ref()),
    None,
  )
}

///|
/// Record a claim result from the latest committed-time facade. Expiry is
/// determined exclusively by that facade's durable time observation.
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] phase3_host_record_receipt_v3(
  store : S,
  current : Phase3HostFacadeV3,
  claim_ref : @contracts.RecordRef,
  receipt_id : String,
  event_id : String,
  command_idempotency_key : String,
  outcome_value : SchedulerReceiptOutcomeV3,
  evidence : Array[@contracts.EvidenceRef],
  result_ref? : @contracts.RecordRef,
  result_digest? : @contracts.ContentDigest,
) -> Phase3HostSchedulerMutationV3 raise {
  let plan = prepare_scheduler_receipt_v3(
    current.scheduler,
    current.time,
    claim_ref,
    receipt_id,
    event_id,
    command_idempotency_key,
    outcome_value,
    evidence,
    result_ref?,
    result_digest?,
  )
  let outcome = commit_scheduler_receipt_v3(store, plan)
  let scheduler = fold_scheduler_v3(store.replay(current.scheduler_workflow))
  match outcome {
    @storage.FreshlyApplied(_) | @storage.AlreadyCommitted(_) =>
      if !scheduler
        .receipts()
        .any(value => {
          value.record_ref() == plan.receipt().record_ref() &&
          value.digest() == plan.receipt().digest()
        }) {
        raise ReplayBindingViolation(field="phase3_host_receipt_refold_v3")
      }
    @storage.GuardRejected(_) => ()
  }
  make_phase3_host_scheduler_mutation_v3(
    current,
    scheduler,
    outcome,
    None,
    Some(plan.receipt().record_ref()),
  )
}

///|
pub fn Phase3HostSchedulerMutationV3::outcome(
  self : Phase3HostSchedulerMutationV3,
) -> @storage.ClassifiedGuardedCommitOutcome {
  self.outcome
}

///|
pub fn Phase3HostSchedulerMutationV3::facade(
  self : Phase3HostSchedulerMutationV3,
) -> Phase3HostFacadeV3 {
  self.facade
}

///|
pub fn Phase3HostSchedulerMutationV3::canonical_bytes(
  self : Phase3HostSchedulerMutationV3,
) -> Bytes {
  self.canonical
}

///|
pub fn Phase3HostSchedulerMutationV3::digest(
  self : Phase3HostSchedulerMutationV3,
) -> @contracts.ContentDigest {
  self.digest
}
