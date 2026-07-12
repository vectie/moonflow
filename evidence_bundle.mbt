///|
pub(all) struct EvidenceSourceSpec {
  artifact_ref : String
  producer_product_id : String
  contract_id : String
  claim_class : String
  result_id : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct EvidenceBundleSpec {
  contract_id : String
  bundle_id : String
  sources : Array[EvidenceSourceSpec]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct EvidenceBundleEntry {
  artifact_ref : String
  object_ref : String
  producer_product_id : String
  contract_id : String
  claim_class : String
  result_id : String
  sha256 : String
  size_bytes : Int
} derive(Debug, Eq, ToJson)

///|
pub(all) struct EvidenceBundleManifest {
  contract_id : String
  bundle_id : String
  content_digest : String
  entries : Array[EvidenceBundleEntry]
  recorded_at : String
} derive(Debug, Eq, ToJson)

///|
fn decode_evidence_source(value : Json) -> EvidenceSourceSpec raise {
  let fields = wire_object(value, "MoonFlow evidence source")
  {
    artifact_ref: wire_string(fields, "artifact_ref"),
    producer_product_id: wire_string(fields, "producer_product_id"),
    contract_id: wire_string(fields, "contract_id"),
    claim_class: wire_string(fields, "claim_class"),
    result_id: wire_string(fields, "result_id"),
  }
}

///|
pub fn decode_evidence_bundle_spec(value : Json) -> EvidenceBundleSpec raise {
  let fields = wire_object(value, "MoonFlow evidence bundle spec")
  guard fields.get("sources") is Some(Array(values)) else {
    fail("MoonFlow evidence bundle spec requires sources")
  }
  let spec = EvidenceBundleSpec::{
    contract_id: wire_string(fields, "contract_id"),
    bundle_id: wire_string(fields, "bundle_id"),
    sources: values.map(value => decode_evidence_source(value)),
  }
  if spec.contract_id != "moonflow.evidence-bundle-request.v1" {
    fail("unsupported evidence bundle request contract")
  }
  if spec.sources.is_empty() {
    fail("evidence bundle requires at least one source")
  }
  for source in spec.sources {
    if !artifact_ref_is_workspace_relative(source.artifact_ref) {
      fail("evidence source must be workspace-relative: \{source.artifact_ref}")
    }
    if claim_class_rank(source.claim_class) is None {
      fail("unsupported evidence claim: \{source.claim_class}")
    }
  }
  spec
}

///|
pub fn EvidenceBundleManifest::quality_issues(
  self : EvidenceBundleManifest,
) -> Array[String] {
  let issues : Array[String] = []
  if self.contract_id != "moonflow.evidence-bundle.v1" {
    issues.push("unsupported evidence bundle contract")
  }
  if self.bundle_id.trim().is_empty() {
    issues.push("bundle_id is required")
  }
  if !self.content_digest.has_prefix("sha256:") ||
    self.content_digest.length() != 71 {
    issues.push("content_digest must be a full sha256 digest")
  }
  if self.entries.is_empty() {
    issues.push("evidence bundle entries are required")
  }
  if self.recorded_at.trim().is_empty() {
    issues.push("recorded_at is required")
  }
  let seen : Array[String] = []
  for entry in self.entries {
    if !artifact_ref_is_workspace_relative(entry.artifact_ref) ||
      !artifact_ref_is_workspace_relative(entry.object_ref) {
      issues.push("bundle entry paths must be workspace-relative")
    }
    if seen.contains(entry.artifact_ref) {
      issues.push("duplicate evidence source: \{entry.artifact_ref}")
    } else {
      seen.push(entry.artifact_ref)
    }
    if !entry.sha256.has_prefix("sha256:") || entry.sha256.length() != 71 {
      issues.push("entry sha256 must be a full digest: \{entry.artifact_ref}")
    }
    if entry.size_bytes < 0 {
      issues.push("entry size cannot be negative")
    }
    if claim_class_rank(entry.claim_class) is None {
      issues.push("unsupported entry claim: \{entry.claim_class}")
    }
  }
  issues
}

///|
pub fn evidence_bundle_manifest(
  spec : EvidenceBundleSpec,
  entries : Array[EvidenceBundleEntry],
  content_digest : String,
  recorded_at : String,
) -> EvidenceBundleManifest raise {
  if entries.length() != spec.sources.length() {
    fail("every evidence source must produce one content-addressed entry")
  }
  let manifest = EvidenceBundleManifest::{
    contract_id: "moonflow.evidence-bundle.v1",
    bundle_id: spec.bundle_id,
    content_digest,
    entries,
    recorded_at,
  }
  let issues = manifest.quality_issues()
  if !issues.is_empty() {
    fail("invalid evidence bundle: \{issues.join("; ")}")
  }
  manifest
}
