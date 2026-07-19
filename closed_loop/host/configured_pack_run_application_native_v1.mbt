///|
struct ConfiguredPackRunRootsV1 {
  work : String
  governance : String
  evidence : String
  time : String
  scheduler : String
  final_learning : String
  source : String
}

///|
struct ConfiguredPackRunWorkflowsV1 {
  work : @contracts.RecordRef
  governance : @contracts.RecordRef
  evidence : @contracts.RecordRef
  time : @contracts.RecordRef
  scheduler : @contracts.RecordRef
  final_learning : @contracts.RecordRef
  source : @contracts.RecordRef
}

///|
pub struct ConfiguredPackRunApplicationV1 {
  workspace_root : String
  run_id : String
  recovery_evidence_binding_id : String
  final_learning_binding_id : String
  effects_policy_ref : @contracts.RecordRef
  roots : ConfiguredPackRunRootsV1
  workflows : ConfiguredPackRunWorkflowsV1
  canonical_json : String
  digest : @contracts.ContentDigest
}

///|
fn require_configured_pack_run_application_v1(
  config : ConfiguredPackRunApplicationV1,
) -> Unit raise {
  if !config.workspace_root.has_prefix("/") ||
    config.workspace_root.contains("\\") ||
    config.workspace_root.iter().any(char => char.is_control()) ||
    (
      config.workspace_root.length() > 1 &&
      config.workspace_root.has_suffix("/")
    ) {
    fail("workspace_root must be a canonical absolute path")
  }
  require_run_id_v1(config.run_id)
  if config.recovery_evidence_binding_id.trim().is_empty() ||
    config.final_learning_binding_id.trim().is_empty() {
    fail("pack run binding identifiers must not be empty")
  }
  if config.workflows.work == config.workflows.governance ||
    config.workflows.work == config.workflows.evidence ||
    config.workflows.scheduler == config.workflows.time ||
    config.workflows.final_learning == config.workflows.source ||
    config.workflows.final_learning == config.workflows.governance ||
    config.workflows.source == config.workflows.governance {
    fail("pack run workflows must preserve stream separation")
  }
}

///|
pub fn decode_configured_pack_run_application_v1(
  value : Json,
) -> ConfiguredPackRunApplicationV1 raise {
  let fields = configured_host_object_v1(
    value,
    "configured_pack_run_application",
    [
      "contract_id", "contract_version", "workspace_root", "run_id", "recovery_evidence_binding_id",
      "final_learning_binding_id", "effects_policy_ref", "roots", "workflows",
    ],
  )
  if configured_host_string_v1(fields, "contract_id") !=
    "moonflow.configured-pack-run-application.v1" ||
    configured_host_string_v1(fields, "contract_version") != "1.0.0" {
    fail("unsupported configured pack run application contract")
  }
  let root_fields = configured_host_object_v1(
    configured_host_required_json_v1(fields, "roots"),
    "roots",
    [
      "work", "governance", "evidence", "time", "scheduler", "final_learning", "source",
    ],
  )
  let workflow_fields = configured_host_object_v1(
    configured_host_required_json_v1(fields, "workflows"),
    "workflows",
    [
      "work", "governance", "evidence", "time", "scheduler", "final_learning", "source",
    ],
  )
  let canonical_json = value.stringify()
  let config : ConfiguredPackRunApplicationV1 = {
    workspace_root: configured_host_string_v1(fields, "workspace_root"),
    run_id: configured_host_string_v1(fields, "run_id"),
    recovery_evidence_binding_id: configured_host_string_v1(
      fields, "recovery_evidence_binding_id",
    ),
    final_learning_binding_id: configured_host_string_v1(
      fields, "final_learning_binding_id",
    ),
    effects_policy_ref: configured_host_record_ref_v1(
      configured_host_required_json_v1(fields, "effects_policy_ref"),
      "effects_policy_ref",
    ),
    roots: {
      work: configured_host_string_v1(root_fields, "work"),
      governance: configured_host_string_v1(root_fields, "governance"),
      evidence: configured_host_string_v1(root_fields, "evidence"),
      time: configured_host_string_v1(root_fields, "time"),
      scheduler: configured_host_string_v1(root_fields, "scheduler"),
      final_learning: configured_host_string_v1(root_fields, "final_learning"),
      source: configured_host_string_v1(root_fields, "source"),
    },
    workflows: {
      work: configured_host_record_ref_v1(
        configured_host_required_json_v1(workflow_fields, "work"),
        "workflows.work",
      ),
      governance: configured_host_record_ref_v1(
        configured_host_required_json_v1(workflow_fields, "governance"),
        "workflows.governance",
      ),
      evidence: configured_host_record_ref_v1(
        configured_host_required_json_v1(workflow_fields, "evidence"),
        "workflows.evidence",
      ),
      time: configured_host_record_ref_v1(
        configured_host_required_json_v1(workflow_fields, "time"),
        "workflows.time",
      ),
      scheduler: configured_host_record_ref_v1(
        configured_host_required_json_v1(workflow_fields, "scheduler"),
        "workflows.scheduler",
      ),
      final_learning: configured_host_record_ref_v1(
        configured_host_required_json_v1(workflow_fields, "final_learning"),
        "workflows.final_learning",
      ),
      source: configured_host_record_ref_v1(
        configured_host_required_json_v1(workflow_fields, "source"),
        "workflows.source",
      ),
    },
    canonical_json,
    digest: @contracts.sha256_digest(@utf8.encode(canonical_json)),
  }
  require_configured_pack_run_application_v1(config)
  config
}

///|
fn configured_pack_run_operator_profile_v1(
  mutation : @orchestration.OperatorMutationHandoffV1,
) -> String {
  match mutation.companion() {
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
}

///|
fn configured_pack_run_host_v1(
  config : ConfiguredPackRunApplicationV1,
  input : Bytes,
) -> (String, ConfiguredPackHostV1) raise {
  let input_json = @json.parse(@utf8.decode(input))
  guard input_json is Object(fields) else {
    fail("pack run handoff must be a JSON object")
  }
  let contract_id = configured_host_string_v1(fields, "contract_id")
  if contract_id == "moonflow.operator-mutation-handoff.v1" {
    let mutation = @orchestration.decode_operator_mutation_handoff_v1(
      input_json,
    )
    let profile = configured_pack_run_operator_profile_v1(mutation)
    (
      "operator-mutation",
      {
        operation: ConfiguredOperatorV1,
        workspace_root: config.workspace_root,
        profile,
        run_id: Some(config.run_id),
        binding_id: None,
        recovery_evidence_binding_id: Some(config.recovery_evidence_binding_id),
        effects_policy_ref: Some(config.effects_policy_ref),
        roots: {
          mutation: Some(config.roots.work),
          source: None,
          governance: Some(config.roots.governance),
          evidence: Some(config.roots.evidence),
          time: Some(config.roots.time),
        },
        workflows: {
          mutation: Some(config.workflows.work),
          source: None,
          governance: Some(config.workflows.governance),
          evidence: Some(config.workflows.evidence),
          time: Some(config.workflows.time),
        },
        canonical_json: config.canonical_json,
        digest: config.digest,
      },
    )
  } else if contract_id == "moonflow.pack-handoff.v1" {
    let envelope = @orchestration.decode_pack_handoff_envelope_v1(input_json)
    match envelope.kind() {
      @orchestration.PackScheduledActionV3 =>
        (
          "scheduled-action",
          {
            operation: ConfiguredScheduleV1,
            workspace_root: config.workspace_root,
            profile: @orchestration.phase3_scheduler_time_profile_id_v3(),
            run_id: None,
            binding_id: None,
            recovery_evidence_binding_id: None,
            effects_policy_ref: None,
            roots: {
              mutation: Some(config.roots.scheduler),
              source: None,
              governance: None,
              evidence: None,
              time: Some(config.roots.time),
            },
            workflows: {
              mutation: Some(config.workflows.scheduler),
              source: None,
              governance: None,
              evidence: None,
              time: Some(config.workflows.time),
            },
            canonical_json: config.canonical_json,
            digest: config.digest,
          },
        )
      @orchestration.PackDeliverableCandidateV1
      | @orchestration.PackDeliverableDecisionV1
      | @orchestration.PackArtifactRevisionV1
      | @orchestration.PackDeliveryReceiptV1 =>
        (
          "final-deliverable",
          configured_pack_run_final_learning_host_v1(
            config,
            @orchestration.final_deliverable_guard_profile_id_v1(),
          ),
        )
      @orchestration.PackOutcomeObservationV1
      | @orchestration.PackGapAssessmentV1
      | @orchestration.PackImprovementProposalV1
      | @orchestration.PackOfflineEvaluationV1
      | @orchestration.PackHumanVersionDecisionV1 =>
        (
          "learning-loop",
          configured_pack_run_final_learning_host_v1(
            config,
            @orchestration.learning_loop_guard_profile_id_v1(),
          ),
        )
      @orchestration.PackOperatorCommandV1 =>
        fail(
          "operator commands require a typed operator mutation handoff companion",
        )
    }
  } else {
    fail("unsupported pack run handoff contract")
  }
}

///|
fn configured_pack_run_final_learning_host_v1(
  config : ConfiguredPackRunApplicationV1,
  profile : String,
) -> ConfiguredPackHostV1 {
  {
    operation: ConfiguredFinalLearningV1,
    workspace_root: config.workspace_root,
    profile,
    run_id: None,
    binding_id: Some(config.final_learning_binding_id),
    recovery_evidence_binding_id: None,
    effects_policy_ref: None,
    roots: {
      mutation: Some(config.roots.final_learning),
      source: Some(config.roots.source),
      governance: Some(config.roots.governance),
      evidence: None,
      time: None,
    },
    workflows: {
      mutation: Some(config.workflows.final_learning),
      source: Some(config.workflows.source),
      governance: Some(config.workflows.governance),
      evidence: None,
      time: None,
    },
    canonical_json: config.canonical_json,
    digest: config.digest,
  }
}

///|
fn configured_pack_run_projection_v1(
  config : ConfiguredPackRunApplicationV1,
) -> @orchestration.MoonFlowOperatorSurfaceV1 raise {
  let work_store = @storage.FileSystemStore::open(
    config.workspace_root,
    config.roots.work,
  )
  let governance_store = @storage.FileSystemStore::open(
    config.workspace_root,
    config.roots.governance,
  )
  let evidence_store = @storage.FileSystemStore::open(
    config.workspace_root,
    config.roots.evidence,
  )
  let time_store = @storage.FileSystemStore::open(
    config.workspace_root,
    config.roots.time,
  )
  let final_learning_store = @storage.FileSystemStore::open(
    config.workspace_root,
    config.roots.final_learning,
  )
  let source_store = @storage.FileSystemStore::open(
    config.workspace_root,
    config.roots.source,
  )
  let work_replay = work_store.replay(config.workflows.work)
  let governance_replay = governance_store.replay(config.workflows.governance)
  let recovery = @orchestration.fold_governed_recovery_v3(
    @effects.EffectsProjection::new(
      config.workflows.work,
      config.effects_policy_ref,
    ),
    work_replay,
    governance_replay,
  )
  let evidence = @orchestration.fold_recovery_evidence_stream_v3(
    @orchestration.RecoveryEvidenceStreamBindingV3::new(
      config.recovery_evidence_binding_id,
      config.workflows.evidence,
      config.workflows.work,
    ),
    evidence_store.replay(config.workflows.evidence),
    work_replay,
  )
  let time = @orchestration.fold_time_evidence_v3(
    time_store.replay(config.workflows.time),
  )
  let final_learning = @orchestration.fold_final_learning_stream_v1(
    @orchestration.FinalLearningStreamBindingV1::new(
      config.final_learning_binding_id,
      config.workflows.final_learning,
      config.workflows.source,
      config.workflows.governance,
    ),
    final_learning_store.replay(config.workflows.final_learning),
    source_store.replay(config.workflows.source),
    governance_replay,
  )
  @orchestration.MoonFlowOperatorSurfaceV1::from_complete_projections_v1(
    config.run_id,
    recovery,
    evidence,
    time,
    final_learning,
  )
}

///|
pub struct PackRunApplicationReceiptV1 {
  host_receipt : @orchestration.PackHostReceiptV1
  operator_projection : @orchestration.MoonFlowOperatorSurfaceV1
  json : Json
  canonical_json : String
  digest : @contracts.ContentDigest
}

///|
pub fn advance_configured_pack_run_v1(
  config : ConfiguredPackRunApplicationV1,
  input : Bytes,
) -> PackRunApplicationReceiptV1 raise {
  let (operation, host) = configured_pack_run_host_v1(config, input)
  let host_receipt = commit_configured_pack_handoff_v1(host, input)
  let operator_projection = configured_pack_run_projection_v1(config)
  let json : Json = {
    "contract_id": "moonflow.pack-run-application-receipt.v1",
    "contract_version": "1.0.0",
    "run_id": config.run_id,
    "operation": operation,
    "host_receipt": host_receipt.to_json(),
    "operator_projection": operator_projection.json(),
    "operator_projection_digest": operator_projection.digest().text(),
    "application_config_digest": config.digest.text(),
  }
  let canonical_json = json.stringify()
  {
    host_receipt,
    operator_projection,
    json,
    canonical_json,
    digest: @contracts.sha256_digest(@utf8.encode(canonical_json)),
  }
}

///|
pub fn advance_configured_pack_run_json_v1(
  config : Json,
  input : Bytes,
) -> PackRunApplicationReceiptV1 raise {
  advance_configured_pack_run_v1(
    decode_configured_pack_run_application_v1(config),
    input,
  )
}

///|
pub fn PackRunApplicationReceiptV1::host_receipt(
  self : PackRunApplicationReceiptV1,
) -> @orchestration.PackHostReceiptV1 {
  self.host_receipt
}

///|
pub fn PackRunApplicationReceiptV1::operator_projection(
  self : PackRunApplicationReceiptV1,
) -> @orchestration.MoonFlowOperatorSurfaceV1 {
  self.operator_projection
}

///|
pub fn PackRunApplicationReceiptV1::to_json(
  self : PackRunApplicationReceiptV1,
) -> Json {
  self.json
}

///|
pub fn PackRunApplicationReceiptV1::canonical_json(
  self : PackRunApplicationReceiptV1,
) -> String {
  self.canonical_json
}

///|
pub fn PackRunApplicationReceiptV1::digest(
  self : PackRunApplicationReceiptV1,
) -> @contracts.ContentDigest {
  self.digest
}
