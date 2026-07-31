///|
pub fn capability_source_bundle_contract_v1() -> String {
  "moonflow.capability-source-bundle.v1"
}

///|
pub fn adapter_declaration_contract_v1() -> String {
  "moonflow.adapter-declaration.v1"
}

///|
pub fn adapter_health_contract_v1() -> String {
  "moonflow.adapter-health.v1"
}

///|
pub fn capability_catalog_contract_v1() -> String {
  "moonflow.capability-catalog.v1"
}

///|
pub fn graph_capability_report_contract_v1() -> String {
  "moonflow.graph-capability-report.v1"
}

///|
pub(all) struct PackSchemaDescriptorV1 {
  id : String
  version : String
  path : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PackToolDescriptorV1 {
  id : String
  owner_product : String
  input_schema_id : String
  output_schema_id : String
  authority : String
  idempotent : Bool
  review_required : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PackCapabilityManifestV1 {
  pack_id : String
  product_id : String
  pack_version : String
  schemas : Array[PackSchemaDescriptorV1]
  tools : Array[PackToolDescriptorV1]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AdapterOperationDeclarationV1 {
  operation_id : String
  claim_ceiling : String
  supports_cancel : Bool
  supports_reconcile : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AdapterDeclarationV1 {
  contract_id : String
  adapter_id : String
  product_id : String
  pack_id : String
  pack_version : String
  protocol : String
  operations : Array[AdapterOperationDeclarationV1]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AdapterHealthAttestationV1 {
  contract_id : String
  adapter_id : String
  product_id : String
  pack_id : String
  pack_version : String
  protocol : String
  status : String
  checked_at : String
  valid_until : String
  operation_refs : Array[String]
  evidence_ref : String
  evidence_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilityProductV1 {
  product_id : String
  pack_id : String
  pack_version : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilityOperationV1 {
  operation_ref : String
  product_id : String
  pack_id : String
  pack_version : String
  tool_id : String
  adapter_id : String
  protocol : String
  authority : String
  input_schema_ref : String
  output_schema_ref : String
  claim_ceiling : String
  idempotent : Bool
  review_required : Bool
  supports_cancel : Bool
  supports_reconcile : Bool
  health_checked_at : String
  health_valid_until : String
  health_evidence_ref : String
  health_evidence_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilityConformanceIssueV1 {
  code : String
  subject : String
  detail : String
  suggestions : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilityCatalogV1 {
  contract_id : String
  catalog_id : String
  compiled_at : String
  conformant : Bool
  products : Array[CapabilityProductV1]
  operations : Array[CapabilityOperationV1]
  issues : Array[CapabilityConformanceIssueV1]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GraphCapabilityBindingV1 {
  work_item_id : String
  operation_ref : String
  adapter_id : String
  input_schema_ref : String
  output_schema_ref : String
  authority : String
  claim_ceiling : String
  review_required : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GraphCapabilityReportV1 {
  contract_id : String
  catalog_id : String
  graph_id : String
  accepted : Bool
  bindings : Array[GraphCapabilityBindingV1]
  issues : Array[CapabilityConformanceIssueV1]
  catalog_issues : Array[CapabilityConformanceIssueV1]
} derive(Debug, Eq, ToJson, FromJson)

///|
fn catalog_json_values(
  fields : Map[String, Json],
  key : String,
) -> Array[Json] raise {
  match fields.get(key) {
    Some(Array(values)) => values
    _ => fail("missing or invalid array field: \{key}")
  }
}

///|
fn catalog_safe_identifier(value : String) -> Bool {
  !value.is_blank() &&
  value.length() <= 128 &&
  value
  .iter()
  .all(char => {
    char.is_ascii_alphabetic() ||
    char.is_ascii_digit() ||
    char == '-' ||
    char == '_' ||
    char == '.'
  })
}

///|
fn catalog_semver_is_canonical(value : String) -> Bool {
  let parts = value.split(".").to_array()
  if parts.length() != 3 {
    return false
  }
  for part in parts {
    if part.is_empty() ||
      (part.length() > 1 && part[0] == '0') ||
      !part.iter().all(char => char.is_ascii_digit()) {
      return false
    }
  }
  true
}

///|
fn catalog_timestamp_is_canonical(value : String) -> Bool {
  value.length() == 20 &&
  value[4] == '-' &&
  value[7] == '-' &&
  value[10] == 'T' &&
  value[13] == ':' &&
  value[16] == ':' &&
  value[19] == 'Z' &&
  value
  .iter()
  .all(char => {
    char.is_ascii_digit() ||
    char == '-' ||
    char == 'T' ||
    char == ':' ||
    char == 'Z'
  })
}

///|
fn catalog_digest_is_sha256(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:]
  .iter()
  .all(char => char.is_ascii_digit() || ('a' <= char && char <= 'f'))
}

///|
fn catalog_versioned_ref_is_canonical(
  value : String,
  product_id : String,
) -> Bool {
  let owner_parts = value.split("/").to_array()
  if owner_parts.length() != 2 || owner_parts[0].to_owned() != product_id {
    return false
  }
  let version_parts = owner_parts[1].split("@").to_array()
  version_parts.length() == 2 &&
  catalog_safe_identifier(version_parts[0].to_owned()) &&
  catalog_semver_is_canonical(version_parts[1].to_owned())
}

///|
fn canonical_pack_authority(value : String) -> String? {
  match value {
    "Observe" | "observe" => Some("observe")
    "CognitiveMaintenance" | "cognitive-maintenance" =>
      Some("cognitive-maintenance")
    "SandboxExecution" | "sandbox-execution" => Some("sandbox-execution")
    "WorkspaceMutation" | "workspace-mutation" => Some("workspace-mutation")
    "ExternalEffect" | "external-effect" => Some("external-effect")
    "PhysicalEffect" | "physical-effect" => Some("physical-effect")
    _ => None
  }
}

///|
pub fn versioned_operation_ref(
  product_id : String,
  tool_id : String,
  pack_version : String,
) -> String {
  "\{product_id}/\{tool_id}@\{pack_version}"
}

///|
pub fn versioned_schema_ref(
  product_id : String,
  schema_id : String,
  schema_version : String,
) -> String {
  "\{product_id}/\{schema_id}@\{schema_version}"
}

///|
fn decode_pack_schema_descriptor_v1(
  value : Json,
) -> PackSchemaDescriptorV1 raise {
  let fields = wire_object(value, "pack schema descriptor")
  {
    id: wire_string(fields, "id"),
    version: wire_string(fields, "version"),
    path: wire_string(fields, "path"),
  }
}

///|
fn decode_pack_tool_descriptor_v1(value : Json) -> PackToolDescriptorV1 raise {
  let fields = wire_object(value, "pack tool descriptor")
  {
    id: wire_string(fields, "id"),
    owner_product: wire_string(fields, "owner_product"),
    input_schema_id: wire_string(fields, "input_schema_id"),
    output_schema_id: wire_string(fields, "output_schema_id"),
    authority: wire_string(fields, "authority"),
    idempotent: wire_bool(fields, "idempotent"),
    review_required: wire_bool(fields, "review_required"),
  }
}

///|
pub fn decode_pack_capability_manifest_v1(
  value : Json,
) -> PackCapabilityManifestV1 raise {
  let fields = wire_object(value, "Moon Suite pack manifest")
  {
    pack_id: wire_string(fields, "id"),
    product_id: wire_string(fields, "product_id"),
    pack_version: wire_string(fields, "version"),
    schemas: catalog_json_values(fields, "schemas").map(
      decode_pack_schema_descriptor_v1,
    ),
    tools: catalog_json_values(fields, "tools").map(
      decode_pack_tool_descriptor_v1,
    ),
  }
}

///|
fn decode_adapter_operation_declaration_v1(
  value : Json,
) -> AdapterOperationDeclarationV1 raise {
  let fields = wire_object(value, "MoonFlow adapter operation declaration")
  {
    operation_id: wire_string(fields, "operation_id"),
    claim_ceiling: wire_string(fields, "claim_ceiling"),
    supports_cancel: wire_bool(fields, "supports_cancel"),
    supports_reconcile: wire_bool(fields, "supports_reconcile"),
  }
}

///|
pub fn decode_adapter_declaration_v1(
  value : Json,
) -> AdapterDeclarationV1 raise {
  let fields = wire_object(value, "MoonFlow adapter declaration")
  {
    contract_id: wire_string(fields, "contract_id"),
    adapter_id: wire_string(fields, "adapter_id"),
    product_id: wire_string(fields, "product_id"),
    pack_id: wire_string(fields, "pack_id"),
    pack_version: wire_string(fields, "pack_version"),
    protocol: wire_string(fields, "protocol"),
    operations: catalog_json_values(fields, "operations").map(
      decode_adapter_operation_declaration_v1,
    ),
  }
}

///|
pub fn decode_adapter_health_attestation_v1(
  value : Json,
) -> AdapterHealthAttestationV1 raise {
  let fields = wire_object(value, "MoonFlow adapter health attestation")
  {
    contract_id: wire_string(fields, "contract_id"),
    adapter_id: wire_string(fields, "adapter_id"),
    product_id: wire_string(fields, "product_id"),
    pack_id: wire_string(fields, "pack_id"),
    pack_version: wire_string(fields, "pack_version"),
    protocol: wire_string(fields, "protocol"),
    status: wire_string(fields, "status"),
    checked_at: wire_string(fields, "checked_at"),
    valid_until: wire_string(fields, "valid_until"),
    operation_refs: wire_strings(fields, "operation_refs"),
    evidence_ref: wire_string(fields, "evidence_ref"),
    evidence_digest: wire_string(fields, "evidence_digest"),
  }
}

///|
fn catalog_add_issue(
  issues : Array[CapabilityConformanceIssueV1],
  code : String,
  subject : String,
  detail : String,
  suggestions? : Array[String] = [],
) -> Unit {
  issues.push({ code, subject, detail, suggestions })
}

///|
fn manifest_schema(
  manifest : PackCapabilityManifestV1,
  schema_id : String,
) -> PackSchemaDescriptorV1? {
  for schema in manifest.schemas {
    if schema.id == schema_id {
      return Some(schema)
    }
  }
  None
}

///|
fn matching_adapter_declarations(
  declarations : Array[AdapterDeclarationV1],
  manifest : PackCapabilityManifestV1,
  operation_id : String,
) -> Array[(AdapterDeclarationV1, AdapterOperationDeclarationV1)] {
  let matches : Array[(AdapterDeclarationV1, AdapterOperationDeclarationV1)] = []
  for declaration in declarations {
    if declaration.product_id == manifest.product_id &&
      declaration.pack_id == manifest.pack_id &&
      declaration.pack_version == manifest.pack_version {
      for operation in declaration.operations {
        if operation.operation_id == operation_id {
          matches.push((declaration, operation))
        }
      }
    }
  }
  matches
}

///|
fn matching_health_attestations(
  attestations : Array[AdapterHealthAttestationV1],
  declaration : AdapterDeclarationV1,
) -> Array[AdapterHealthAttestationV1] {
  attestations.filter(health => {
    health.adapter_id == declaration.adapter_id &&
    health.product_id == declaration.product_id &&
    health.pack_id == declaration.pack_id &&
    health.pack_version == declaration.pack_version
  })
}

///|
fn validate_manifest_shape(
  manifest : PackCapabilityManifestV1,
  issues : Array[CapabilityConformanceIssueV1],
) -> Unit {
  let subject = "\{manifest.product_id}@\{manifest.pack_version}"
  if !catalog_safe_identifier(manifest.pack_id) {
    catalog_add_issue(
      issues, "invalid-pack-id", subject, "pack id must be a safe non-empty identifier",
    )
  }
  if !catalog_safe_identifier(manifest.product_id) {
    catalog_add_issue(
      issues, "invalid-product-id", subject, "product id must be a safe non-empty identifier",
    )
  }
  if !catalog_semver_is_canonical(manifest.pack_version) {
    catalog_add_issue(
      issues, "invalid-pack-version", subject, "pack version must be canonical major.minor.patch",
    )
  }
  if manifest.schemas.is_empty() {
    catalog_add_issue(
      issues, "schemas-missing", subject, "pack manifest must declare versioned schemas",
    )
  }
  if manifest.tools.is_empty() {
    catalog_add_issue(
      issues, "tools-missing", subject, "pack manifest must declare executable tools",
    )
  }
  let schema_ids : Array[String] = []
  for schema in manifest.schemas {
    let schema_subject = "\{subject}/schema/\{schema.id}"
    if !catalog_safe_identifier(schema.id) {
      catalog_add_issue(
        issues, "invalid-schema-id", schema_subject, "schema id must be a safe non-empty identifier",
      )
    }
    if schema_ids.contains(schema.id) {
      catalog_add_issue(
        issues, "duplicate-schema-id", schema_subject, "schema ids must be unique within one pack version",
      )
    } else {
      schema_ids.push(schema.id)
    }
    if !catalog_semver_is_canonical(schema.version) {
      catalog_add_issue(
        issues, "invalid-schema-version", schema_subject, "schema version must be canonical major.minor.patch",
      )
    }
    if !artifact_ref_is_workspace_relative(schema.path) {
      catalog_add_issue(
        issues, "invalid-schema-path", schema_subject, "schema path must be workspace relative",
      )
    }
  }
  let tool_ids : Array[String] = []
  for tool in manifest.tools {
    let tool_subject = "\{subject}/tool/\{tool.id}"
    if !catalog_safe_identifier(tool.id) {
      catalog_add_issue(
        issues, "invalid-tool-id", tool_subject, "tool id must be a safe non-empty identifier",
      )
    }
    if tool_ids.contains(tool.id) {
      catalog_add_issue(
        issues, "duplicate-tool-id", tool_subject, "tool ids must be unique within one pack version",
      )
    } else {
      tool_ids.push(tool.id)
    }
    if tool.owner_product != manifest.product_id {
      catalog_add_issue(
        issues, "tool-owner-mismatch", tool_subject, "tool owner_product must equal manifest product_id",
      )
    }
    if manifest_schema(manifest, tool.input_schema_id) is None {
      catalog_add_issue(
        issues, "input-schema-missing", tool_subject, "input_schema_id does not resolve in the pack manifest",
      )
    }
    if manifest_schema(manifest, tool.output_schema_id) is None {
      catalog_add_issue(
        issues, "output-schema-missing", tool_subject, "output_schema_id does not resolve in the pack manifest",
      )
    }
    if canonical_pack_authority(tool.authority) is None {
      catalog_add_issue(
        issues,
        "authority-unsupported",
        tool_subject,
        "tool authority is not a canonical Moon Suite authority class",
        suggestions=canonical_authority_classes(),
      )
    }
  }
}

///|
fn declaration_shape_issues(
  declaration : AdapterDeclarationV1,
  issues : Array[CapabilityConformanceIssueV1],
) -> Unit {
  let subject = "\{declaration.adapter_id}@\{declaration.pack_version}"
  if declaration.contract_id != adapter_declaration_contract_v1() {
    catalog_add_issue(
      issues,
      "adapter-contract-unsupported",
      subject,
      "adapter declaration contract_id is unsupported",
      suggestions=[adapter_declaration_contract_v1()],
    )
  }
  if !catalog_safe_identifier(declaration.adapter_id) {
    catalog_add_issue(
      issues, "invalid-adapter-id", subject, "adapter id must be a safe non-empty identifier",
    )
  }
  if !catalog_safe_identifier(declaration.product_id) ||
    !catalog_safe_identifier(declaration.pack_id) ||
    !catalog_semver_is_canonical(declaration.pack_version) {
    catalog_add_issue(
      issues, "adapter-subject-invalid", subject, "adapter product, pack and pack version identities must be canonical",
    )
  }
  if declaration.protocol != "moonflow.adapter.v2" {
    catalog_add_issue(
      issues,
      "adapter-protocol-unsupported",
      subject,
      "manifest-derived capabilities require moonflow.adapter.v2",
      suggestions=["moonflow.adapter.v2"],
    )
  }
  if declaration.operations.is_empty() {
    catalog_add_issue(
      issues, "adapter-operations-missing", subject, "adapter declaration must bind at least one manifest operation",
    )
  }
  let operation_ids : Array[String] = []
  for operation in declaration.operations {
    let operation_subject = "\{subject}/\{operation.operation_id}"
    if operation_ids.contains(operation.operation_id) {
      catalog_add_issue(
        issues, "duplicate-adapter-operation", operation_subject, "an adapter may declare an operation only once",
      )
    } else {
      operation_ids.push(operation.operation_id)
    }
    if claim_class_rank(operation.claim_ceiling) is None {
      catalog_add_issue(
        issues, "claim-ceiling-unsupported", operation_subject, "adapter operation claim ceiling is unsupported",
      )
    }
    if !operation.supports_reconcile {
      catalog_add_issue(
        issues, "reconciliation-unsupported", operation_subject, "production adapter operations must support reconciliation",
      )
    }
  }
}

///|
fn declaration_is_executable(
  declaration : AdapterDeclarationV1,
  operation : AdapterOperationDeclarationV1,
) -> Bool {
  declaration.contract_id == adapter_declaration_contract_v1() &&
  catalog_safe_identifier(declaration.adapter_id) &&
  catalog_safe_identifier(declaration.product_id) &&
  catalog_safe_identifier(declaration.pack_id) &&
  catalog_semver_is_canonical(declaration.pack_version) &&
  declaration.protocol == "moonflow.adapter.v2" &&
  catalog_safe_identifier(operation.operation_id) &&
  claim_class_rank(operation.claim_ceiling) is Some(_) &&
  operation.supports_reconcile
}

///|
fn health_shape_issues(
  health : AdapterHealthAttestationV1,
  compiled_at : String,
  issues : Array[CapabilityConformanceIssueV1],
) -> Unit {
  let subject = "\{health.adapter_id}@\{health.pack_version}"
  if health.contract_id != adapter_health_contract_v1() {
    catalog_add_issue(
      issues,
      "health-contract-unsupported",
      subject,
      "adapter health contract_id is unsupported",
      suggestions=[adapter_health_contract_v1()],
    )
  }
  if !catalog_safe_identifier(health.adapter_id) ||
    !catalog_safe_identifier(health.product_id) ||
    !catalog_safe_identifier(health.pack_id) ||
    !catalog_semver_is_canonical(health.pack_version) {
    catalog_add_issue(
      issues, "health-subject-invalid", subject, "health adapter, product, pack and version identities must be canonical",
    )
  }
  if health.protocol != "moonflow.adapter.v2" {
    catalog_add_issue(
      issues,
      "health-protocol-unsupported",
      subject,
      "health evidence must observe moonflow.adapter.v2",
      suggestions=["moonflow.adapter.v2"],
    )
  }
  if health.status != "healthy" {
    catalog_add_issue(
      issues,
      "adapter-unhealthy",
      subject,
      "adapter health status must be healthy, got \{health.status}",
    )
  }
  if !catalog_timestamp_is_canonical(health.checked_at) ||
    !catalog_timestamp_is_canonical(health.valid_until) {
    catalog_add_issue(
      issues, "health-time-invalid", subject, "checked_at and valid_until must be canonical UTC timestamps",
    )
  } else if health.checked_at > compiled_at {
    catalog_add_issue(
      issues, "health-from-future", subject, "health evidence was recorded after catalog compilation",
    )
  } else if health.valid_until < compiled_at {
    catalog_add_issue(
      issues, "health-expired", subject, "health evidence expired before catalog compilation",
    )
  }
  if !artifact_ref_is_workspace_relative(health.evidence_ref) {
    catalog_add_issue(
      issues, "health-evidence-ref-invalid", subject, "health evidence_ref must be workspace relative",
    )
  }
  if !catalog_digest_is_sha256(health.evidence_digest) {
    catalog_add_issue(
      issues, "health-evidence-digest-invalid", subject, "health evidence_digest must be a lowercase sha256 digest",
    )
  }
  let operation_refs : Array[String] = []
  for operation_ref in health.operation_refs {
    if operation_refs.contains(operation_ref) {
      catalog_add_issue(
        issues, "health-operation-duplicate", subject, "health operation_refs must be unique",
      )
    } else {
      operation_refs.push(operation_ref)
    }
  }
}

///|
fn health_is_executable(
  health : AdapterHealthAttestationV1,
  compiled_at : String,
) -> Bool {
  let seen : Array[String] = []
  let mut unique_operations = true
  for operation_ref in health.operation_refs {
    if seen.contains(operation_ref) {
      unique_operations = false
    } else {
      seen.push(operation_ref)
    }
  }
  health.contract_id == adapter_health_contract_v1() &&
  catalog_safe_identifier(health.adapter_id) &&
  catalog_safe_identifier(health.product_id) &&
  catalog_safe_identifier(health.pack_id) &&
  catalog_semver_is_canonical(health.pack_version) &&
  health.protocol == "moonflow.adapter.v2" &&
  health.status == "healthy" &&
  catalog_timestamp_is_canonical(health.checked_at) &&
  catalog_timestamp_is_canonical(health.valid_until) &&
  health.checked_at <= compiled_at &&
  health.valid_until >= compiled_at &&
  unique_operations &&
  artifact_ref_is_workspace_relative(health.evidence_ref) &&
  catalog_digest_is_sha256(health.evidence_digest)
}

///|
pub fn compile_capability_catalog_v1(value : Json) -> CapabilityCatalogV1 raise {
  let fields = wire_object(value, "MoonFlow capability source bundle")
  let contract_id = wire_string(fields, "contract_id")
  guard contract_id == capability_source_bundle_contract_v1() else {
    fail("unsupported capability source bundle contract: \{contract_id}")
  }
  let catalog_id = wire_string(fields, "catalog_id")
  let compiled_at = wire_string(fields, "compiled_at")
  guard catalog_timestamp_is_canonical(compiled_at) else {
    fail("capability source compiled_at must be a canonical UTC timestamp")
  }
  let manifests = catalog_json_values(fields, "pack_manifests").map(
    decode_pack_capability_manifest_v1,
  )
  let declarations = catalog_json_values(fields, "adapter_declarations").map(
    decode_adapter_declaration_v1,
  )
  let health_attestations = catalog_json_values(fields, "health_attestations").map(
    decode_adapter_health_attestation_v1,
  )
  let issues : Array[CapabilityConformanceIssueV1] = []
  let products : Array[CapabilityProductV1] = []
  let operations : Array[CapabilityOperationV1] = []
  for declaration in declarations {
    declaration_shape_issues(declaration, issues)
  }
  for health in health_attestations {
    health_shape_issues(health, compiled_at, issues)
  }
  for manifest in manifests {
    let manifest_issue_count = issues.length()
    validate_manifest_shape(manifest, issues)
    let product = CapabilityProductV1::{
      product_id: manifest.product_id,
      pack_id: manifest.pack_id,
      pack_version: manifest.pack_version,
    }
    if products.contains(product) {
      catalog_add_issue(
        issues,
        "duplicate-pack-manifest",
        "\{manifest.product_id}@\{manifest.pack_version}",
        "the source bundle contains the same pack identity more than once",
      )
    } else {
      products.push(product)
    }
    if issues.length() != manifest_issue_count {
      continue
    }
    for tool in manifest.tools {
      let operation_ref = versioned_operation_ref(
        manifest.product_id,
        tool.id,
        manifest.pack_version,
      )
      let operation_issue_count = issues.length()
      guard manifest_schema(manifest, tool.input_schema_id)
        is Some(input_schema) else {
        continue
      }
      guard manifest_schema(manifest, tool.output_schema_id)
        is Some(output_schema) else {
        continue
      }
      guard canonical_pack_authority(tool.authority) is Some(authority) else {
        continue
      }
      let matches = matching_adapter_declarations(
        declarations,
        manifest,
        tool.id,
      )
      if matches.is_empty() {
        catalog_add_issue(
          issues, "adapter-declaration-missing", operation_ref, "manifest tool has no version-matched adapter declaration",
        )
        continue
      }
      if matches.length() > 1 {
        catalog_add_issue(
          issues, "adapter-declaration-ambiguous", operation_ref, "manifest tool resolves to more than one adapter declaration",
        )
        continue
      }
      let (declaration, adapter_operation) = matches[0]
      if !declaration_is_executable(declaration, adapter_operation) {
        continue
      }
      let health_matches = matching_health_attestations(
        health_attestations, declaration,
      )
      if health_matches.is_empty() {
        catalog_add_issue(
          issues, "health-attestation-missing", operation_ref, "adapter has no version-matched health attestation",
        )
        continue
      }
      if health_matches.length() > 1 {
        catalog_add_issue(
          issues, "health-attestation-ambiguous", operation_ref, "adapter has more than one health attestation in the source bundle",
        )
        continue
      }
      let health = health_matches[0]
      if health.protocol != declaration.protocol {
        catalog_add_issue(
          issues,
          "health-protocol-mismatch",
          operation_ref,
          "health evidence observed a different adapter protocol",
          suggestions=[declaration.protocol],
        )
      }
      if !health.operation_refs.contains(operation_ref) {
        catalog_add_issue(
          issues,
          "health-operation-unobserved",
          operation_ref,
          "health evidence did not exercise the versioned operation",
          suggestions=[operation_ref],
        )
      }
      if !health_is_executable(health, compiled_at) {
        continue
      }
      if issues.length() != operation_issue_count {
        continue
      }
      operations.push({
        operation_ref,
        product_id: manifest.product_id,
        pack_id: manifest.pack_id,
        pack_version: manifest.pack_version,
        tool_id: tool.id,
        adapter_id: declaration.adapter_id,
        protocol: declaration.protocol,
        authority,
        input_schema_ref: versioned_schema_ref(
          manifest.product_id,
          input_schema.id,
          input_schema.version,
        ),
        output_schema_ref: versioned_schema_ref(
          manifest.product_id,
          output_schema.id,
          output_schema.version,
        ),
        claim_ceiling: adapter_operation.claim_ceiling,
        idempotent: tool.idempotent,
        review_required: tool.review_required,
        supports_cancel: adapter_operation.supports_cancel,
        supports_reconcile: adapter_operation.supports_reconcile,
        health_checked_at: health.checked_at,
        health_valid_until: health.valid_until,
        health_evidence_ref: health.evidence_ref,
        health_evidence_digest: health.evidence_digest,
      })
    }
  }
  {
    contract_id: capability_catalog_contract_v1(),
    catalog_id,
    compiled_at,
    conformant: issues.is_empty(),
    products,
    operations,
    issues,
  }
}

///|
pub fn decode_capability_catalog_v1(value : Json) -> CapabilityCatalogV1 raise {
  let catalog : CapabilityCatalogV1 = @json.from_json(value)
  guard catalog.contract_id == capability_catalog_contract_v1() else {
    fail("unsupported capability catalog contract: \{catalog.contract_id}")
  }
  guard catalog_timestamp_is_canonical(catalog.compiled_at) else {
    fail("capability catalog compiled_at must be a canonical UTC timestamp")
  }
  guard catalog_safe_identifier(catalog.catalog_id) else {
    fail("capability catalog_id must be a safe non-empty identifier")
  }
  let product_identities : Array[String] = []
  for product in catalog.products {
    guard catalog_safe_identifier(product.product_id) &&
      catalog_safe_identifier(product.pack_id) &&
      catalog_semver_is_canonical(product.pack_version) else {
      fail("capability catalog contains an invalid product identity")
    }
    let identity = "\{product.product_id}/\{product.pack_id}@\{product.pack_version}"
    guard !product_identities.contains(identity) else {
      fail("capability catalog contains a duplicate product identity")
    }
    product_identities.push(identity)
  }
  let operation_refs : Array[String] = []
  for operation in catalog.operations {
    guard catalog_safe_identifier(operation.product_id) &&
      catalog_safe_identifier(operation.pack_id) &&
      catalog_safe_identifier(operation.tool_id) &&
      catalog_semver_is_canonical(operation.pack_version) &&
      catalog_safe_identifier(operation.adapter_id) else {
      fail("capability catalog contains an invalid operation identity")
    }
    guard product_identities.contains(
      "\{operation.product_id}/\{operation.pack_id}@\{operation.pack_version}",
    ) else {
      fail("capability catalog operation has no matching installed product")
    }
    guard operation.operation_ref ==
      versioned_operation_ref(
        operation.product_id,
        operation.tool_id,
        operation.pack_version,
      ) else {
      fail("capability catalog contains a non-canonical operation_ref")
    }
    guard !operation_refs.contains(operation.operation_ref) else {
      fail("capability catalog contains a duplicate operation_ref")
    }
    operation_refs.push(operation.operation_ref)
    guard catalog_versioned_ref_is_canonical(
        operation.input_schema_ref,
        operation.product_id,
      ) &&
      catalog_versioned_ref_is_canonical(
        operation.output_schema_ref,
        operation.product_id,
      ) else {
      fail("capability catalog contains a non-canonical schema reference")
    }
    guard operation.protocol == "moonflow.adapter.v2" &&
      operation.supports_reconcile &&
      authority_class_is_canonical(operation.authority) &&
      claim_class_rank(operation.claim_ceiling) is Some(_) else {
      fail("capability catalog contains a non-conformant operation")
    }
    guard catalog_timestamp_is_canonical(operation.health_checked_at) &&
      catalog_timestamp_is_canonical(operation.health_valid_until) &&
      operation.health_checked_at <= catalog.compiled_at &&
      operation.health_valid_until >= catalog.compiled_at &&
      artifact_ref_is_workspace_relative(operation.health_evidence_ref) &&
      catalog_digest_is_sha256(operation.health_evidence_digest) else {
      fail("capability catalog contains invalid health evidence")
    }
  }
  catalog
}

///|
pub fn CapabilityCatalogV1::adapter_capabilities(
  self : CapabilityCatalogV1,
) -> Array[AdapterCapability] {
  self.operations.map(operation => AdapterCapability::{
    adapter_id: operation.adapter_id,
    product_id: operation.product_id,
    protocol: operation.protocol,
    operations: [operation.operation_ref],
    authority_classes: [operation.authority],
    input_contracts: [operation.input_schema_ref],
    output_contracts: [operation.output_schema_ref],
    claim_ceiling: operation.claim_ceiling,
    healthy: true,
    supports_cancel: operation.supports_cancel,
    supports_reconcile: operation.supports_reconcile,
  })
}

///|
pub fn CapabilityCatalogV1::adapter_capabilities_at(
  self : CapabilityCatalogV1,
  evaluated_at : String,
) -> Array[AdapterCapability] raise {
  guard catalog_timestamp_is_canonical(evaluated_at) else {
    fail("capability evaluation time must be a canonical UTC timestamp")
  }
  self.operations
  .filter(operation => {
    operation.health_checked_at <= evaluated_at &&
    operation.health_valid_until >= evaluated_at
  })
  .map(operation => AdapterCapability::{
    adapter_id: operation.adapter_id,
    product_id: operation.product_id,
    protocol: operation.protocol,
    operations: [operation.operation_ref],
    authority_classes: [operation.authority],
    input_contracts: [operation.input_schema_ref],
    output_contracts: [operation.output_schema_ref],
    claim_ceiling: operation.claim_ceiling,
    healthy: true,
    supports_cancel: operation.supports_cancel,
    supports_reconcile: operation.supports_reconcile,
  })
}

///|
pub fn decode_adapter_capabilities_at_v1(
  value : Json,
  evaluated_at : String,
) -> Array[AdapterCapability] raise {
  match value {
    Array(values) => values.map(value => validate_adapter_capability(value))
    Object(fields) =>
      match fields.get("contract_id") {
        Some(String(contract_id)) if contract_id ==
          capability_catalog_contract_v1() =>
          decode_capability_catalog_v1(value).adapter_capabilities_at(
            evaluated_at,
          )
        Some(String(contract_id)) =>
          fail("unsupported MoonFlow capability contract: \{contract_id}")
        _ => fail("MoonFlow capability object requires a supported contract_id")
      }
    _ =>
      fail(
        "MoonFlow capabilities must be a legacy JSON array or capability catalog",
      )
  }
}

///|
fn catalog_operations_for_product(
  catalog : CapabilityCatalogV1,
  product_id : String,
) -> Array[CapabilityOperationV1] {
  catalog.operations.filter(operation => operation.product_id == product_id)
}

///|
fn catalog_operation_by_ref(
  catalog : CapabilityCatalogV1,
  operation_ref : String,
) -> CapabilityOperationV1? {
  for operation in catalog.operations {
    if operation.operation_ref == operation_ref {
      return Some(operation)
    }
  }
  None
}

///|
fn catalog_operation_suggestions(
  operations : Array[CapabilityOperationV1],
  requested : String,
) -> Array[String] {
  let exact_tools = operations
    .filter(operation => operation.tool_id == requested)
    .map(operation => operation.operation_ref)
  if !exact_tools.is_empty() {
    return exact_tools
  }
  operations.map(operation => operation.operation_ref)
}

///|
fn graph_contract_reasons(
  actual : Array[String],
  expected : String,
  direction : String,
) -> Array[String] {
  if actual.length() == 1 && actual[0] == expected {
    []
  } else {
    [
      "\{direction} contracts must exactly bind the manifest schema \{expected}; got \{actual.join(", ")}",
    ]
  }
}

///|
pub fn compile_work_graph_capabilities_at_v1(
  graph : Json,
  catalog : CapabilityCatalogV1,
  evaluated_at : String,
) -> GraphCapabilityReportV1 raise {
  guard catalog_timestamp_is_canonical(evaluated_at) else {
    fail("graph capability evaluation time must be a canonical UTC timestamp")
  }
  let events = events_from_work_graph(graph)
  let graph_id = events[0].run_id
  let bindings : Array[GraphCapabilityBindingV1] = []
  let issues : Array[CapabilityConformanceIssueV1] = []
  for item in events {
    if item.kind != ItemRegistered {
      continue
    }
    let product_operations = catalog_operations_for_product(
      catalog,
      item.product_id,
    )
    let product_installed = catalog.products.any(product => {
      product.product_id == item.product_id
    })
    if !product_installed {
      catalog_add_issue(
        issues,
        "product-not-installed",
        item.work_item_id,
        "work item product \{item.product_id} is absent from the installed manifest catalog",
        suggestions=catalog.products.map(product => product.product_id),
      )
      continue
    }
    guard catalog_operation_by_ref(catalog, item.operation) is Some(operation) else {
      let unversioned = !item.operation.contains("/") ||
        !item.operation.contains("@")
      catalog_add_issue(
        issues,
        if unversioned {
          "operation-not-versioned"
        } else {
          "operation-not-conformant"
        },
        item.work_item_id,
        if unversioned {
          "operation must use the manifest-derived product/tool@pack-version identity; got \{item.operation}"
        } else {
          "versioned operation is not supplied by a conformant, healthy installed adapter: \{item.operation}"
        },
        suggestions=catalog_operation_suggestions(
          product_operations,
          item.operation,
        ),
      )
      continue
    }
    let item_issue_count = issues.length()
    if operation.health_checked_at > evaluated_at ||
      operation.health_valid_until < evaluated_at {
      catalog_add_issue(
        issues,
        "operation-health-window-invalid",
        item.work_item_id,
        "operation health window \{operation.health_checked_at}..\{operation.health_valid_until} does not cover \{evaluated_at}",
      )
    }
    if operation.product_id != item.product_id {
      catalog_add_issue(
        issues,
        "operation-owner-mismatch",
        item.work_item_id,
        "operation owner \{operation.product_id} does not match work item product \{item.product_id}",
      )
    }
    if operation.authority != item.requested_authority {
      catalog_add_issue(
        issues,
        "authority-mismatch",
        item.work_item_id,
        "work item requests \{item.requested_authority}, but manifest tool declares \{operation.authority}",
        suggestions=[operation.authority],
      )
    }
    for
      reason in graph_contract_reasons(
        item.input_contracts,
        operation.input_schema_ref,
        "input",
      ) {
      catalog_add_issue(
        issues,
        "input-schema-mismatch",
        item.work_item_id,
        reason,
        suggestions=[operation.input_schema_ref],
      )
    }
    for
      reason in graph_contract_reasons(
        item.output_contracts,
        operation.output_schema_ref,
        "output",
      ) {
      catalog_add_issue(
        issues,
        "output-schema-mismatch",
        item.work_item_id,
        reason,
        suggestions=[operation.output_schema_ref],
      )
    }
    match
      (
        claim_class_rank(item.required_claim),
        claim_class_rank(operation.claim_ceiling),
      ) {
      (Some(required), Some(ceiling)) =>
        if required > ceiling {
          catalog_add_issue(
            issues,
            "claim-ceiling-exceeded",
            item.work_item_id,
            "required claim \{item.required_claim} exceeds adapter ceiling \{operation.claim_ceiling}",
            suggestions=[operation.claim_ceiling],
          )
        }
      (None, _) =>
        catalog_add_issue(
          issues,
          "required-claim-unsupported",
          item.work_item_id,
          "work item required_claim is not a canonical claim class",
        )
      (_, None) =>
        catalog_add_issue(
          issues,
          "claim-ceiling-unsupported",
          item.work_item_id,
          "catalog operation claim ceiling is not canonical",
        )
    }
    if issues.length() == item_issue_count {
      bindings.push({
        work_item_id: item.work_item_id,
        operation_ref: operation.operation_ref,
        adapter_id: operation.adapter_id,
        input_schema_ref: operation.input_schema_ref,
        output_schema_ref: operation.output_schema_ref,
        authority: operation.authority,
        claim_ceiling: operation.claim_ceiling,
        review_required: operation.review_required,
      })
    }
  }
  {
    contract_id: graph_capability_report_contract_v1(),
    catalog_id: catalog.catalog_id,
    graph_id,
    accepted: issues.is_empty(),
    bindings,
    issues,
    catalog_issues: catalog.issues.copy(),
  }
}

///|
pub fn compile_work_graph_capabilities_v1(
  graph : Json,
  catalog : CapabilityCatalogV1,
) -> GraphCapabilityReportV1 raise {
  compile_work_graph_capabilities_at_v1(graph, catalog, catalog.compiled_at)
}

///|
pub fn conformant_events_from_work_graph_at_v1(
  graph : Json,
  catalog : CapabilityCatalogV1,
  evaluated_at : String,
) -> Array[RuntimeEvent] raise {
  let report = compile_work_graph_capabilities_at_v1(
    graph, catalog, evaluated_at,
  )
  guard report.accepted else {
    let reasons = report.issues.map(issue => "\{issue.subject}:\{issue.code}")
    fail("work graph capability compilation failed: \{reasons.join(", ")}")
  }
  events_from_work_graph(graph)
}

///|
pub fn conformant_events_from_work_graph_v1(
  graph : Json,
  catalog : CapabilityCatalogV1,
) -> Array[RuntimeEvent] raise {
  conformant_events_from_work_graph_at_v1(graph, catalog, catalog.compiled_at)
}

///|
pub fn capability_guarded_events_from_work_graph_v1(
  graph : Json,
  capabilities : Json,
  evaluated_at : String,
) -> Array[RuntimeEvent] raise {
  match capabilities {
    Object(fields) =>
      match fields.get("contract_id") {
        Some(String(contract_id)) if contract_id ==
          capability_catalog_contract_v1() =>
          conformant_events_from_work_graph_at_v1(
            graph,
            decode_capability_catalog_v1(capabilities),
            evaluated_at,
          )
        Some(String(contract_id)) =>
          fail("unsupported MoonFlow capability contract: \{contract_id}")
        _ => fail("MoonFlow capability object requires a supported contract_id")
      }
    Array(_) => events_from_work_graph(graph)
    _ =>
      fail(
        "MoonFlow capabilities must be a legacy JSON array or capability catalog",
      )
  }
}
