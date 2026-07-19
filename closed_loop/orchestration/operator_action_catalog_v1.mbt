///|
pub(all) enum OperatorActionKindV1 {
  OperatorActionCommandV1
  OperatorActionScheduleRegistrationV1
  OperatorActionFinalLearningPersistV1
} derive(Eq, Debug)

///|
fn OperatorActionKindV1::wire(self : OperatorActionKindV1) -> String {
  match self {
    OperatorActionCommandV1 => "operator-command"
    OperatorActionScheduleRegistrationV1 => "schedule-registration"
    OperatorActionFinalLearningPersistV1 => "final-learning-persist"
  }
}

///|
fn operator_action_kind_from_wire_v1(
  value : String,
) -> OperatorActionKindV1 raise OrchestrationError {
  match value {
    "operator-command" => OperatorActionCommandV1
    "schedule-registration" => OperatorActionScheduleRegistrationV1
    "final-learning-persist" => OperatorActionFinalLearningPersistV1
    _ => raise MalformedInput(field="operator_action_kind_v1")
  }
}

///|
fn require_operator_action_id_v1(
  value : String,
) -> Unit raise OrchestrationError {
  if value.is_empty() ||
    value.length() > 96 ||
    !value
    .iter()
    .all(char => {
      char.is_ascii_alphabetic() ||
      char.is_ascii_digit() ||
      char == '-' ||
      char == '_'
    }) {
    raise MalformedInput(field="operator_action_id_v1")
  }
}

///|
fn require_operator_action_relative_path_v1(
  value : String,
  field : String,
) -> Unit raise OrchestrationError {
  let segments = value.split("/")
  if value.is_empty() ||
    value.has_prefix("/") ||
    value.has_suffix("/") ||
    value.contains("\\") ||
    value.contains("//") ||
    value.iter().any(char => char.is_control()) ||
    segments.any(segment => {
      segment.is_empty() || segment == "." || segment == ".."
    }) {
    raise MalformedInput(field~)
  }
}

///|
pub struct OperatorActionDescriptorV1 {
  action_id : String
  label : String
  summary : String
  action_kind : OperatorActionKindV1
  enabled : Bool
  disabled_reason : String?
  host_config_relative_path : String
  handoff_relative_path : String
}

///|
pub struct OperatorActionCatalogMaterializationV1 {
  run_id : String
  operator_projection_digest : @contracts.ContentDigest
  actions : ReadOnlyArray[OperatorActionDescriptorV1]
  published_json : Json
  published_canonical_json : String
  published_bytes : Bytes
  published_digest : @contracts.ContentDigest
  source_json : Json
  source_canonical_json : String
  digest : @contracts.ContentDigest
}

///|
fn decode_operator_action_descriptor_v1(
  value : Json,
) -> OperatorActionDescriptorV1 raise OrchestrationError {
  let fields = handoff_json_object_v1(value, "operator_action_descriptor", [
    "action_id", "label", "summary", "action_kind", "enabled", "disabled_reason",
    "host_config", "handoff_template",
  ])
  let action_id = handoff_json_string_v1(fields, "action_id")
  require_operator_action_id_v1(action_id)
  guard fields.get("enabled") is Some(enabled_json) else {
    raise MalformedInput(field="operator_action_enabled_v1")
  }
  let enabled : Bool = @json.from_json(enabled_json) catch {
    _ => raise MalformedInput(field="operator_action_enabled_v1")
  }
  let disabled_reason = handoff_json_optional_string_v1(
    fields, "disabled_reason",
  )
  if (enabled && disabled_reason is Some(_)) ||
    (
      !enabled &&
      !["stale", "rejected", "unavailable"].contains(
        disabled_reason.unwrap_or(""),
      )
    ) {
    raise MalformedInput(field="operator_action_disabled_reason_v1")
  }
  let host_config_relative_path = handoff_json_string_v1(fields, "host_config")
  let handoff_relative_path = handoff_json_string_v1(fields, "handoff_template")
  require_operator_action_relative_path_v1(
    host_config_relative_path, "operator_action_host_config_v1",
  )
  require_operator_action_relative_path_v1(
    handoff_relative_path, "operator_action_handoff_v1",
  )
  {
    action_id,
    label: handoff_json_string_v1(fields, "label"),
    summary: handoff_json_string_v1(fields, "summary"),
    action_kind: operator_action_kind_from_wire_v1(
      handoff_json_string_v1(fields, "action_kind"),
    ),
    enabled,
    disabled_reason,
    host_config_relative_path,
    handoff_relative_path,
  }
}

///|
fn operator_action_published_json_v1(
  value : OperatorActionDescriptorV1,
) -> Json {
  {
    "action_id": value.action_id,
    "label": value.label,
    "summary": value.summary,
    "status": if value.enabled {
      "available"
    } else {
      value.disabled_reason.unwrap_or("unavailable")
    },
    "enabled": value.enabled,
    "host_config": value.host_config_relative_path,
    "handoff_template": value.handoff_relative_path,
  }
}

///|
pub fn decode_operator_action_catalog_materialization_v1(
  value : Json,
) -> OperatorActionCatalogMaterializationV1 raise OrchestrationError {
  let fields = handoff_json_object_v1(
    value,
    "operator_action_catalog_materialization",
    [
      "contract_id", "contract_version", "run_id", "operator_projection_digest",
      "actions",
    ],
  )
  let version = handoff_json_string_v1(fields, "contract_version")
  if handoff_json_string_v1(fields, "contract_id") !=
    "moonflow.operator-actions-materialization.v1" ||
    version != "1.0.0" {
    raise UnsupportedVersion(
      field="operator_action_catalog_materialization_v1",
      version~,
    )
  }
  let run_id = handoff_json_string_v1(fields, "run_id")
  require_text(run_id, "operator_action_catalog_run_id_v1")
  require_operator_action_id_v1(run_id)
  let operator_projection_digest = @contracts.ContentDigest::parse(
    handoff_json_string_v1(fields, "operator_projection_digest"),
  ) catch {
    _ => raise MalformedInput(field="operator_projection_digest_v1")
  }
  guard fields.get("actions") is Some(Array(values)) else {
    raise MalformedInput(field="operator_action_catalog_actions_v1")
  }
  let actions : Array[OperatorActionDescriptorV1] = []
  for value in values {
    let action = decode_operator_action_descriptor_v1(value)
    if actions.any(existing => existing.action_id == action.action_id) {
      raise MalformedInput(field="operator_action_duplicate_id_v1")
    }
    actions.push(action)
  }
  let published_json : Json = {
    "contract_id": "moonflow.operator-actions.v1",
    "contract_version": "1.0.0",
    "run_id": run_id,
    "actions": [
      for action in actions => operator_action_published_json_v1(action)
    ],
  }
  let published_canonical_json = published_json.stringify()
  let published_bytes = @utf8.encode(published_canonical_json)
  let source_canonical_json = value.stringify()
  {
    run_id,
    operator_projection_digest,
    actions: ReadOnlyArray::from_array(actions),
    published_json,
    published_canonical_json,
    published_bytes,
    published_digest: @contracts.sha256_digest(published_bytes),
    source_json: value,
    source_canonical_json,
    digest: @contracts.sha256_digest(@utf8.encode(source_canonical_json)),
  }
}

///|
pub fn OperatorActionCatalogMaterializationV1::run_id(
  self : OperatorActionCatalogMaterializationV1,
) -> String {
  self.run_id
}

///|
pub fn OperatorActionCatalogMaterializationV1::operator_projection_digest(
  self : OperatorActionCatalogMaterializationV1,
) -> @contracts.ContentDigest {
  self.operator_projection_digest
}

///|
pub fn OperatorActionCatalogMaterializationV1::actions(
  self : OperatorActionCatalogMaterializationV1,
) -> ReadOnlyArray[OperatorActionDescriptorV1] {
  self.actions
}

///|
pub fn OperatorActionCatalogMaterializationV1::bytes(
  self : OperatorActionCatalogMaterializationV1,
) -> Bytes {
  self.published_bytes
}

///|
pub fn OperatorActionCatalogMaterializationV1::digest(
  self : OperatorActionCatalogMaterializationV1,
) -> @contracts.ContentDigest {
  self.published_digest
}

///|
pub fn OperatorActionDescriptorV1::action_kind(
  self : OperatorActionDescriptorV1,
) -> OperatorActionKindV1 {
  self.action_kind
}

///|
pub fn OperatorActionDescriptorV1::host_config_relative_path(
  self : OperatorActionDescriptorV1,
) -> String {
  self.host_config_relative_path
}

///|
pub fn OperatorActionDescriptorV1::handoff_relative_path(
  self : OperatorActionDescriptorV1,
) -> String {
  self.handoff_relative_path
}
