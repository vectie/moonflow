///|
/// Initial native-filesystem activation. The scheduler and committed-time
/// workflows must use independently opened roots in the same workspace.
pub fn activate_phase3_scheduler_filesystem_v3(
  scheduler_store : @storage.FileSystemStore,
  time_store : @storage.FileSystemStore,
  scheduler_workflow : @contracts.RecordRef,
  time_workflow : @contracts.RecordRef,
) -> @storage.GuardedWorkflowActivationReceipt raise {
  scheduler_store.activate_guarded_workflow_profiles(
    scheduler_workflow,
    [phase3_scheduler_time_profile_config_v3(time_workflow)],
    [[time_store]],
  )
}

///|
pub fn evolve_phase3_scheduler_filesystem_v3(
  scheduler_store : @storage.FileSystemStore,
  time_store : @storage.FileSystemStore,
  scheduler_workflow : @contracts.RecordRef,
  time_workflow : @contracts.RecordRef,
  prior : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.GuardedWorkflowEvolutionReceipt raise {
  scheduler_store.add_guard_profile(
    scheduler_workflow,
    prior,
    phase3_scheduler_time_profile_config_v3(time_workflow),
    [time_store],
  )
}

///|
pub fn bind_phase3_scheduler_filesystem_v3(
  scheduler_store : @storage.FileSystemStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.RegistryBoundFileSystemStore raise {
  @storage.RegistryBoundFileSystemStore::new_for_profile(
    scheduler_store, receipt, phase3_scheduler_time_profile_id_text_v3,
  )
}
