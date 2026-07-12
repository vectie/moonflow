///|
fn review_projection() -> @moonflow.RunProjection {
  {
    run_id: "flow-generic-r1",
    book_id: "generic-book",
    declaration_revision: "r1",
    source_digest: "sha256:source",
    last_sequence: 5,
    items: [
      {
        work_item_id: "work-research",
        declaration_id: "research",
        product_id: "moonwiki",
        requested_authority: "observe",
        acceptance_criteria: ["source provenance is complete"],
        operation: "build-evidence-bundle",
        input_contracts: ["test.input.v1"],
        output_contracts: ["test.output.v1"],
        required_claim: "research-evidence",
        input_artifacts: ["evidence/input.json"],
        timeout_ms: 1000,
        depends_on: [],
        status: Review,
        attempt_count: 1,
        request_id: "request-research",
        result_id: "result-research",
        active_attempt_id: "attempt-research",
        idempotency_key: "idem-research",
        external_job_id: "job-research",
        attempt_status: "succeeded",
        input_digest: "sha256:input",
        output_digest: "sha256:output",
        error_kind: "",
        compensable: false,
        blocker: "",
        acceptance_review_id: "",
        acceptance_review_artifact: "",
        acceptance_reviewer_id: "",
        artifacts: ["books/generic-book/outputs/evidence.json"],
        approvals: [],
      },
    ],
    applied_event_ids: [],
    applied_events: [],
    outcome: "review",
  }
}

///|
fn accepted_review() -> @moonflow.AcceptanceReviewReceipt {
  {
    contract_id: "moonflow.acceptance-review.v1",
    review_id: "review-research-r1",
    run_id: "flow-generic-r1",
    work_item_id: "work-research",
    declaration_id: "research",
    result_id: "result-research",
    attempt_id: "attempt-research",
    output_digest: "sha256:output",
    decision: "accepted",
    criteria: [
      {
        criterion: "source provenance is complete",
        satisfied: true,
        evidence_refs: ["books/generic-book/outputs/evidence.json"],
        note: "The attached bundle contains source and review records.",
      },
    ],
    reviewer_id: "reviewer-1",
    review_authority_id: "book-owner-review",
    receipt_artifact: "books/generic-book/reviews/research-r1.json",
    recorded_at: "2026-07-11T12:00:00Z",
  }
}

///|
test "typed acceptance review binds every criterion and result identity" {
  let projection = review_projection()
  let event = @moonflow.acceptance_review_event(projection, accepted_review())
  projection.apply(event)
  let item = projection.items[0]
  assert_true(item.status == Accepted)
  assert_eq(item.acceptance_review_id, "review-research-r1")
  assert_eq(
    item.acceptance_review_artifact,
    "books/generic-book/reviews/research-r1.json",
  )
  assert_eq(item.acceptance_reviewer_id, "book-owner-review")
  assert_true(item.artifacts.contains(item.acceptance_review_artifact))
}

///|
test "acceptance review fails closed on changed criterion text" {
  let base = accepted_review()
  let receipt = {
    ..base,
    criteria: [{ ..base.criteria[0], criterion: "weaker criterion" }],
  }
  try @moonflow.acceptance_review_event(review_projection(), receipt) catch {
    InvalidAcceptanceReview(issues) =>
      assert_true(issues.any(issue => issue.contains("exactly match")))
    _ => fail("unexpected acceptance review error")
  } noraise {
    _ => fail("expected criterion mismatch")
  }
}

///|
test "rejected review returns Work to a visible blocker" {
  let base = accepted_review()
  let receipt = {
    ..base,
    decision: "rejected",
    criteria: [
      {
        ..base.criteria[0],
        satisfied: false,
        evidence_refs: [],
        note: "The source timestamp is absent.",
      },
    ],
  }
  let projection = review_projection()
  projection.apply(@moonflow.acceptance_review_event(projection, receipt))
  assert_true(projection.items[0].status == Blocked)
  assert_eq(projection.items[0].error_kind, "acceptance-rejected")
  assert_true(
    projection.items[0].blocker.contains("source timestamp is absent"),
  )
  assert_eq(projection.items[0].acceptance_review_id, "review-research-r1")
}
