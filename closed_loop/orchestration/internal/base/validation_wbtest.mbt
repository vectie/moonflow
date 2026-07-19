///|
test "canonical text rejects empty, padded, and whitespace-only input" {
  inspect(is_canonical_text("orchestration"), content="true")
  inspect(is_canonical_text(""), content="false")
  inspect(is_canonical_text(" orchestration"), content="false")
  inspect(is_canonical_text("orchestration "), content="false")
  inspect(is_canonical_text(" \n\t"), content="false")
}

///|
test "non-negative addition distinguishes negative and overflow" {
  assert_true(checked_add_non_negative(40L, 2L) == Value(42L))
  assert_true(checked_add_non_negative(-1L, 2L) == Negative)
  assert_true(checked_add_non_negative(9223372036854775807L, 1L) == Overflow)
}

///|
test "non-negative multiplication distinguishes negative and overflow" {
  assert_true(checked_multiply_non_negative(6L, 7L) == Value(42L))
  assert_true(checked_multiply_non_negative(6L, -7L) == Negative)
  assert_true(
    checked_multiply_non_negative(9223372036854775807L, 2L) == Overflow,
  )
  assert_true(
    checked_multiply_non_negative(0L, 9223372036854775807L) == Value(0L),
  )
}
