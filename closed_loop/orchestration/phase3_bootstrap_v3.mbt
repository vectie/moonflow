///|
let phase3_scheduler_time_profile_id_text_v3 = "closed-loop.scheduler.committed-time.v3"

///|
let phase3_scheduler_time_profile_name_text_v3 = "scheduler mutation guarded by committed time stream"

///|
pub fn phase3_scheduler_time_profile_id_v3() -> String {
  phase3_scheduler_time_profile_id_text_v3
}

///|
pub fn phase3_scheduler_time_profile_name_v3() -> String {
  phase3_scheduler_time_profile_name_text_v3
}

///|
/// Stable generic configuration for both scheduler-claim and scheduler-
/// receipt mutations. The exact ordered guard set contains only the committed
/// time stream.
pub fn phase3_scheduler_time_profile_config_v3(
  time_workflow : @contracts.RecordRef,
) -> @storage.GuardProfileConfig raise {
  @storage.GuardProfileConfig::new(
    phase3_scheduler_time_profile_id_text_v3,
    phase3_scheduler_time_profile_name_text_v3,
    [time_workflow],
  )
}

///|
/// Initial in-memory activation for a scheduler stream. Memory storage keeps
/// the mutation and time roots in one atomic backing store while preserving
/// their independent workflow identities.
pub fn activate_phase3_scheduler_memory_v3(
  store : @storage.MemoryStore,
  scheduler_workflow : @contracts.RecordRef,
  time_workflow : @contracts.RecordRef,
) -> @storage.GuardedWorkflowActivationReceipt raise {
  store.activate_guarded_workflow_profiles(scheduler_workflow, [
    phase3_scheduler_time_profile_config_v3(time_workflow),
  ])
}

///|
/// Append the Phase-3 scheduler/time profile to an already activated memory
/// registry without replacing any existing operation profile.
pub fn evolve_phase3_scheduler_memory_v3(
  store : @storage.MemoryStore,
  scheduler_workflow : @contracts.RecordRef,
  time_workflow : @contracts.RecordRef,
  prior : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.GuardedWorkflowEvolutionReceipt raise {
  store.add_guard_profile(
    scheduler_workflow,
    prior,
    phase3_scheduler_time_profile_config_v3(time_workflow),
  )
}

///|
pub fn bind_phase3_scheduler_memory_v3(
  store : @storage.MemoryStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.GuardedMemoryStore raise {
  @storage.GuardedMemoryStore::new_for_profile(
    store, receipt, phase3_scheduler_time_profile_id_text_v3,
  )
}
