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
  result_id? : String = "result-wiki-job-1-final",
  product_id? : String = "moonwiki",
  output_digest? : String = "sha256:output",
  error_kind? : String = "",
) -> AdapterResult {
  {
    result_id,
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
fn adapter_projection_events() -> Array[RuntimeEvent] raise {
  @moonflow.events_from_work_graph({
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-r1",
    "book_id": "adapter-book",
    "declaration_revision": "r1",
    "source_digest": "sha256:7c83693394b7d8dfd98d8a3c7217cbddfa44e4b7ba5ef88c513d6da403e32f9c",
    "items": [
      {
        "work_item_id": "work-research",
        "declaration_id": "research",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["reviewed evidence is attached"],
        "depends_on": [],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  })
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

///|
test "adapter attempt survives replay and reconciles exactly once" {
  let events = adapter_projection_events()
  let before = @moonflow.replay("flow-r1", events)
  let submitted = @moonflow.adapter_submission_event(before, adapter_request())
  events.push(submitted)
  let restarted = @moonflow.replay("flow-r1", events)
  guard restarted.find_item("work-research") is Some(active) else {
    fail("expected research item")
  }
  assert_true(active.status is Active)
  assert_eq(active.attempt_count, 1)
  assert_eq(active.active_attempt_id, "attempt-work-research-1")
  assert_eq(active.input_digest, "sha256:input")
  let repeated_submission = @moonflow.adapter_submission_event(
    restarted,
    adapter_request(),
  )
  assert_true(repeated_submission == submitted)
  let reconciled = @moonflow.adapter_reconciliation_event(
    restarted,
    adapter_result(Succeeded),
  )
  events.push(reconciled)
  let after = @moonflow.replay("flow-r1", events)
  guard after.find_item("work-research") is Some(review) else {
    fail("expected research item")
  }
  assert_true(review.status is Review)
  assert_eq(review.output_digest, "sha256:output")
  assert_eq(review.artifacts.length(), 1)
  let repeated_result = @moonflow.adapter_reconciliation_event(
    after,
    adapter_result(Succeeded),
  )
  assert_true(repeated_result == reconciled)
  after.apply(repeated_result)
  assert_eq(after.last_sequence, reconciled.sequence)
  assert_eq(review.artifacts.length(), 1)
}

///|
test "same adapter result identity with changed content fails closed" {
  let events = adapter_projection_events()
  let before = @moonflow.replay("flow-r1", events)
  events.push(@moonflow.adapter_submission_event(before, adapter_request()))
  let active = @moonflow.replay("flow-r1", events)
  events.push(
    @moonflow.adapter_reconciliation_event(active, adapter_result(Succeeded)),
  )
  let completed = @moonflow.replay("flow-r1", events)
  try
    @moonflow.adapter_reconciliation_event(
      completed,
      adapter_result(Succeeded, output_digest="sha256:changed"),
    )
  catch {
    AdapterReceiptConflict(result_id) =>
      assert_eq(result_id, "result-wiki-job-1-final")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected conflicting result receipt")
  }
}

///|
test "unknown adapter outcome blocks until later reconciliation" {
  let events = adapter_projection_events()
  let before = @moonflow.replay("flow-r1", events)
  events.push(@moonflow.adapter_submission_event(before, adapter_request()))
  let active = @moonflow.replay("flow-r1", events)
  events.push(
    @moonflow.adapter_reconciliation_event(
      active,
      adapter_result(
        Unknown,
        result_id="result-wiki-job-1-unknown",
        output_digest="",
      ),
    ),
  )
  let blocked = @moonflow.replay("flow-r1", events)
  guard blocked.find_item("work-research") is Some(item) else {
    fail("expected research item")
  }
  assert_true(item.status is Blocked)
  assert_true(item.blocker.contains("reconciliation required"))
  events.push(
    @moonflow.adapter_reconciliation_event(
      blocked,
      adapter_result(Succeeded, result_id="result-wiki-job-1-final"),
    ),
  )
  let recovered = @moonflow.replay("flow-r1", events)
  guard recovered.find_item("work-research") is Some(review) else {
    fail("expected research item")
  }
  assert_true(review.status is Review)
  assert_eq(review.output_digest, "sha256:output")
}
