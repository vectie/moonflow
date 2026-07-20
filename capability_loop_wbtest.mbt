///|
fn capability_loop_test_ref(
  id : String,
  version : String,
) -> CapabilityRecordRefV1 {
  {
    record_id: id,
    record_version: version,
    record_digest: "sha256:\{id}:\{version}",
  }
}

///|
test "capability loop resolves canary, records exact outcomes, and settles" {
  let request : CapabilityActivationRequestV1 = {
    contract_version: "moonbook.bookkeeper.capability_activation_request.v1",
    request: capability_loop_test_ref("request", "1"),
    receipt: capability_loop_test_ref("receipt", "1"),
    scope_id: "wiki-maintainer",
    rollout_mode: "canary",
    challenger_participant_ids: ["challenger-session"],
    max_observations: 4,
    experiment: capability_loop_test_ref("experiment", "1"),
    old_capability: capability_loop_test_ref("capability", "4"),
    new_capability: capability_loop_test_ref("capability", "5"),
    rollback: capability_loop_test_ref("rollback", "1"),
    activation_review: capability_loop_test_ref("activation-review", "1"),
    activation_reviewer_id: "human-1",
    activation_reviewer_authority_ref: "authority:human-1",
    requested_at: 100L,
    adoption_authorized: true,
    source_side_effects_applied: false,
    activation_side_effects_applied: false,
  }
  let projection = activate_capability_v1(
    request,
    activation_id="activation-1",
    activated_at=101L,
  )
  let baseline = resolve_capability_v1(
    projection,
    scope_id="wiki-maintainer",
    participant_id="baseline-session",
  )
  let challenger = resolve_capability_v1(
    projection,
    scope_id="wiki-maintainer",
    participant_id="challenger-session",
  )
  assert_eq(baseline.assignment, "baseline")
  assert_eq(baseline.selected_capability.record_version, "4")
  assert_eq(challenger.assignment, "challenger")
  assert_eq(challenger.selected_capability.record_version, "5")
  let observed = projection.record_observation({
    observation_id: "observation-1",
    scope_id: "wiki-maintainer",
    participant_id: "challenger-session",
    assignment: "challenger",
    capability: request.new_capability,
    outcome: capability_loop_test_ref("outcome", "1"),
    reward_evidence: capability_loop_test_ref("reward", "1"),
    accepted: true,
    recorded_at: 110L,
  })
  assert_eq(observed.observations.length(), 1)
  let promoted = observed.settle({
    contract_version: capability_loop_contract_version(),
    settlement_id: "settlement-1",
    scope_id: "wiki-maintainer",
    decision: "promote",
    experiment_outcome: capability_loop_test_ref("experiment-outcome", "1"),
    reviewer_id: "human-2",
    reviewer_authority_ref: "authority:human-2",
    review_evidence: capability_loop_test_ref("settlement-review", "1"),
    settled_at: 120L,
  })
  assert_eq(promoted.status, "promoted")
  assert_eq(
    resolve_capability_v1(
      promoted,
      scope_id="wiki-maintainer",
      participant_id="baseline-session",
    ).selected_capability.record_version,
    "5",
  )
}
