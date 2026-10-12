///|
/// This route deliberately supports one exact digital product operation.
pub fn single_step_mold_item_supported(item : RuntimeItem) -> Bool {
  item.product_id == "moonmold" &&
  item.operation == "moonmold/spatial.operation.execute@0.2.0" &&
  item.requested_authority == "workspace-mutation" &&
  item.required_claim == "digital-artifact" &&
  item.input_contracts == ["moonmold/spatial-operation-request@1.0.0"] &&
  item.output_contracts == ["moonmold/spatial-operation-receipt@1.0.0"]
}

///|
/// Mold's durable attempt store is workspace-wide, so the attempt identity
/// includes the run. The ordinary director's per-item identity is unchanged.
pub fn single_step_request_for_item(
  projection : RunProjection,
  item : RuntimeItem,
  input_digest : String,
  recorded_at : String,
) -> AdapterRequest raise {
  guard single_step_mold_item_supported(item) && item.status == Ready else {
    fail("single-step requires one ready exact-version digital Mold item")
  }
  let request = director_request_for_item(
    projection, item, input_digest, recorded_at,
  )
  let tuple = "run:" +
    projection.run_id.length().to_string() +
    ":" +
    projection.run_id +
    "|item:" +
    item.work_item_id.length().to_string() +
    ":" +
    item.work_item_id +
    "|attempt:" +
    (item.attempt_count + 1).to_string()
  let identity = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(tuple)),
  )
  {
    ..request,
    request_id: "request-" + identity,
    attempt_id: "attempt-" + identity,
  }
}

///|
pub fn single_step_mold_receipt_ref(request : AdapterRequest) -> String {
  ".moonsuite/products/moonmold/adapter-attempts/" +
  request.attempt_id +
  "/operation-receipt.json"
}

///|
/// Verify the native Mold stdout protocol, not the unattended manifest's
/// aggregate-output protocol. Mold's output digest binds its receipt bytes.
pub fn single_step_validate_mold_result(
  request : AdapterRequest,
  result : AdapterResult,
  receipt : Json,
  receipt_digest : String,
  expected_artifacts : Array[String],
) -> Unit raise {
  guard reconcile_adapter_result(request, result) == ImportSuccess else {
    fail("Mold did not return a correlated successful terminal result")
  }
  guard result.output_digest == receipt_digest &&
    result.output_artifacts ==
    [single_step_mold_receipt_ref(request), ..expected_artifacts] else {
    fail("Mold output receipt digest or declared artifact identity differs")
  }
  let fields = wire_object(receipt, "Mold operation receipt")
  guard wire_string(fields, "contract_id") ==
    "moonmold.spatial-operation-receipt.v1" &&
    wire_string(fields, "operation_ref") ==
    "moonmold/spatial.operation.execute@0.2.0" &&
    wire_string(fields, "request_id") == request.request_id &&
    wire_string(fields, "attempt_id") == request.attempt_id &&
    wire_string(fields, "idempotency_key") == request.idempotency_key &&
    wire_string(fields, "outcome") is ("applied" | "idempotent-no-op") &&
    wire_string(fields, "claim_ceiling") == "digital-artifact" &&
    wire_bool(fields, "physical_authority") == false &&
    wire_bool(fields, "review_required") &&
    wire_strings(fields, "artifacts") == expected_artifacts else {
    fail(
      "Mold operation receipt correlation, outcome or claim boundary differs",
    )
  }
  guard fields.get("backend_qualification") is Some(Object(qualification)) &&
    qualification.get("evidence_class") ==
    Some(Json::string("fixture-reference-only")) &&
    qualification.get("production_qualified") == Some(false.to_json()) &&
    qualification.get("physical_authority") == Some(false.to_json()) &&
    qualification.get("blender_evidence") == Some(false.to_json()) else {
    fail("Mold native reference qualification must remain explicit")
  }
}
