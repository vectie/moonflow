///|
fn adapter_request() -> AdapterRequest {
  {
    request_id: "request-flow-r1-research-a1",
    run_id: "flow-r1",
    work_item_id: "work-research",
    declaration_id: "research",
    attempt_id: "attempt-work-research-1",
    idempotency_key: "flow-r1/work-research/1/sha256:input",
    product_id: "moonwiki",
    operation: "research",
    requested_authority: "observe",
    input_digest: "sha256:input",
    input_artifacts: [],
    timeout_ms: 60000,
    created_at: "2026-07-11T00:00:00Z",
  }
}

///|
fn adapter_result(
  status : AdapterAttemptStatus,
  product_id? : String = "moonwiki",
  output_digest? : String = "sha256:output",
  error_kind? : String = "",
) -> AdapterResult {
  {
    request_id: "request-flow-r1-research-a1",
    attempt_id: "attempt-work-research-1",
    idempotency_key: "flow-r1/work-research/1/sha256:input",
    product_id,
    external_job_id: "wiki-job-1",
    status,
    output_digest,
    output_artifacts: ["artifact-research-bundle"],
    error_kind,
    compensable: true,
    recorded_at: "2026-07-11T00:00:10Z",
  }
}

///|
test "adapter success reconciles with exact identities" {
  let decision = @moonflow.reconcile_adapter_result(
    adapter_request(),
    adapter_result(Succeeded),
  )
  assert_true(decision is ImportSuccess)
}

///|
test "adapter mismatch fails closed" {
  try
    @moonflow.reconcile_adapter_result(
      adapter_request(),
      adapter_result(Succeeded, product_id="moonmoon"),
    )
  catch {
    AdapterIdentityMismatch(field~, expected~, actual~) => {
      assert_eq(field, "product_id")
      assert_eq(expected, "moonwiki")
      assert_eq(actual, "moonmoon")
    }
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected identity mismatch")
  }
}

///|
test "adapter success requires output digest" {
  try
    @moonflow.reconcile_adapter_result(
      adapter_request(),
      adapter_result(Succeeded, output_digest=""),
    )
  catch {
    InvalidAdapterResult(issues) =>
      assert_true(issues.contains("succeeded result requires output_digest"))
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected invalid result")
  }
}

///|
test "adapter failure remains an importable typed outcome" {
  let decision = @moonflow.reconcile_adapter_result(
    adapter_request(),
    adapter_result(Failed, output_digest="", error_kind="source-timeout"),
  )
  assert_true(decision is ImportFailure)
}

///|
test "production capability requires reconciliation" {
  let capability = AdapterCapability::{
    adapter_id: "moonwiki-v1",
    product_id: "moonwiki",
    protocol: "moonflow.adapter.v1",
    operations: ["research"],
    authority_classes: ["observe"],
    supports_cancel: true,
    supports_reconcile: false,
  }
  assert_true(
    capability
    .quality_issues()
    .contains("production adapters must support reconciliation"),
  )
}
