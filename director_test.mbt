///|
fn director_capability(
  adapter_id : String,
  healthy? : Bool = true,
  authority? : String = "sandbox-execution",
  ceiling? : String = "scenario-qualified",
) -> AdapterCapability {
  {
    adapter_id,
    product_id: "moonmoon",
    protocol: "moonflow.adapter.v1",
    operations: ["simulate-mission"],
    authority_classes: [authority],
    input_contracts: ["moonsuite.robot-design.v1"],
    output_contracts: ["moonsuite.evidence-envelope.v1"],
    claim_ceiling: ceiling,
    healthy,
    supports_cancel: true,
    supports_reconcile: true,
  }
}

///|
fn director_requirement() -> DirectorRequirement {
  {
    requirement_id: "requirement-simulate",
    product_id: "moonmoon",
    operation: "simulate-mission",
    requested_authority: "sandbox-execution",
    input_contracts: ["moonsuite.robot-design.v1"],
    output_contracts: ["moonsuite.evidence-envelope.v1"],
    required_claim: "scenario-qualified",
  }
}

///|
test "director selects only a healthy contract and claim compatible adapter" {
  let decision = select_adapter(
    [
      director_capability("unhealthy", healthy=false),
      director_capability("low-claim", ceiling="simulation-evidence"),
      director_capability("qualified"),
    ],
    director_requirement(),
  )
  assert_true(decision.accepted)
  assert_eq(decision.selected_adapter_id, "qualified")
  assert_true(decision.reviews[0].reasons.contains("adapter unhealthy"))
  assert_true(
    decision.reviews[1].reasons.contains(
      "required claim exceeds adapter ceiling",
    ),
  )
}

///|
test "director fails closed when authority is incompatible" {
  let decision = select_adapter(
    [director_capability("observe-only", authority="observe")],
    director_requirement(),
  )
  assert_false(decision.accepted)
  assert_eq(decision.selected_adapter_id, "")
  assert_true(decision.reviews[0].reasons.contains("authority unsupported"))
}

///|
test "unknown outcome reconciles before retry and every retry preserves evidence" {
  let unknown = director_retry_decision(UnknownOutcome)
  assert_true(unknown.requires_reconciliation)
  assert_eq(unknown.action, "reconcile-before-any-retry")
  let failures : Array[DirectorFailureClass] = [
    TransientFailure,
    QualityRejection,
    AuthorityDenial,
    PermanentIncompatibility,
    UnknownOutcome,
  ]
  for failure in failures {
    let decision = director_retry_decision(failure)
    assert_true(decision.preserves_attempt_evidence)
    assert_true(decision.reuses_idempotency_lineage)
  }
}

///|
test "director derives a stable request from declared execution binding" {
  let projection = @moonflow.replay(
    "flow-r1",
    @moonflow.events_from_work_graph({
      "contract_id": "moonsuite.work-model.v1",
      "graph_id": "flow-r1",
      "book_id": "robot",
      "declaration_revision": "r1",
      "source_digest": "sha256:source",
      "items": [
        {
          "work_item_id": "work-research",
          "declaration_id": "research",
          "product_id": "moonwiki",
          "requested_authority": "observe",
          "acceptance_criteria": ["evidence reviewed"],
          "operation": "query-evidence",
          "input_contracts": ["question.v1"],
          "output_contracts": ["evidence.v1"],
          "required_claim": "research-evidence",
          "input_artifacts": ["books/robot/inputs/question.json"],
          "timeout_ms": 60000,
          "depends_on": [],
        },
      ],
      "recorded_at": "2026-07-12T00:00:00Z",
    }),
  )
  guard projection.find_item("work-research") is Some(item) else {
    fail("expected item")
  }
  let requirement = director_requirement_for_item(item)
  assert_eq(requirement.operation, "query-evidence")
  let request = director_request_for_item(
    projection, item, "sha256:input", "2026-07-12T00:01:00Z",
  )
  assert_eq(request.attempt_id, "attempt-work-research-1")
  assert_true(
    request.input_artifacts == ["books/robot/inputs/question.json"],
  )
  assert_true(request.idempotency_key.contains("sha256:input"))
  let submitted = @moonflow.adapter_submission_event(projection, request)
  let active = @moonflow.replay(
    "flow-r1",
    projection.applied_events + [submitted],
  )
  guard active.find_item("work-research") is Some(active_item) else {
    fail("expected active item")
  }
  let result = director_success_result_for_item(
    active_item,
    "sha256:output",
    ["evidence/output.json"],
    "2026-07-12T00:02:00Z",
  )
  assert_eq(result.request_id, request.request_id)
  assert_eq(result.output_digest, "sha256:output")
}
