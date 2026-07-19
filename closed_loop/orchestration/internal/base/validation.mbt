///|
/// The closed result used by facade adapters to preserve their own error type.
pub(all) enum NonNegativeArithmeticResult {
  Value(Int64)
  Negative
  Overflow
} derive(Eq, Debug)

///|
/// True when text has non-whitespace content and is already trim-canonical.
pub fn is_canonical_text(value : String) -> Bool {
  !value.trim().is_empty() && value == value.trim().to_owned()
}

///|
/// Add two non-negative integers without wrapping.
pub fn checked_add_non_negative(
  left : Int64,
  right : Int64,
) -> NonNegativeArithmeticResult {
  if left < 0L || right < 0L {
    return Negative
  }
  let maximum = 9223372036854775807L
  if right > maximum - left {
    return Overflow
  }
  Value(left + right)
}

///|
/// Multiply two non-negative integers without wrapping.
pub fn checked_multiply_non_negative(
  left : Int64,
  right : Int64,
) -> NonNegativeArithmeticResult {
  if left < 0L || right < 0L {
    return Negative
  }
  let maximum = 9223372036854775807L
  if left != 0L && right > maximum / left {
    return Overflow
  }
  Value(left * right)
}
