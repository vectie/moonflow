///|
type ArtifactRef

///|
type ContentDigest

///|
suberror ContractError {
  FixtureFailure
}

///|
type EvidenceRef

///|
type OpaqueExtension

///|
type RecordRef

///|
enum ReplayDecision {
  FixtureDecision
}

///|
type SchemaRef

///|
type Version

///|
type VersionProfile

///|
type WireEnvelope

///|
trait EnvelopeCodec {}

///|
trait ReceiptExchangePort {}

///|
trait WorkExchangePort {}

///|
fn decide_envelope_replay() -> Unit {
  ()
}

///|
fn decode_wire_envelope() -> Unit {
  ()
}

///|
fn encode_wire_envelope() -> Unit {
  ()
}

///|
fn negotiate_highest() -> Unit {
  ()
}

///|
fn sha256_digest() -> Unit {
  ()
}

///|
fn sha256_hex() -> Unit {
  ()
}
