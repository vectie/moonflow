///|
let phase2_governance_recovery_evidence_profile_id_v3 = "governance+recovery-evidence"

///|
let phase2_governance_recovery_evidence_profile_name_v3 = "governance + recovery evidence"

///|
/// Stable profile id for ordinary governed work mutations.
pub fn phase2_governance_guard_profile_id_v3() -> String {
  @storage.default_guard_profile_id()
}

///|
/// Stable profile id for work mutations that also consume recovery evidence.
pub fn phase2_governance_recovery_evidence_guard_profile_id_v3() -> String {
  phase2_governance_recovery_evidence_profile_id_v3
}

///|
pub fn phase2_governance_guard_profile_config_v3(
  governance_workflow : @contracts.RecordRef,
) -> @storage.GuardProfileConfig raise {
  @storage.GuardProfileConfig::new(
    phase2_governance_guard_profile_id_v3(),
    @storage.default_guard_profile_name(),
    [governance_workflow],
  )
}

///|
/// The exact order is protocol data: governance first, recovery evidence
/// second. Callers never construct or reorder this list themselves.
pub fn phase2_governance_recovery_evidence_guard_profile_config_v3(
  governance_workflow : @contracts.RecordRef,
  evidence_workflow : @contracts.RecordRef,
) -> @storage.GuardProfileConfig raise {
  if governance_workflow == evidence_workflow {
    raise RecoveryViolation(field="phase2_guard_profile_independent_streams_v3")
  }
  @storage.GuardProfileConfig::new(
    phase2_governance_recovery_evidence_guard_profile_id_v3(),
    phase2_governance_recovery_evidence_profile_name_v3,
    [governance_workflow, evidence_workflow],
  )
}

///|
pub fn phase2_guard_profile_configs_v3(
  governance_workflow : @contracts.RecordRef,
  evidence_workflow : @contracts.RecordRef,
) -> Array[@storage.GuardProfileConfig] raise {
  [
    phase2_governance_guard_profile_config_v3(governance_workflow),
    phase2_governance_recovery_evidence_guard_profile_config_v3(
      governance_workflow, evidence_workflow,
    ),
  ]
}

///|
/// One-call portable host activation for a fresh Phase 2 work registry.
pub fn activate_phase2_memory_guard_profiles_v3(
  store : @storage.MemoryStore,
  work_workflow : @contracts.RecordRef,
  governance_workflow : @contracts.RecordRef,
  evidence_workflow : @contracts.RecordRef,
) -> @storage.GuardedWorkflowActivationReceipt raise {
  store.activate_guarded_workflow_profiles(
    work_workflow,
    phase2_guard_profile_configs_v3(governance_workflow, evidence_workflow),
  )
}

///|
/// One-call native host activation for a fresh Phase 2 work registry. The
/// nested root order mirrors the canonical workflow order in each profile.
#cfg(target="native")
pub fn activate_phase2_filesystem_guard_profiles_v3(
  work_store : @storage.FileSystemStore,
  work_workflow : @contracts.RecordRef,
  governance_store : @storage.FileSystemStore,
  governance_workflow : @contracts.RecordRef,
  evidence_store : @storage.FileSystemStore,
  evidence_workflow : @contracts.RecordRef,
) -> @storage.GuardedWorkflowActivationReceipt raise {
  work_store.activate_guarded_workflow_profiles(
    work_workflow,
    phase2_guard_profile_configs_v3(governance_workflow, evidence_workflow),
    [[governance_store], [governance_store, evidence_store]],
  )
}

///|
/// Migration helper for a legacy governance-only in-memory activation.
pub fn add_phase2_memory_recovery_evidence_profile_v3(
  store : @storage.MemoryStore,
  work_workflow : @contracts.RecordRef,
  prior : @storage.GuardedWorkflowActivationReceipt,
  governance_workflow : @contracts.RecordRef,
  evidence_workflow : @contracts.RecordRef,
) -> @storage.GuardedWorkflowEvolutionReceipt raise {
  store.add_guard_profile(
    work_workflow,
    prior,
    phase2_governance_recovery_evidence_guard_profile_config_v3(
      governance_workflow, evidence_workflow,
    ),
  )
}

///|
/// Migration helper for a legacy governance-only filesystem activation.
#cfg(target="native")
pub fn add_phase2_filesystem_recovery_evidence_profile_v3(
  work_store : @storage.FileSystemStore,
  work_workflow : @contracts.RecordRef,
  prior : @storage.GuardedWorkflowActivationReceipt,
  governance_store : @storage.FileSystemStore,
  governance_workflow : @contracts.RecordRef,
  evidence_store : @storage.FileSystemStore,
  evidence_workflow : @contracts.RecordRef,
) -> @storage.GuardedWorkflowEvolutionReceipt raise {
  work_store.add_guard_profile(
    work_workflow,
    prior,
    phase2_governance_recovery_evidence_guard_profile_config_v3(
      governance_workflow, evidence_workflow,
    ),
    [governance_store, evidence_store],
  )
}

///|
pub fn bind_phase2_memory_governance_store_v3(
  store : @storage.MemoryStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.GuardedMemoryStore raise {
  @storage.GuardedMemoryStore::new_for_profile(
    store,
    receipt,
    phase2_governance_guard_profile_id_v3(),
  )
}

///|
pub fn bind_phase2_memory_recovery_evidence_store_v3(
  store : @storage.MemoryStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.GuardedMemoryStore raise {
  @storage.GuardedMemoryStore::new_for_profile(
    store,
    receipt,
    phase2_governance_recovery_evidence_guard_profile_id_v3(),
  )
}

///|
#cfg(target="native")
pub fn bind_phase2_filesystem_governance_store_v3(
  store : @storage.FileSystemStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.RegistryBoundFileSystemStore raise {
  @storage.RegistryBoundFileSystemStore::new_for_profile(
    store,
    receipt,
    phase2_governance_guard_profile_id_v3(),
  )
}

///|
#cfg(target="native")
pub fn bind_phase2_filesystem_recovery_evidence_store_v3(
  store : @storage.FileSystemStore,
  receipt : @storage.GuardedWorkflowActivationReceipt,
) -> @storage.RegistryBoundFileSystemStore raise {
  @storage.RegistryBoundFileSystemStore::new_for_profile(
    store,
    receipt,
    phase2_governance_recovery_evidence_guard_profile_id_v3(),
  )
}

///|
fn[S : @storage.RegistryBoundGuardedStoragePort] require_phase2_selected_profile_v3(
  store : S,
  expected_profile_id : String,
  request : @storage.GuardedCommitRequest,
) -> Unit raise {
  let profile = store.selected_guard_profile()
  let workflows = profile.guard_workflows()
  let guards = request.guards()
  if profile.profile_id() != expected_profile_id ||
    workflows.length() != guards.length() {
    raise RecoveryViolation(field="phase2_selected_guard_profile_v3")
  }
  for index, workflow in workflows {
    if workflow != guards[index].workflow() {
      raise RecoveryViolation(field="phase2_selected_guard_profile_v3")
    }
  }
}

///|
pub fn[S : @storage.RegistryBoundGuardedStoragePort] require_phase2_governance_guard_profile_v3(
  store : S,
  request : @storage.GuardedCommitRequest,
) -> Unit raise {
  require_phase2_selected_profile_v3(
    store,
    phase2_governance_guard_profile_id_v3(),
    request,
  )
}

///|
pub fn[S : @storage.RegistryBoundGuardedStoragePort] require_phase2_recovery_evidence_guard_profile_v3(
  store : S,
  request : @storage.GuardedCommitRequest,
) -> Unit raise {
  require_phase2_selected_profile_v3(
    store,
    phase2_governance_recovery_evidence_guard_profile_id_v3(),
    request,
  )
}
