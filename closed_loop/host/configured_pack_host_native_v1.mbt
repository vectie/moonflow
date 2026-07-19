///|
pub(all) enum ConfiguredPackHostOperationV1 {
  ConfiguredFinalLearningV1
  ConfiguredScheduleV1
  ConfiguredOperatorV1
}

///|
struct ConfiguredHostRootsV1 {
  mutation : String?
  source : String?
  governance : String?
  evidence : String?
  time : String?
}

///|
struct ConfiguredHostWorkflowsV1 {
  mutation : @contracts.RecordRef?
  source : @contracts.RecordRef?
  governance : @contracts.RecordRef?
  evidence : @contracts.RecordRef?
  time : @contracts.RecordRef?
}

///|
pub struct ConfiguredPackHostV1 {
  operation : ConfiguredPackHostOperationV1
  workspace_root : String
  profile : String
  run_id : String?
  binding_id : String?
  recovery_evidence_binding_id : String?
  effects_policy_ref : @contracts.RecordRef?
  roots : ConfiguredHostRootsV1
  workflows : ConfiguredHostWorkflowsV1
  canonical_json : String
  digest : @contracts.ContentDigest
}

///|
fn configured_host_object_v1(
  value : Json,
  field : String,
  allowed : Array[String],
) -> Map[String, Json] raise {
  guard value is Object(fields) else { fail("missing object: \{field}") }
  for key, _ in fields {
    if !allowed.contains(key) {
      fail("unsupported configured host field: \{field}.\{key}")
    }
  }
  fields
}

///|
fn configured_host_string_v1(
  fields : Map[String, Json],
  key : String,
) -> String raise {
  guard fields.get(key) is Some(String(value)) && !value.trim().is_empty() else {
    fail("missing configured host string: \{key}")
  }
  value
}

///|
fn configured_host_optional_string_v1(
  fields : Map[String, Json],
  key : String,
) -> String? raise {
  match fields.get(key) {
    Some(Null) => None
    Some(String(value)) if !value.trim().is_empty() => Some(value)
    _ => fail("invalid configured host string: \{key}")
  }
}

///|
fn configured_host_record_ref_v1(
  value : Json,
  field : String,
) -> @contracts.RecordRef raise {
  let fields = configured_host_object_v1(value, field, [
    "kind", "id", "version", "digest",
  ])
  @contracts.RecordRef::new(
    configured_host_string_v1(fields, "kind"),
    configured_host_string_v1(fields, "id"),
    configured_host_string_v1(fields, "version"),
    configured_host_string_v1(fields, "digest"),
  ) catch {
    _ => fail("invalid configured host record ref: \{field}")
  }
}

///|
fn configured_host_optional_ref_v1(
  value : Json,
  field : String,
) -> @contracts.RecordRef? raise {
  match value {
    Null => None
    _ => Some(configured_host_record_ref_v1(value, field))
  }
}

///|
fn configured_host_required_json_v1(
  fields : Map[String, Json],
  key : String,
) -> Json raise {
  guard fields.get(key) is Some(value) else {
    fail("missing configured host field: \{key}")
  }
  value
}

///|
fn configured_host_operation_v1(
  value : String,
) -> ConfiguredPackHostOperationV1 raise {
  match value {
    "final-learning" => ConfiguredFinalLearningV1
    "schedule" => ConfiguredScheduleV1
    "operator" => ConfiguredOperatorV1
    _ => fail("unsupported configured host operation")
  }
}

///|
fn require_configured_host_shape_v1(
  config : ConfiguredPackHostV1,
) -> Unit raise {
  if !config.workspace_root.has_prefix("/") ||
    config.workspace_root.contains("\\") ||
    (
      config.workspace_root.length() > 1 &&
      config.workspace_root.has_suffix("/")
    ) {
    fail("workspace_root must be a canonical absolute path")
  }
  match config.operation {
    ConfiguredFinalLearningV1 =>
      if config.roots.mutation is None ||
        config.roots.source is None ||
        config.roots.governance is None ||
        config.workflows.mutation is None ||
        config.workflows.source is None ||
        config.workflows.governance is None ||
        config.binding_id is None ||
        config.run_id is Some(_) ||
        config.effects_policy_ref is Some(_) ||
        (
          config.profile !=
          @orchestration.final_deliverable_guard_profile_id_v1() &&
          config.profile != @orchestration.learning_loop_guard_profile_id_v1()
        ) {
        fail("incomplete final-learning host configuration")
      }
    ConfiguredScheduleV1 =>
      if config.roots.mutation is None ||
        config.roots.time is None ||
        config.workflows.mutation is None ||
        config.workflows.time is None ||
        config.profile != @orchestration.phase3_scheduler_time_profile_id_v3() ||
        config.run_id is Some(_) ||
        config.effects_policy_ref is Some(_) {
        fail("incomplete scheduler host configuration")
      }
    ConfiguredOperatorV1 =>
      if config.roots.mutation is None ||
        config.roots.governance is None ||
        config.roots.evidence is None ||
        config.roots.time is None ||
        config.workflows.mutation is None ||
        config.workflows.governance is None ||
        config.workflows.evidence is None ||
        config.workflows.time is None ||
        config.run_id is None ||
        config.recovery_evidence_binding_id is None ||
        config.effects_policy_ref is None ||
        (
          config.profile !=
          @orchestration.phase2_governance_guard_profile_id_v3() &&
          config.profile !=
          @orchestration.phase2_governance_recovery_evidence_guard_profile_id_v3()
        ) {
        fail("incomplete operator host configuration")
      }
  }
}

///|
pub fn decode_configured_pack_host_v1(
  value : Json,
) -> ConfiguredPackHostV1 raise {
  let fields = configured_host_object_v1(value, "configured_pack_host", [
    "contract_id", "contract_version", "operation", "workspace_root", "profile",
    "run_id", "binding_id", "recovery_evidence_binding_id", "effects_policy_ref",
    "roots", "workflows",
  ])
  if configured_host_string_v1(fields, "contract_id") !=
    "moonflow.configured-pack-host.v1" ||
    configured_host_string_v1(fields, "contract_version") != "1.0.0" {
    fail("unsupported configured pack host contract")
  }
  let root_fields = configured_host_object_v1(
    configured_host_required_json_v1(fields, "roots"),
    "roots",
    ["mutation", "source", "governance", "evidence", "time"],
  )
  let workflow_fields = configured_host_object_v1(
    configured_host_required_json_v1(fields, "workflows"),
    "workflows",
    ["mutation", "source", "governance", "evidence", "time"],
  )
  let config : ConfiguredPackHostV1 = {
    operation: configured_host_operation_v1(
      configured_host_string_v1(fields, "operation"),
    ),
    workspace_root: configured_host_string_v1(fields, "workspace_root"),
    profile: configured_host_string_v1(fields, "profile"),
    run_id: configured_host_optional_string_v1(fields, "run_id"),
    binding_id: configured_host_optional_string_v1(fields, "binding_id"),
    recovery_evidence_binding_id: configured_host_optional_string_v1(
      fields, "recovery_evidence_binding_id",
    ),
    effects_policy_ref: configured_host_optional_ref_v1(
      configured_host_required_json_v1(fields, "effects_policy_ref"),
      "effects_policy_ref",
    ),
    roots: {
      mutation: configured_host_optional_string_v1(root_fields, "mutation"),
      source: configured_host_optional_string_v1(root_fields, "source"),
      governance: configured_host_optional_string_v1(root_fields, "governance"),
      evidence: configured_host_optional_string_v1(root_fields, "evidence"),
      time: configured_host_optional_string_v1(root_fields, "time"),
    },
    workflows: {
      mutation: configured_host_optional_ref_v1(
        configured_host_required_json_v1(workflow_fields, "mutation"),
        "workflows.mutation",
      ),
      source: configured_host_optional_ref_v1(
        configured_host_required_json_v1(workflow_fields, "source"),
        "workflows.source",
      ),
      governance: configured_host_optional_ref_v1(
        configured_host_required_json_v1(workflow_fields, "governance"),
        "workflows.governance",
      ),
      evidence: configured_host_optional_ref_v1(
        configured_host_required_json_v1(workflow_fields, "evidence"),
        "workflows.evidence",
      ),
      time: configured_host_optional_ref_v1(
        configured_host_required_json_v1(workflow_fields, "time"),
        "workflows.time",
      ),
    },
    canonical_json: value.stringify(),
    digest: @contracts.sha256_digest(@utf8.encode(value.stringify())),
  }
  require_configured_host_shape_v1(config)
  config
}

///|
fn configured_host_store_v1(
  config : ConfiguredPackHostV1,
  root : String?,
  field : String,
) -> @storage.FileSystemStore raise {
  guard root is Some(value) else { fail("missing storage root: \{field}") }
  @storage.FileSystemStore::open(config.workspace_root, value)
}

///|
fn configured_host_workflow_v1(
  value : @contracts.RecordRef?,
  field : String,
) -> @contracts.RecordRef raise {
  guard value is Some(workflow) else { fail("missing workflow: \{field}") }
  workflow
}

///|
fn configured_final_learning_commit_v1(
  config : ConfiguredPackHostV1,
  input : Bytes,
) -> @orchestration.PackHostReceiptV1 raise {
  let stream_store = configured_host_store_v1(
    config,
    config.roots.mutation,
    "mutation",
  )
  let source_store = configured_host_store_v1(
    config,
    config.roots.source,
    "source",
  )
  let governance_store = configured_host_store_v1(
    config,
    config.roots.governance,
    "governance",
  )
  let stream_workflow = configured_host_workflow_v1(
    config.workflows.mutation,
    "mutation",
  )
  let source_workflow = configured_host_workflow_v1(
    config.workflows.source,
    "source",
  )
  let governance_workflow = configured_host_workflow_v1(
    config.workflows.governance,
    "governance",
  )
  guard config.binding_id is Some(binding_id) else {
    fail("missing final-learning binding_id")
  }
  let binding = @orchestration.FinalLearningStreamBindingV1::new(
    binding_id, stream_workflow, source_workflow, governance_workflow,
  )
  let activation = match
    stream_store.current_guarded_activation_receipt(stream_workflow) {
    Some(value) => value
    None =>
      @orchestration.activate_final_learning_filesystem_profiles_v1(
        stream_store, binding, source_store, governance_store,
      )
  }
  let envelope = @orchestration.decode_pack_handoff_json_bytes_v1(input)
  let token = envelope.digest().hex()
  if config.profile == @orchestration.final_deliverable_guard_profile_id_v1() {
    @orchestration.commit_pack_final_learning_handoff_v1(
      @orchestration.bind_final_deliverable_filesystem_store_v1(
        stream_store, activation,
      ),
      binding,
      envelope,
      "pack-host-final-event-\{token}",
      "pack-host-final-command-\{token}",
    )
  } else {
    @orchestration.commit_pack_final_learning_handoff_v1(
      @orchestration.bind_learning_loop_filesystem_store_v1(
        stream_store, activation,
      ),
      binding,
      envelope,
      "pack-host-learning-event-\{token}",
      "pack-host-learning-command-\{token}",
    )
  }
}

///|
fn configured_schedule_commit_v1(
  config : ConfiguredPackHostV1,
  input : Bytes,
) -> @orchestration.PackHostReceiptV1 raise {
  let scheduler_store = configured_host_store_v1(
    config,
    config.roots.mutation,
    "mutation",
  )
  let time_store = configured_host_store_v1(config, config.roots.time, "time")
  let scheduler_workflow = configured_host_workflow_v1(
    config.workflows.mutation,
    "mutation",
  )
  let time_workflow = configured_host_workflow_v1(config.workflows.time, "time")
  let activation = match
    scheduler_store.current_guarded_activation_receipt(scheduler_workflow) {
    Some(value) => value
    None =>
      @orchestration.activate_phase3_scheduler_filesystem_v3(
        scheduler_store, time_store, scheduler_workflow, time_workflow,
      )
  }
  let bound = @orchestration.bind_phase3_scheduler_filesystem_v3(
    scheduler_store, activation,
  )
  let scheduler = @orchestration.fold_scheduler_v3(
    scheduler_store.replay(scheduler_workflow),
  )
  let time = @orchestration.fold_time_evidence_v3(
    time_store.replay(time_workflow),
  )
  let envelope = @orchestration.decode_pack_handoff_json_bytes_v1(input)
  let token = envelope.digest().hex()
  @orchestration.commit_pack_scheduled_action_handoff_v1(
    bound,
    scheduler,
    time,
    envelope,
    "pack-host-registration-\{token}",
    "pack-host-schedule-event-\{token}",
    "pack-host-schedule-command-\{token}",
  )
}

///|
fn configured_operator_commit_v1(
  config : ConfiguredPackHostV1,
  input : Bytes,
) -> @orchestration.PackHostReceiptV1 raise {
  let work_store = configured_host_store_v1(
    config,
    config.roots.mutation,
    "mutation",
  )
  let governance_store = configured_host_store_v1(
    config,
    config.roots.governance,
    "governance",
  )
  let evidence_store = configured_host_store_v1(
    config,
    config.roots.evidence,
    "evidence",
  )
  let time_store = configured_host_store_v1(config, config.roots.time, "time")
  let work_workflow = configured_host_workflow_v1(
    config.workflows.mutation,
    "mutation",
  )
  let governance_workflow = configured_host_workflow_v1(
    config.workflows.governance,
    "governance",
  )
  let evidence_workflow = configured_host_workflow_v1(
    config.workflows.evidence,
    "evidence",
  )
  let time_workflow = configured_host_workflow_v1(config.workflows.time, "time")
  guard config.run_id is Some(run_id) &&
    config.recovery_evidence_binding_id is Some(evidence_binding_id) &&
    config.effects_policy_ref is Some(effects_policy_ref) else {
    fail("incomplete operator projection configuration")
  }
  let activation = match
    work_store.current_guarded_activation_receipt(work_workflow) {
    Some(value) => value
    None =>
      @orchestration.activate_phase2_filesystem_guard_profiles_v3(
        work_store, work_workflow, governance_store, governance_workflow, evidence_store,
        evidence_workflow,
      )
  }
  let mutation = @orchestration.decode_operator_mutation_handoff_json_v1(input)
  let required_profile = match mutation.companion() {
    @orchestration.OperatorRecoveryRetryCompanionV1(source, _) =>
      if source.from_callback_evidence() {
        @orchestration.phase2_governance_recovery_evidence_guard_profile_id_v3()
      } else {
        @orchestration.phase2_governance_guard_profile_id_v3()
      }
    @orchestration.OperatorManualHoldCompanionV1(_, _, _, _)
    | @orchestration.OperatorManualResumeCompanionV1(_, _, _, _)
    | @orchestration.OperatorQuarantineCompanionV1(_, _) =>
      @orchestration.phase2_governance_recovery_evidence_guard_profile_id_v3()
  }
  if config.profile != required_profile {
    fail("configured operator profile does not match mutation companion")
  }
  let work_replay = work_store.replay(work_workflow)
  let governance_replay = governance_store.replay(governance_workflow)
  let evidence_replay = evidence_store.replay(evidence_workflow)
  let current = @orchestration.fold_governed_recovery_v3(
    @effects.EffectsProjection::new(work_workflow, effects_policy_ref),
    work_replay,
    governance_replay,
  )
  let evidence = @orchestration.fold_recovery_evidence_stream_v3(
    @orchestration.RecoveryEvidenceStreamBindingV3::new(
      evidence_binding_id, evidence_workflow, work_workflow,
    ),
    evidence_replay,
    work_replay,
  )
  let time = @orchestration.fold_time_evidence_v3(
    time_store.replay(time_workflow),
  )
  if required_profile == @orchestration.phase2_governance_guard_profile_id_v3() {
    @orchestration.execute_pack_operator_mutation_at_committed_time_v1(
      @orchestration.bind_phase2_filesystem_governance_store_v3(
        work_store, activation,
      ),
      run_id,
      current,
      evidence,
      time,
      mutation,
    )
  } else {
    @orchestration.execute_pack_operator_mutation_at_committed_time_v1(
      @orchestration.bind_phase2_filesystem_recovery_evidence_store_v3(
        work_store, activation,
      ),
      run_id,
      current,
      evidence,
      time,
      mutation,
    )
  }
}

///|
/// Opens or provisions only the registry-bound roots declared by the generic
/// host configuration, then commits one pack handoff. Reconciliation remains
/// outside this facade and no provider or ambient clock is consulted.
pub fn commit_configured_pack_handoff_v1(
  config : ConfiguredPackHostV1,
  input : Bytes,
) -> @orchestration.PackHostReceiptV1 raise {
  match config.operation {
    ConfiguredFinalLearningV1 =>
      configured_final_learning_commit_v1(config, input)
    ConfiguredScheduleV1 => configured_schedule_commit_v1(config, input)
    ConfiguredOperatorV1 => configured_operator_commit_v1(config, input)
  }
}

///|
pub fn commit_configured_pack_handoff_json_v1(
  config : Json,
  input : Bytes,
) -> @orchestration.PackHostReceiptV1 raise {
  commit_configured_pack_handoff_v1(
    decode_configured_pack_host_v1(config),
    input,
  )
}
