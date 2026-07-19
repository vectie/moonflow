///|
/// Construction failures are values so callers can reject proposals without side effects.
pub enum AuthorizationError {
  Blank(String)
  Negative(String)
  IncompleteOption(String)
  DuplicateEvidence(String)
  TupleMismatch(String)
  OutsideGovernanceWindow
  OutsideDispatchWindow
  InvalidInterval(String)
  CausalMismatch(String)
  CanonicalCodecError(String)
  ContentReferenceMismatch(String)
  ReplayConflict(String)
  PreviousDigestMismatch(String)
  ProducerMismatch(String)
  ControlMismatch(String)
  EligibilityMismatch(String)
  GovernanceMismatch(String)
  ProofMismatch(String)
  DispatchIneligible(String)
} derive(Eq, Debug)

///|
fn nonblank(value : String, field : String) -> Result[Unit, AuthorizationError] {
  if value.trim().is_empty() {
    Err(Blank(field))
  } else {
    Ok(())
  }
}

///|
fn nonnegative(
  value : Int64,
  field : String,
) -> Result[Unit, AuthorizationError] {
  if value < 0L {
    Err(Negative(field))
  } else {
    Ok(())
  }
}
