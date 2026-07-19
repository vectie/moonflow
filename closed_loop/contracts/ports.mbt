///|
/// Pure codec boundary for validated neutral envelopes.
pub(open) trait EnvelopeCodec {
  fn supported_versions(Self) -> VersionProfile
  fn encode_envelope(Self, WireEnvelope, Version) -> Bytes raise ContractError
  fn decode_envelope(Self, Bytes, Version) -> WireEnvelope raise ContractError
}

///|
/// Pure boundary mapping for reviewed receipt exchange. Implementations return
/// data only and expose no state-changing or application operation.
pub(open) trait ReceiptExchangePort {
  fn supported_versions(Self) -> VersionProfile
  fn encode_receipt(Self, WireEnvelope, Version) -> Bytes raise ContractError
  fn decode_receipt(Self, Bytes, Version) -> WireEnvelope raise ContractError
}

///|
/// Pure boundary mapping for request/result exchange. Implementations return
/// bytes or validated neutral envelopes only.
pub(open) trait WorkExchangePort {
  fn supported_versions(Self) -> VersionProfile
  fn encode_request(Self, WireEnvelope, Version) -> Bytes raise ContractError
  fn decode_request(Self, Bytes, Version) -> WireEnvelope raise ContractError
  fn encode_result(Self, WireEnvelope, Version) -> Bytes raise ContractError
  fn decode_result(Self, Bytes, Version) -> WireEnvelope raise ContractError
}
