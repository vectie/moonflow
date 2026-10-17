///|
/// Validate the generic adapter protocol and exact host-hashed receipt identity.
/// Pack-owned semantics are verified through the pinned native verifier before
/// this result may become a durable reconciliation event.
pub fn single_step_validate_result(
  request : AdapterRequest,
  result : AdapterResult,
  receipt_ref : String,
  receipt_digest : String,
  expected_artifacts : Array[String],
) -> Unit raise {
  guard reconcile_adapter_result(request, result) == ImportSuccess else {
    fail(
      "selected adapter did not return a correlated successful terminal result",
    )
  }
  guard artifact_ref_is_workspace_relative(receipt_ref) &&
    result.output_digest == receipt_digest &&
    result.output_artifacts == [receipt_ref, ..expected_artifacts] else {
    fail("adapter output receipt digest or declared artifact identity differs")
  }
}
