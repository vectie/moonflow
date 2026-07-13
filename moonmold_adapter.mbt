///|
pub fn moonmold_capability() -> AdapterCapability {
  {
    adapter_id: "moonmold-mcp",
    product_id: "moonmold",
    protocol: "moonmold.blender.v1+mcp-jsonrpc-stdio",
    operations: ["semantic-operation", "live-building"],
    authority_classes: [
      "observe", "cognitive-maintenance", "sandbox-execution", "workspace-mutation",
    ],
    input_contracts: [
      "moonmold-building-plan-v1", "moonmold.spatial-artifact.v1",
      "moonmold.representation-transform.v1",
    ],
    output_contracts: [
      "moonmold.spatial-artifact.v1",
      "moonmold.representation-transform.v1",
      "moonmold-live-blender-evidence-v1",
    ],
    claim_ceiling: "digital-artifact",
    healthy: true,
    supports_cancel: true,
    supports_reconcile: true,
  }
}

///|
pub(all) struct MoonMoldDispatch {
  request : AdapterRequest
  declaration_revision : String
  source_digest : String
  expected_parent_digest : String
  expected_parent_representation : String
  expected_child_representation : String
  expected_lineage_relation : String
  authority_envelope_id : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct MoonMoldResult {
  request_id : String
  attempt_id : String
  idempotency_key : String
  status : String
  artifact_id : String
  artifact_digest : String
  parent_digest : String
  parent_representation : String
  representation : String
  lineage_relation : String
  claim_ceiling : String
  authority_envelope_id : String
  portable_artifact_ref : String
  evidence_refs : Array[String]
  physical_effects : Bool
} derive(Debug, Eq, ToJson)

///|
pub(all) struct MoonMoldEvidenceMapping {
  mapping_id : String
  request_id : String
  declaration_revision : String
  source_digest : String
  input_digest : String
  expected_parent_digest : String
  artifact_id : String
  artifact_digest : String
  representation : String
  lineage_relation : String
  claim_ceiling : String
  authority_envelope_id : String
  accepted : Bool
  issues : Array[String]
  checkpoint_artifact_refs : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct MoonMoldCheckpointDecision {
  decision : String
  reason : String
  invalidated_artifact_refs : Array[String]
} derive(Debug, Eq, ToJson)

///|
fn moonmold_digest_valid(value : String) -> Bool {
  value.has_prefix("sha256:") && value.length() == 71
}

///|
fn moonmold_representation_transition_issues(
  parent : String,
  child : String,
  relation : String,
) -> Array[String] {
  let issues : Array[String] = []
  match child {
    "editable-authoring-model" =>
      if parent != "spatial-intent" || relation != "modeled-from" {
        issues.push("editable authoring must be modeled from spatial intent")
      }
    "engineering-model" =>
      if parent != "editable-authoring-model" || relation != "modeled-from" {
        issues.push("engineering must be modeled from editable authoring geometry")
      }
    "visual-styled-model" =>
      if parent != "engineering-model" || relation != "styled-from" {
        issues.push("presentation must be styled from engineering geometry")
      }
    "simulation-model" =>
      if parent != "engineering-model" || relation != "physics-derived-from" {
        issues.push("simulation input must be physics-derived from engineering geometry")
      }
    "manufacturing-candidate" =>
      if parent != "engineering-model" ||
        relation != "manufacturing-derived-from" {
        issues.push("manufacturing candidate must derive from engineering geometry")
      }
    _ => issues.push("unsupported MoonMold representation")
  }
  issues
}

///|
pub fn MoonMoldDispatch::quality_issues(
  self : MoonMoldDispatch,
) -> Array[String] {
  let issues = self.request.quality_issues()
  if self.request.product_id != "moonmold" {
    issues.push("MoonMold dispatch product_id must be moonmold")
  }
  if self.request.operation != "semantic-operation" &&
    self.request.operation != "live-building" {
    issues.push("unsupported MoonMold dispatch operation")
  }
  if self.request.requested_authority == "external-effect" ||
    self.request.requested_authority == "physical-effect" {
    issues.push("MoonMold dispatch cannot request external or physical authority")
  }
  if self.request.required_claim != "digital-artifact" {
    issues.push("MoonMold dispatch claim ceiling must be digital-artifact")
  }
  if self.declaration_revision.trim().is_empty() ||
    self.authority_envelope_id.trim().is_empty() {
    issues.push("declaration revision and authority envelope are required")
  }
  if !moonmold_digest_valid(self.source_digest) ||
    !moonmold_digest_valid(self.expected_parent_digest) {
    issues.push("source and expected parent must be sha256 digests")
  }
  issues.append(
    moonmold_representation_transition_issues(
      self.expected_parent_representation,
      self.expected_child_representation,
      self.expected_lineage_relation,
    ),
  )
  issues
}

///|
pub fn attest_moonmold_result(
  dispatch : MoonMoldDispatch,
  result : MoonMoldResult,
) -> MoonMoldEvidenceMapping {
  let issues = dispatch.quality_issues()
  if result.request_id != dispatch.request.request_id ||
    result.attempt_id != dispatch.request.attempt_id ||
    result.idempotency_key != dispatch.request.idempotency_key {
    issues.push("result request, attempt, or idempotency lineage mismatches dispatch")
  }
  if result.status != "succeeded" && result.status != "idempotent-no-op" {
    issues.push("MoonMold result is not successful")
  }
  if result.parent_digest != dispatch.expected_parent_digest {
    issues.push("MoonMold result has a stale or unexpected parent digest")
  }
  if result.parent_representation != dispatch.expected_parent_representation ||
    result.representation != dispatch.expected_child_representation ||
    result.lineage_relation != dispatch.expected_lineage_relation {
    issues.push("MoonMold result representation lineage mismatches dispatch")
  }
  issues.append(
    moonmold_representation_transition_issues(
      result.parent_representation,
      result.representation,
      result.lineage_relation,
    ),
  )
  if !moonmold_digest_valid(result.artifact_digest) {
    issues.push("MoonMold artifact digest must be sha256")
  }
  if result.claim_ceiling != "digital-artifact" {
    issues.push("MoonMold cannot emit simulation evidence or physical claims")
  }
  if result.authority_envelope_id != dispatch.authority_envelope_id {
    issues.push("MoonMold result authority envelope mismatches dispatch")
  }
  if result.physical_effects {
    issues.push("MoonMold result cannot report physical effects")
  }
  if !artifact_ref_is_workspace_relative(result.portable_artifact_ref) {
    issues.push("MoonMold portable artifact ref must be workspace-relative")
  }
  for evidence_ref in result.evidence_refs {
    if !artifact_ref_is_workspace_relative(evidence_ref) {
      issues.push("MoonMold evidence refs must be workspace-relative")
    }
  }
  {
    mapping_id: "moonmold-evidence-\{dispatch.request.request_id}",
    request_id: dispatch.request.request_id,
    declaration_revision: dispatch.declaration_revision,
    source_digest: dispatch.source_digest,
    input_digest: dispatch.request.input_digest,
    expected_parent_digest: dispatch.expected_parent_digest,
    artifact_id: result.artifact_id,
    artifact_digest: result.artifact_digest,
    representation: result.representation,
    lineage_relation: result.lineage_relation,
    claim_ceiling: result.claim_ceiling,
    authority_envelope_id: result.authority_envelope_id,
    accepted: issues.is_empty(),
    issues,
    checkpoint_artifact_refs: [
      result.portable_artifact_ref, ..result.evidence_refs,
    ],
  }
}

///|
pub fn moonmold_checkpoint_decision(
  accepted : MoonMoldEvidenceMapping,
  child : MoonMoldDispatch,
) -> MoonMoldCheckpointDecision {
  let refs = accepted.checkpoint_artifact_refs.copy()
  if !accepted.accepted {
    return {
      decision: "invalidated",
      reason: "source MoonMold evidence was not accepted",
      invalidated_artifact_refs: refs,
    }
  }
  if child.quality_issues().length() > 0 {
    return {
      decision: "invalidated",
      reason: "revised MoonMold dispatch is invalid",
      invalidated_artifact_refs: refs,
    }
  }
  if child.source_digest != accepted.source_digest {
    return {
      decision: "invalidated",
      reason: "declaration source digest changed",
      invalidated_artifact_refs: refs,
    }
  }
  if child.request.input_digest != accepted.input_digest {
    return {
      decision: "invalidated",
      reason: "spatial input digest changed",
      invalidated_artifact_refs: refs,
    }
  }
  if child.expected_parent_digest != accepted.expected_parent_digest {
    return {
      decision: "invalidated",
      reason: "accepted parent geometry changed",
      invalidated_artifact_refs: refs,
    }
  }
  if child.expected_child_representation != accepted.representation ||
    child.expected_lineage_relation != accepted.lineage_relation ||
    child.authority_envelope_id != accepted.authority_envelope_id {
    return {
      decision: "invalidated",
      reason: "representation, lineage, or authority changed",
      invalidated_artifact_refs: refs,
    }
  }
  {
    decision: "reused",
    reason: "source, input, parent, representation, lineage, and authority remain exact",
    invalidated_artifact_refs: [],
  }
}

