///|
pub struct OperatorActionMaterializationReceiptV1 {
  run_id : String
  operator_projection_digest : @contracts.ContentDigest
  catalog_digest : @contracts.ContentDigest
  action_count : Int
  canonical_json : String
  digest : @contracts.ContentDigest
}

///|
fn operator_action_json_string_v1(value : Json, key : String) -> String? {
  guard value is Object(fields) else { return None }
  match fields.get(key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
async fn require_operator_projection_binding_v1(
  run_path : String,
  run_id : String,
  expected_digest : @contracts.ContentDigest,
) -> Unit {
  let path = "\{run_path}/operator-projection.json"
  if !@fs.exists(path) {
    fail("operator projection is not published")
  }
  let bytes = @fs.read_file(path).binary()
  if @contracts.sha256_digest(bytes) != expected_digest {
    fail("operator projection digest does not match action catalog")
  }
  let text = @utf8.decode(bytes) catch {
    _ => fail("operator projection is not valid UTF-8")
  }
  let json = @json.parse(text) catch {
    _ => fail("operator projection is not valid JSON")
  }
  if operator_action_json_string_v1(json, "contract_id") !=
    Some("moonflow.operator-surface.v1") ||
    operator_action_json_string_v1(json, "run_id") != Some(run_id) {
    fail("operator projection run binding does not match action catalog")
  }
}

///|
async fn operator_action_server_file_v1(
  run_path : String,
  relative : String,
) -> String {
  let path = "\{run_path}/\{relative}"
  if !@fs.exists(path) {
    fail("operator action server input is missing")
  }
  let canonical = @fs.realpath(path)
  if !canonical.has_prefix(run_path + "/") {
    fail("operator action server input escapes the run")
  }
  canonical
}

///|
fn require_final_learning_handoff_kind_v1(
  kind : @orchestration.PackHandoffRecordKindV1,
) -> Unit raise {
  match kind {
    @orchestration.PackDeliverableCandidateV1
    | @orchestration.PackDeliverableDecisionV1
    | @orchestration.PackArtifactRevisionV1
    | @orchestration.PackDeliveryReceiptV1
    | @orchestration.PackOutcomeObservationV1
    | @orchestration.PackGapAssessmentV1
    | @orchestration.PackImprovementProposalV1
    | @orchestration.PackOfflineEvaluationV1
    | @orchestration.PackHumanVersionDecisionV1 => ()
    _ => fail("unsupported final-learning handoff kind")
  }
}

///|
async fn validate_operator_action_server_inputs_v1(
  run_path : String,
  run_id : String,
  descriptor : @orchestration.OperatorActionDescriptorV1,
) -> Unit {
  let config_path = operator_action_server_file_v1(
    run_path,
    descriptor.host_config_relative_path(),
  )
  let handoff_path = operator_action_server_file_v1(
    run_path,
    descriptor.handoff_relative_path(),
  )
  let config_json = @json.parse(@fs.read_file(config_path).text()) catch {
    _ => fail("operator action host config is not valid JSON")
  }
  let config = decode_configured_pack_host_v1(config_json)
  match (descriptor.action_kind(), config.operation) {
    (@orchestration.OperatorActionCommandV1, ConfiguredOperatorV1) => {
      if config.run_id != Some(run_id) {
        fail("operator action host config run_id mismatch")
      }
      ignore(
        @orchestration.decode_operator_mutation_handoff_json_v1(
          @fs.read_file(handoff_path).binary(),
        ),
      )
    }
    (@orchestration.OperatorActionScheduleRegistrationV1, ConfiguredScheduleV1) => {
      let envelope = @orchestration.decode_pack_handoff_json_bytes_v1(
        @fs.read_file(handoff_path).binary(),
      )
      ignore(envelope.scheduled_action())
    }
    (
      @orchestration.OperatorActionFinalLearningPersistV1,
      ConfiguredFinalLearningV1,
    ) => {
      let envelope = @orchestration.decode_pack_handoff_json_bytes_v1(
        @fs.read_file(handoff_path).binary(),
      )
      require_final_learning_handoff_kind_v1(envelope.kind())
    }
    _ => fail("operator action kind does not match host configuration")
  }
}

///|
pub async fn materialize_operator_actions_v1(
  run_root : String,
  run_id : String,
  materialization : @orchestration.OperatorActionCatalogMaterializationV1,
) -> OperatorActionMaterializationReceiptV1 {
  require_run_root_v1(run_root)
  require_run_id_v1(run_id)
  if materialization.run_id() != run_id ||
    @contracts.sha256_digest(materialization.bytes()) !=
    materialization.digest() {
    fail("operator action catalog run or digest mismatch")
  }
  let canonical_root = @fs.realpath(run_root)
  if canonical_root != run_root {
    fail("operator run root must already be canonical")
  }
  let run_path = if run_root == "/" {
    "/\{run_id}"
  } else {
    "\{run_root}/\{run_id}"
  }
  if !@fs.exists(run_path) {
    fail("operator run must exist before actions are materialized")
  }
  let canonical_run = @fs.realpath(run_path)
  if canonical_run != run_path ||
    (run_root != "/" && !canonical_run.has_prefix(run_root + "/")) {
    fail("operator run path escapes the supplied root")
  }
  require_operator_projection_binding_v1(
    canonical_run,
    run_id,
    materialization.operator_projection_digest(),
  )
  for descriptor in materialization.actions() {
    validate_operator_action_server_inputs_v1(canonical_run, run_id, descriptor)
  }
  let target = "\{canonical_run}/operator-actions.json"
  let temporary = "\{canonical_run}/.operator-actions.\{materialization.digest().hex()}.tmp"
  @fs.write_file(
    temporary,
    materialization.bytes(),
    create=0o600,
    truncate=true,
  )
  operator_materialization_atomic_replace_v1(temporary, target)
  let json : Json = {
    "contract_id": "moonflow.operator-actions-materialization-receipt.v1",
    "contract_version": "1.0.0",
    "run_id": run_id,
    "operator_projection_digest": materialization
    .operator_projection_digest()
    .text(),
    "catalog_digest": materialization.digest().text(),
    "action_count": materialization.actions().length().to_string(),
  }
  let canonical_json = json.stringify()
  {
    run_id,
    operator_projection_digest: materialization.operator_projection_digest(),
    catalog_digest: materialization.digest(),
    action_count: materialization.actions().length(),
    canonical_json,
    digest: @contracts.sha256_digest(@utf8.encode(canonical_json)),
  }
}

///|
pub fn OperatorActionMaterializationReceiptV1::to_json(
  self : OperatorActionMaterializationReceiptV1,
) -> Json {
  {
    "contract_id": "moonflow.operator-actions-materialization-receipt.v1",
    "contract_version": "1.0.0",
    "run_id": self.run_id,
    "operator_projection_digest": self.operator_projection_digest.text(),
    "catalog_digest": self.catalog_digest.text(),
    "action_count": self.action_count.to_string(),
    "receipt_digest": self.digest.text(),
  }
}
