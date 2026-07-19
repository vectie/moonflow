///|
/// Typed storage failures contain only safe identities, versions, digests,
/// paths, and operating-system status codes. They never contain opaque bytes.
pub(all) suberror StorageError {
  ValidationFailure(field~ : String)
  UnsupportedVersion(record_kind~ : String, version~ : String)
  OptimisticRevisionConflict(
    workflow_id~ : String,
    expected~ : Int64,
    actual~ : Int64
  )
  IdentityConflict(kind~ : String, id~ : String, version~ : String)
  IdempotencyConflict(key~ : String)
  GuardedCommitRequired(
    workflow_id~ : String,
    key~ : String,
    binding_digest~ : String
  )
  GuardedBindingConflict(workflow_id~ : String, field~ : String)
  GuardedBindingFork(workflow_id~ : String)
  GuardedRegistryMissing(name~ : String)
  GuardedRegistryCorrupt(name~ : String)
  SequenceGap(workflow_id~ : String, expected~ : Int64, actual~ : Int64)
  RevisionGap(workflow_id~ : String, expected~ : Int64, actual~ : Int64)
  DigestMismatch(
    record_kind~ : String,
    record_id~ : String,
    expected~ : String,
    actual~ : String
  )
  CorruptCommittedData(name~ : String)
  UnsafePath(path~ : String)
  SymlinkRejected(path~ : String)
  IoFailure(operation~ : String, status~ : Int)
} derive(Eq, Debug)

///|
fn require_storage_text(
  value : String,
  field : String,
) -> Unit raise StorageError {
  if value.is_empty() ||
    value.trim().length() != value.length() ||
    value.iter().any(char => char.is_control()) {
    raise ValidationFailure(field~)
  }
}

///|
fn storage_version(
  value : String,
  record_kind : String,
) -> @contracts.Version raise StorageError {
  let parsed = @contracts.Version::parse(value) catch {
    _ => raise UnsupportedVersion(record_kind~, version=value)
  }
  if parsed.text() != "1.0.0" {
    raise UnsupportedVersion(record_kind~, version=value)
  }
  parsed
}

///|
fn parse_content_digest(
  value : String,
  field : String,
) -> @contracts.ContentDigest raise StorageError {
  @contracts.ContentDigest::parse(value) catch {
    _ => raise ValidationFailure(field~)
  }
}

///|
fn decode_contract_envelope(
  bytes : Bytes,
  record_kind : String,
) -> @contracts.WireEnvelope raise StorageError {
  @contracts.decode_wire_envelope(bytes) catch {
    UnsupportedVersion(version~, ..) | UnsupportedCanonicalVersion(version) =>
      raise UnsupportedVersion(record_kind~, version~)
    PayloadDigestMismatch(expected~, actual~)
    | EnvelopeDigestMismatch(expected~, actual~) =>
      raise DigestMismatch(
        record_kind~,
        record_id=record_kind,
        expected~,
        actual~,
      )
    _ => raise ValidationFailure(field=record_kind)
  }
}

///|
fn new_contract_record_ref(
  kind : String,
  id : String,
  version : String,
  digest : String,
  field : String,
) -> @contracts.RecordRef raise StorageError {
  @contracts.RecordRef::new(kind, id, version, digest) catch {
    _ => raise ValidationFailure(field~)
  }
}

///|
fn new_contract_evidence_ref(
  record : @contracts.RecordRef,
  provenance : @contracts.RecordRef,
  observed : String,
  locator : String?,
  media_type : String?,
) -> @contracts.EvidenceRef raise StorageError {
  @contracts.EvidenceRef::new(
    record,
    provenance,
    observed,
    locator?,
    media_type?,
  ) catch {
    _ => raise ValidationFailure(field="evidence_ref")
  }
}
