///|
fn digest(char : String) -> String {
  "sha256:\{char.repeat(64)}"
}

///|
fn dispatch(
  parent? : String = digest("a"),
  source? : String = digest("b"),
  input? : String = digest("c"),
  child_representation? : String = "engineering-model",
  parent_representation? : String = "editable-authoring-model",
  lineage? : String = "modeled-from",
  authority? : String = "workspace-mutation",
  claim? : String = "digital-artifact",
) -> MoonMoldDispatch {
  {
    request: {
      request_id: "moonmold-request-1",
      run_id: "run-building-r1",
      book_id: "book-building",
      work_item_id: "model-building",
      declaration_id: "declaration-model-building",
      attempt_id: "attempt-model-building-1",
      idempotency_key: "moonmold-building-r1",
      product_id: "moonmold",
      operation: "live-building",
      requested_authority: authority,
      acceptance_criteria: ["portable lineage accepted"],
      input_contracts: ["moonmold-building-plan-v1"],
      output_contracts: [
        "moonmold.spatial-artifact.v1", "moonmold.representation-transform.v1",
      ],
      required_claim: claim,
      input_digest: input,
      input_artifacts: ["books/building/spatial-intent.json"],
      timeout_ms: 120000,
      created_at: "2026-07-13T00:00:00Z",
    },
    declaration_revision: "r1",
    source_digest: source,
    expected_parent_digest: parent,
    expected_parent_representation: parent_representation,
    expected_child_representation: child_representation,
    expected_lineage_relation: lineage,
    authority_envelope_id: "authority-moonmold-building-r1",
  }
}

///|
fn result(
  parent? : String = digest("a"),
  representation? : String = "engineering-model",
  parent_representation? : String = "editable-authoring-model",
  lineage? : String = "modeled-from",
  claim? : String = "digital-artifact",
  physical? : Bool = false,
) -> MoonMoldResult {
  {
    request_id: "moonmold-request-1",
    attempt_id: "attempt-model-building-1",
    idempotency_key: "moonmold-building-r1",
    status: "succeeded",
    artifact_id: "building:engineering-model",
    artifact_digest: digest("d"),
    parent_digest: parent,
    parent_representation,
    representation,
    lineage_relation: lineage,
    claim_ceiling: claim,
    authority_envelope_id: "authority-moonmold-building-r1",
    portable_artifact_ref: "books/building/evidence/engineering.portable.json",
    evidence_refs: ["books/building/evidence/live-blender.json"],
    physical_effects: physical,
  }
}

///|
test "MoonFlow capability and accepted evidence stay within digital authority" {
  let capability = moonmold_capability()
  assert_true(capability.quality_issues().is_empty())
  assert_eq(capability.claim_ceiling, "digital-artifact")
  assert_false(capability.authority_classes.contains("physical-effect"))
  let mapping = attest_moonmold_result(dispatch(), result())
  assert_true(mapping.accepted)
  assert_true(mapping.issues.is_empty())
  assert_eq(mapping.representation, "engineering-model")
}

///|
test "MoonFlow rejects stale lineage mismatch and physical overclaim" {
  let stale = attest_moonmold_result(dispatch(), result(parent=digest("e")))
  assert_false(stale.accepted)
  assert_true(
    stale.issues.contains(
      "MoonMold result has a stale or unexpected parent digest",
    ),
  )
  let styled_as_engineering = attest_moonmold_result(
    dispatch(),
    result(
      representation="visual-styled-model",
      lineage="styled-from",
      parent_representation="engineering-model",
    ),
  )
  assert_false(styled_as_engineering.accepted)
  assert_true(
    styled_as_engineering.issues.contains(
      "MoonMold result representation lineage mismatches dispatch",
    ),
  )
  let physical = attest_moonmold_result(
    dispatch(),
    result(claim="physical-readiness", physical=true),
  )
  assert_false(physical.accepted)
  assert_true(
    physical.issues.contains(
      "MoonMold cannot emit simulation evidence or physical claims",
    ),
  )
  assert_true(
    physical.issues.contains("MoonMold result cannot report physical effects"),
  )
}

///|
test "MoonFlow invalidates changed revision inputs and reuses exact evidence" {
  let parent = attest_moonmold_result(dispatch(), result())
  let exact_child = { ..dispatch(), declaration_revision: "r2" }
  let reused = moonmold_checkpoint_decision(parent, exact_child)
  assert_eq(reused.decision, "reused")
  let changed_input = dispatch(input=digest("f"))
  let invalidated = moonmold_checkpoint_decision(parent, changed_input)
  assert_eq(invalidated.decision, "invalidated")
  assert_eq(invalidated.reason, "spatial input digest changed")
  assert_true(invalidated.invalidated_artifact_refs.length() == 2)
  let changed_parent = dispatch(parent=digest("9"))
  assert_eq(
    moonmold_checkpoint_decision(parent, changed_parent).reason,
    "accepted parent geometry changed",
  )
}

///|
test "MoonFlow rejects premature simulation-evidence claim" {
  let simulation_dispatch = dispatch(
    child_representation="simulation-model",
    parent_representation="engineering-model",
    lineage="physics-derived-from",
  )
  let overclaim = result(
    representation="simulation-model",
    parent_representation="engineering-model",
    lineage="physics-derived-from",
    claim="simulation-evidence",
  )
  let mapping = attest_moonmold_result(simulation_dispatch, overclaim)
  assert_false(mapping.accepted)
  assert_true(
    mapping.issues.contains(
      "MoonMold cannot emit simulation evidence or physical claims",
    ),
  )
}
