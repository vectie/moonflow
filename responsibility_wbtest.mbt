///|
test "all import and adapter paths share one authority vocabulary" {
  assert_eq(canonical_authority_classes().length(), 6)
  for authority in canonical_authority_classes() {
    assert_true(authority_class_is_canonical(authority))
  }
  assert_false(authority_class_is_canonical("unbounded"))
  assert_false(authority_class_is_canonical("PhysicalEffect"))
}

///|
test "projection outcome is a pure deterministic precedence decision" {
  assert_eq(projection_outcome_for_statuses([]), "proposed")
  assert_eq(projection_outcome_for_statuses([Accepted]), "accepted")
  assert_eq(projection_outcome_for_statuses([Failed, Active]), "active")
  assert_eq(projection_outcome_for_statuses([Failed, Blocked]), "blocked")
  assert_eq(projection_outcome_for_statuses([Waiting, Ready]), "ready")
  assert_eq(projection_outcome_for_statuses([Waiting]), "waiting")
}
