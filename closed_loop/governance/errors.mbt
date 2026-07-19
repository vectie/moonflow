///|
/// Typed fail-closed validation errors for the governance state machine.
pub(all) suberror GovernanceError {
  InvalidState(field~ : String)
  IdentityMismatch(field~ : String)
  OrderingMismatch(field~ : String)
  RevisionMismatch(field~ : String, expected~ : Int64, actual~ : Int64)
  ExpiryViolation(field~ : String)
  DigestMismatch(field~ : String)
  EvidenceViolation(field~ : String)
  CriteriaViolation(field~ : String)
  IdempotencyConflict(key~ : String)
  ReceiptBindingFailure(field~ : String)
  UnsupportedVersion(field~ : String, version~ : String)
  InvalidEventKind(String)
  CausationMismatch(field~ : String)
  MalformedPayload(field~ : String)
} derive(Eq, Debug)

///|
fn require_text(value : String, field : String) -> Unit raise GovernanceError {
  if value.trim().is_empty() {
    raise MalformedPayload(field~)
  }
}

///|
fn require_revision(
  value : Int64,
  field : String,
) -> Unit raise GovernanceError {
  if value < 0L {
    raise RevisionMismatch(field~, expected=0L, actual=value)
  }
}

///|
fn require_exact_record(
  actual : @contracts.RecordRef,
  expected : @contracts.RecordRef,
  field : String,
) -> Unit raise GovernanceError {
  if actual != expected {
    raise IdentityMismatch(field~)
  }
}

///|
fn require_digest(
  actual : @contracts.ContentDigest,
  expected : @contracts.ContentDigest,
  field : String,
) -> Unit raise GovernanceError {
  if actual != expected {
    raise DigestMismatch(field~)
  }
}
