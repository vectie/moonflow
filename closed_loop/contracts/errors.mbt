///|
/// Deterministic failures raised by the neutral contract package.
///
/// Error values contain field names, public identities, versions, and digests
/// only. They never contain opaque payload or extension bytes.
pub(all) suberror ContractError {
  InvalidReferenceField(reference~ : String, field~ : String)
  InvalidDigestSyntax(field~ : String)
  UnsupportedDigestAlgorithm(String)
  MalformedVersion(field~ : String)
  UnsupportedVersion(field~ : String, version~ : String)
  NoCommonVersion
  InvalidVersionProfile
  CanonicalizationError(String)
  UnsupportedCanonicalVersion(String)
  PayloadDigestMismatch(expected~ : String, actual~ : String)
  EnvelopeDigestMismatch(expected~ : String, actual~ : String)
  ConflictingReferenceIdentity(kind~ : String, id~ : String, version~ : String)
  ConflictingEnvelopeIdentity(String)
  DecodeError(String)
} derive(Eq, Debug)
