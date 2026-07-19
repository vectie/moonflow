///|
/// Closed failures for the domain-neutral retry-plan proposal contract.
pub(all) suberror RetryAuthorityError {
  Malformed(field~ : String)
  IdentityMismatch(field~ : String)
  DigestMismatch(field~ : String)
  BoundViolation(field~ : String)
} derive(Eq, Debug)
