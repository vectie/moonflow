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
