///|
/// Immutable ordered evidence attachment bound to one workflow revision.
pub struct EvidenceAttachment {
  policy_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  attachment_ref : @contracts.RecordRef
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  purpose : @contracts.RecordRef
  attached_revision : Int64
  evidence_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
fn evidence_attachment_signing_bytes(
  policy_ref : @contracts.RecordRef,
  workflow : @contracts.RecordRef,
  attachment_id : String,
  attachment_version : String,
  evidence : ArrayView[@contracts.EvidenceRef],
  purpose : @contracts.RecordRef,
  attached_revision : Int64,
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(b"MFGEVA01")
  try! writer.write_bytes(record_bytes(policy_ref))
  try! writer.write_bytes(record_bytes(workflow))
  try! writer.write_string(attachment_id)
  try! writer.write_string(attachment_version)
  try! write_evidence_list(writer, evidence)
  try! writer.write_bytes(record_bytes(purpose))
  writer.write_int64(attached_revision)
  writer.finish()
}

///|
fn build_evidence_attachment(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  attachment_id : String,
  attachment_version : String,
  evidence : Array[@contracts.EvidenceRef],
  purpose : @contracts.RecordRef,
  attached_revision : Int64,
  supplied_digest : @contracts.ContentDigest?,
) -> EvidenceAttachment raise GovernanceError {
  require_text(attachment_id, "attachment_id")
  if attachment_version != governance_record_version {
    raise UnsupportedVersion(
      field="attachment_version",
      version=attachment_version,
    )
  }
  require_revision(attached_revision, "attached_revision")
  policy.require_evidence_count(evidence, "attachment_evidence")
  let canonical = evidence_attachment_signing_bytes(
    policy.policy_ref,
    workflow,
    attachment_id,
    attachment_version,
    evidence,
    purpose,
    attached_revision,
  )
  let binding = @contracts.sha256_digest(canonical)
  match supplied_digest {
    Some(expected) => require_digest(binding, expected, "attachment_digest")
    None => ()
  }
  {
    policy_ref: policy.policy_ref,
    workflow,
    attachment_ref: self_record(
      "governance-evidence-attachment", attachment_id, attachment_version, binding,
    ),
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    purpose,
    attached_revision,
    evidence_digest: ordered_evidence_digest(b"MFGEVL01", evidence),
    canonical,
  }
}

///|
pub fn EvidenceAttachment::new(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  attachment_id : String,
  attachment_version : String,
  evidence : Array[@contracts.EvidenceRef],
  purpose : @contracts.RecordRef,
  attached_revision : Int64,
) -> EvidenceAttachment raise GovernanceError {
  build_evidence_attachment(
    policy,
    workflow,
    attachment_id,
    attachment_version,
    evidence,
    purpose,
    attached_revision,
    None,
  )
}

///|
pub fn EvidenceAttachment::workflow(
  self : EvidenceAttachment,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn EvidenceAttachment::attachment_ref(
  self : EvidenceAttachment,
) -> @contracts.RecordRef {
  self.attachment_ref
}

///|
pub fn EvidenceAttachment::evidence(
  self : EvidenceAttachment,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn EvidenceAttachment::purpose(
  self : EvidenceAttachment,
) -> @contracts.RecordRef {
  self.purpose
}

///|
pub fn EvidenceAttachment::attached_revision(
  self : EvidenceAttachment,
) -> Int64 {
  self.attached_revision
}

///|
pub fn EvidenceAttachment::binding_digest(
  self : EvidenceAttachment,
) -> @contracts.ContentDigest {
  self.attachment_ref.digest()
}

///|
pub fn EvidenceAttachment::evidence_digest(
  self : EvidenceAttachment,
) -> @contracts.ContentDigest {
  self.evidence_digest
}

///|
pub fn EvidenceAttachment::canonical_bytes(self : EvidenceAttachment) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(self.canonical)
  try! writer.write_string(self.attachment_ref.digest().text())
  writer.finish()
}

///|
fn decode_evidence_attachment(
  bytes : Bytes,
  policy : GovernancePolicy,
) -> EvidenceAttachment raise {
  let outer = GovernanceReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = @contracts.ContentDigest::parse(outer.read_string())
  outer.require_end()
  let reader = GovernanceReader::new(signing)
  if reader.read_bytes() != b"MFGEVA01" {
    raise MalformedPayload(field="attachment_magic")
  }
  let policy_ref = {
    let nested = GovernanceReader::new(reader.read_bytes())
    let value = read_record(nested)
    nested.require_end()
    value
  }
  require_exact_record(policy_ref, policy.policy_ref, "policy")
  let workflow = {
    let nested = GovernanceReader::new(reader.read_bytes())
    let value = read_record(nested)
    nested.require_end()
    value
  }
  let attachment_id = reader.read_string()
  let version = reader.read_string()
  let evidence = read_evidence_list(reader)
  let purpose = {
    let nested = GovernanceReader::new(reader.read_bytes())
    let value = read_record(nested)
    nested.require_end()
    value
  }
  let revision = reader.read_int64()
  reader.require_end()
  build_evidence_attachment(
    policy,
    workflow,
    attachment_id,
    version,
    evidence,
    purpose,
    revision,
    Some(supplied),
  )
}
