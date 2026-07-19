///|
/// Exact immutable identity of a versioned record and its content digest.
pub struct RecordRef {
  kind : String
  id : String
  version : Version
  digest : ContentDigest
} derive(Eq, Debug)

///|
pub fn RecordRef::new(
  kind : String,
  id : String,
  version : String,
  digest : String,
) -> RecordRef raise ContractError {
  require_text(kind, "record", "kind")
  require_text(id, "record", "id")
  {
    kind,
    id,
    version: parse_version_named(version, "record.version"),
    digest: ContentDigest::parse(digest),
  }
}

///|
pub fn RecordRef::kind(self : RecordRef) -> String {
  self.kind
}

///|
pub fn RecordRef::id(self : RecordRef) -> String {
  self.id
}

///|
pub fn RecordRef::version(self : RecordRef) -> Version {
  self.version
}

///|
pub fn RecordRef::digest(self : RecordRef) -> ContentDigest {
  self.digest
}

///|
fn record_identity_equal(left : RecordRef, right : RecordRef) -> Bool {
  left.kind == right.kind &&
  left.id == right.id &&
  left.version == right.version
}

///|
fn record_identity_text(value : RecordRef) -> String {
  "\{value.kind}:\{value.id}:\{value.version.text()}"
}

///|
/// Exact immutable identity of a schema and its owning contract.
pub struct SchemaRef {
  contract_id : String
  contract_version : Version
  schema_id : String
  schema_version : Version
  schema_digest : ContentDigest
} derive(Eq, Debug)

///|
pub fn SchemaRef::new(
  contract_id : String,
  contract_version : String,
  schema_id : String,
  schema_version : String,
  schema_digest : String,
) -> SchemaRef raise ContractError {
  require_text(contract_id, "schema", "contract_id")
  require_text(schema_id, "schema", "schema_id")
  {
    contract_id,
    contract_version: parse_version_named(
      contract_version, "schema.contract_version",
    ),
    schema_id,
    schema_version: parse_version_named(schema_version, "schema.version"),
    schema_digest: ContentDigest::parse(schema_digest),
  }
}

///|
pub fn SchemaRef::contract_id(self : SchemaRef) -> String {
  self.contract_id
}

///|
pub fn SchemaRef::contract_version(self : SchemaRef) -> Version {
  self.contract_version
}

///|
pub fn SchemaRef::schema_id(self : SchemaRef) -> String {
  self.schema_id
}

///|
pub fn SchemaRef::schema_version(self : SchemaRef) -> Version {
  self.schema_version
}

///|
pub fn SchemaRef::schema_digest(self : SchemaRef) -> ContentDigest {
  self.schema_digest
}

///|
/// Immutable neutral artifact metadata. The locator cannot contain query,
/// fragment, user-information, traversal, control characters, or key-shaped
/// credential material.
pub struct ArtifactRef {
  record : RecordRef
  locator : String
  media_type : String
  run_ref : RecordRef?
  stage_ref : RecordRef?
  attempt_ref : RecordRef?
  provenance_ref : RecordRef
  observed_digest : ContentDigest
  confidentiality : String?
} derive(Eq, Debug)

///|
pub fn ArtifactRef::new(
  record : RecordRef,
  locator : String,
  media_type : String,
  provenance_ref : RecordRef,
  observed_digest : String,
  run_ref? : RecordRef,
  stage_ref? : RecordRef,
  attempt_ref? : RecordRef,
  confidentiality? : String,
) -> ArtifactRef raise ContractError {
  require_locator(locator, "artifact")
  require_media_type(media_type, "artifact")
  require_optional_text(confidentiality, "artifact", "confidentiality")
  {
    record,
    locator,
    media_type,
    run_ref,
    stage_ref,
    attempt_ref,
    provenance_ref,
    observed_digest: ContentDigest::parse(observed_digest),
    confidentiality,
  }
}

///|
pub fn ArtifactRef::record(self : ArtifactRef) -> RecordRef {
  self.record
}

///|
pub fn ArtifactRef::locator(self : ArtifactRef) -> String {
  self.locator
}

///|
pub fn ArtifactRef::media_type(self : ArtifactRef) -> String {
  self.media_type
}

///|
pub fn ArtifactRef::run_ref(self : ArtifactRef) -> RecordRef? {
  self.run_ref
}

///|
pub fn ArtifactRef::stage_ref(self : ArtifactRef) -> RecordRef? {
  self.stage_ref
}

///|
pub fn ArtifactRef::attempt_ref(self : ArtifactRef) -> RecordRef? {
  self.attempt_ref
}

///|
pub fn ArtifactRef::provenance_ref(self : ArtifactRef) -> RecordRef {
  self.provenance_ref
}

///|
pub fn ArtifactRef::observed_digest(self : ArtifactRef) -> ContentDigest {
  self.observed_digest
}

///|
pub fn ArtifactRef::confidentiality(self : ArtifactRef) -> String? {
  self.confidentiality
}

///|
/// Immutable neutral evidence metadata. Locator and media type are optional;
/// opaque evidence content remains outside this value.
pub struct EvidenceRef {
  record : RecordRef
  provenance_ref : RecordRef
  observed_digest : ContentDigest
  locator : String?
  media_type : String?
} derive(Eq, Debug)

///|
pub fn EvidenceRef::new(
  record : RecordRef,
  provenance_ref : RecordRef,
  observed_digest : String,
  locator? : String,
  media_type? : String,
) -> EvidenceRef raise ContractError {
  match locator {
    Some(value) => require_locator(value, "evidence")
    None => ()
  }
  match media_type {
    Some(value) => require_media_type(value, "evidence")
    None => ()
  }
  {
    record,
    provenance_ref,
    observed_digest: ContentDigest::parse(observed_digest),
    locator,
    media_type,
  }
}

///|
pub fn EvidenceRef::record(self : EvidenceRef) -> RecordRef {
  self.record
}

///|
pub fn EvidenceRef::provenance_ref(self : EvidenceRef) -> RecordRef {
  self.provenance_ref
}

///|
pub fn EvidenceRef::observed_digest(self : EvidenceRef) -> ContentDigest {
  self.observed_digest
}

///|
pub fn EvidenceRef::locator(self : EvidenceRef) -> String? {
  self.locator
}

///|
pub fn EvidenceRef::media_type(self : EvidenceRef) -> String? {
  self.media_type
}

///|
/// Opaque namespaced extension bytes. A namespace contains at least one dot;
/// exact bytes are included in canonicalization without interpretation.
pub struct OpaqueExtension {
  namespace_id : String
  name : String
  value : Bytes
}

///|
pub fn OpaqueExtension::new(
  namespace_id : String,
  name : String,
  value : Bytes,
) -> OpaqueExtension raise ContractError {
  require_text(namespace_id, "extension", "namespace")
  require_text(name, "extension", "name")
  if !namespace_id.contains(".") ||
    namespace_id.has_prefix(".") ||
    namespace_id.has_suffix(".") {
    raise InvalidReferenceField(reference="extension", field="namespace")
  }
  { namespace_id, name, value }
}

///|
pub fn OpaqueExtension::namespace_id(self : OpaqueExtension) -> String {
  self.namespace_id
}

///|
pub fn OpaqueExtension::name(self : OpaqueExtension) -> String {
  self.name
}

///|
pub fn OpaqueExtension::value(self : OpaqueExtension) -> Bytes {
  self.value
}

///|
pub impl Eq for OpaqueExtension with fn equal(left, right) {
  left.namespace_id == right.namespace_id &&
  left.name == right.name &&
  left.value == right.value
}
