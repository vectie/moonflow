///|
/// Closed internal result translated by the public facade into its stable
/// `OrchestrationError` variants and field names.
pub(all) enum RetryBackoffResult {
  NominalDelay(Int64)
  InvalidInput
  NumeratorOverflow
  DenominatorOverflow
  OrdinalOverflow
} derive(Eq, Debug)

///|
/// Compute the exponential retry delay before deterministic jitter.
pub fn retry_nominal_delay(
  base_delay : Int64,
  maximum_delay : Int64,
  backoff_numerator : Int64,
  backoff_denominator : Int64,
  retry_ordinal : Int64,
) -> RetryBackoffResult {
  if base_delay < 0L ||
    maximum_delay < 0L ||
    backoff_numerator <= 0L ||
    backoff_denominator <= 0L ||
    retry_ordinal < 0L {
    return InvalidInput
  }
  let mut numerator = base_delay
  let mut denominator = 1L
  let mut ordinal = 0L
  while ordinal < retry_ordinal {
    match @base.checked_multiply_non_negative(numerator, backoff_numerator) {
      Value(value) => numerator = value
      Negative => return InvalidInput
      Overflow => return NumeratorOverflow
    }
    match
      @base.checked_multiply_non_negative(denominator, backoff_denominator) {
      Value(value) => denominator = value
      Negative => return InvalidInput
      Overflow => return DenominatorOverflow
    }
    match @base.checked_add_non_negative(ordinal, 1L) {
      Value(value) => ordinal = value
      Negative => return InvalidInput
      Overflow => return OrdinalOverflow
    }
  }
  let delay = numerator / denominator
  NominalDelay(Int64::min(delay, maximum_delay))
}

///|
fn modular_add(left : Int64, right : Int64, modulus : Int64) -> Int64 {
  if left >= modulus - right {
    left - (modulus - right)
  } else {
    left + right
  }
}

///|
/// Stable SHA-256 text folding used by V2 deterministic jitter.
pub fn hash_mod(bytes : Bytes, modulus : Int64) -> Int64? {
  if modulus <= 0L {
    return None
  }
  let mut value = 0L
  for byte in @utf8.encode(@contracts.sha256_digest(bytes).text()) {
    let mut factor = value
    let mut multiplier = 257
    let mut product = 0L
    while multiplier > 0 {
      if multiplier % 2 == 1 {
        product = modular_add(product, factor, modulus)
      }
      multiplier = multiplier / 2
      if multiplier > 0 {
        factor = modular_add(factor, factor, modulus)
      }
    }
    value = modular_add(product, byte.to_int().to_int64() % modulus, modulus)
  }
  Some(value)
}

///|
/// Decide whether a computed retry instant falls inside its recorded window.
pub fn is_authorized_at(
  due_at : Int64,
  not_before : Int64,
  deadline : Int64?,
) -> Bool {
  if due_at < not_before {
    return false
  }
  match deadline {
    Some(value) => due_at <= value
    None => true
  }
}
