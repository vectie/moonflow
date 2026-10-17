///|
async fn single_step_owner_capability(
  root : String,
  config : SingleStepConfig,
  item : @moonflow.RuntimeItem,
  at : String,
) -> @moonflow.CapabilityOperationV1 {
  let value = plan_read_json(root, config.capability_ref)
  let catalog = @moonflow.decode_capability_catalog_v1(value)
  guard catalog.conformant else {
    fail("single-step capability catalog is not conformant")
  }
  let matches = catalog.operations.filter(operation => {
    operation.operation_ref == item.operation &&
    operation.product_id == item.product_id
  })
  guard matches is [operation] &&
    operation.review_required &&
    operation.authority == "workspace-mutation" &&
    operation.claim_ceiling == "digital-artifact" &&
    operation.authority == item.requested_authority &&
    operation.claim_ceiling == item.required_claim &&
    item.input_contracts == [operation.input_schema_ref] &&
    item.output_contracts == [operation.output_schema_ref] else {
    fail(
      "selected capability does not bind the exact item and explicit review boundary",
    )
  }
  let selected = @moonflow.select_adapter(
    @moonflow.decode_adapter_capabilities_at_v1(value, at),
    @moonflow.director_requirement_for_item(item),
  )
  guard selected.accepted &&
    selected.selected_adapter_id == operation.adapter_id else {
    fail("selected adapter is unavailable, unhealthy or stale")
  }
  let bytes = plan_read_bytes(root, operation.health_evidence_ref)
  guard "sha256:" + sha256_hex(bytes) == operation.health_evidence_digest else {
    fail("adapter health evidence digest differs")
  }
  operation
}

///|
async fn single_step_write_path(root : String, reference : String) -> Unit {
  guard reference.length() <= 4096 &&
    @moonflow.artifact_ref_is_workspace_relative(reference) &&
    !reference.split("/").any(part => part == "" || part == "." || part == "..") else {
    fail("verifier declared a noncanonical workspace path")
  }
  let mut cursor = root
  for part in reference.split("/") {
    cursor += "/" + part.to_owned()
    if @fs.exists(cursor) && @fs.realpath(cursor) != cursor {
      fail("verifier output path is symlinked")
    }
  }
}

///|
async fn single_step_verification_payload(
  root : String,
  operation : @moonflow.CapabilityOperationV1,
  request : @moonflow.AdapterRequest,
  phase : String,
  reconcile? : Bool = false,
) -> Json {
  guard request.input_artifacts.get(0) is Some(reference) else {
    fail("selected primary input is required")
  }
  let health = plan_read_bytes(root, operation.health_evidence_ref)
  guard "sha256:" + sha256_hex(health) == operation.health_evidence_digest else {
    fail("adapter health evidence changed")
  }
  let primary = plan_read_bytes(root, reference)
  {
    "contract_id": "moonflow.single-step-verification-request.v1",
    "phase": phase,
    "reconcile": reconcile,
    "adapter_request": request.to_json(),
    "primary_input_ref": reference,
    "primary_input_sha256": "sha256:" + sha256_hex(primary),
    "health_evidence_ref": operation.health_evidence_ref,
    "health_evidence_sha256": operation.health_evidence_digest,
    "checked_at": operation.health_checked_at,
    "valid_until": operation.health_valid_until,
  }
}

///|
async fn single_step_verify(
  root : String,
  config : SingleStepConfig,
  operation : @moonflow.CapabilityOperationV1,
  request : @moonflow.AdapterRequest,
  exchange : Json,
  action_ref : String,
  name : String,
) -> Json {
  let bytes = @utf8.encode(exchange.stringify(indent=2))
  guard bytes.length() <= 256 * 1024 else {
    fail("owner verification control exchange exceeded 256 KiB")
  }
  let directory = plan_directory(root, action_ref)
  @flow_host.atomic_replace_named_bytes_v1(directory, name, bytes)
  single_step_executable(config.adapter_executable, config.adapter_sha256)
  let output = single_step_process(
    config.adapter_executable,
    ["verify-single-step", root, directory + "/" + name],
    root,
    30000,
  )
  guard output.status == 0 else {
    fail(
      "pinned owner verifier refused the selected evidence: " +
      output.stderr +
      output.stdout,
    )
  }
  let proof = @json.parse(output.stdout)
  guard @utf8.encode(output.stdout).length() <= 128 * 1024 else {
    fail("owner verification policy exceeded 128 KiB")
  }
  guard plan_string(proof, "contract_id") ==
    "moonflow.single-step-verification.v1" &&
    plan_value(proof, "accepted") == true.to_json() &&
    plan_string(proof, "phase") == plan_string(exchange, "phase") &&
    plan_string(proof, "exchange_sha256") == "sha256:" + sha256_hex(bytes) &&
    plan_string(proof, "request_id") == request.request_id &&
    plan_string(proof, "attempt_id") == request.attempt_id &&
    plan_string(proof, "input_digest") == request.input_digest &&
    plan_string(proof, "product_id") == request.product_id &&
    plan_string(proof, "operation") == request.operation &&
    plan_string(proof, "requested_authority") == request.requested_authority &&
    plan_string(proof, "required_claim") == request.required_claim &&
    plan_string(proof, "adapter_id") == operation.adapter_id &&
    plan_string(proof, "pack_version") == operation.pack_version else {
    fail(
      "owner verification does not bind this exact exchange and selected capability",
    )
  }
  let expected : Array[String] = @json.from_json(
    plan_value(proof, "expected_artifacts"),
  )
  let paths : Array[String] = @json.from_json(
    plan_value(proof, "artifact_paths"),
  )
  guard expected.length() <= 64 && !paths.is_empty() && paths.length() <= 64 else {
    fail("owner verifier path budget differs")
  }
  let receipt = plan_string(proof, "receipt_ref")
  for reference in paths {
    single_step_write_path(root, reference)
  }
  for reference in [receipt, ..expected] {
    single_step_write_path(root, reference)
    guard paths.any(path => {
      reference == path || reference.has_prefix(path + "/")
    }) else {
      fail("owner receipt or output is outside its declared Gate write paths")
    }
  }
  ignore(plan_value(proof, "qualification"))
  proof
}
