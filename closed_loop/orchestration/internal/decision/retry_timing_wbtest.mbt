///|
test "retry backoff computes and clamps the nominal delay" {
  assert_true(retry_nominal_delay(10L, 100L, 2L, 1L, 2L) == NominalDelay(40L))
  assert_true(retry_nominal_delay(10L, 25L, 2L, 1L, 2L) == NominalDelay(25L))
  assert_true(retry_nominal_delay(-1L, 25L, 2L, 1L, 2L) == InvalidInput)
  assert_true(
    retry_nominal_delay(9223372036854775807L, 9223372036854775807L, 2L, 1L, 1L) ==
    NumeratorOverflow,
  )
}

///|
test "retry jitter folding is stable and rejects invalid modulus" {
  assert_true(hash_mod(b"retry", 11L) == Some(0L))
  assert_true(hash_mod(b"", 17L) == Some(0L))
  assert_true(hash_mod(b"retry", 0L) is None)
}

///|
test "retry authorization uses inclusive deadline" {
  assert_true(is_authorized_at(10L, 10L, Some(10L)))
  assert_false(is_authorized_at(9L, 10L, None))
  assert_false(is_authorized_at(11L, 10L, Some(10L)))
}
