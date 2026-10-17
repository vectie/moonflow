///|
fn capture_policy_slot(
  fields : Map[String, Json],
  key : String,
) -> String raise {
  guard fields.get(key) is Some(String(value)) else {
    fail("input capture policy requires string field " + key)
  }
  value
}

///|
/// Serialize owner-declared capture policies alongside the validated catalog.
/// Existing typed catalog APIs remain unchanged. Preparation requires this
/// explicit extension so old catalogs cannot silently change capture behavior.
pub fn compile_capability_catalog_json_v1(bundle : Json) -> Json raise {
  let catalog = compile_capability_catalog_v1(bundle)
  let output = catalog.to_json()
  let fields = wire_object(output, "capability catalog")
  let policies : Array[Json] = []
  if catalog.conformant {
    let source = wire_object(bundle, "capability source bundle")
    let declarations : Array[Json] = @json.from_json(
      source.get("adapter_declarations").unwrap(),
    )
    for operation in catalog.operations {
      let mut policy : Json = {
        "contract_id": "moonflow.input-capture-policy.v1",
        "mode": "opaque-revalidated",
        "payload_contract_id": "",
        "reference_array_field": "",
      }
      for declaration in declarations {
        let declared = wire_object(declaration, "adapter declaration")
        if wire_string(declared, "adapter_id") != operation.adapter_id {
          continue
        }
        let members : Array[Json] = @json.from_json(
          declared.get("operations").unwrap(),
        )
        for member in members {
          let owned = wire_object(member, "adapter operation")
          if wire_string(owned, "operation_id") == operation.tool_id {
            if owned.get("input_capture") is Some(value) {
              policy = value
            }
          }
        }
      }
      let declared = wire_object(policy, "input capture policy")
      let mode = wire_string(declared, "mode")
      let payload_contract_id = capture_policy_slot(
        declared, "payload_contract_id",
      )
      let reference_array_field = capture_policy_slot(
        declared, "reference_array_field",
      )
      guard wire_string(declared, "contract_id") ==
        "moonflow.input-capture-policy.v1" &&
        (
          (
            mode == "opaque-revalidated" &&
            payload_contract_id == "" &&
            reference_array_field == ""
          ) ||
          (
            mode == "reference-array-rebind" &&
            !payload_contract_id.is_empty() &&
            reference_array_field.length() > 0 &&
            reference_array_field.length() <= 64 &&
            reference_array_field.all(ch => {
              ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_'
            })
          )
        ) else {
        fail("owner-declared input capture policy is unsupported")
      }
      policies.push({
        "contract_id": "moonflow.input-capture-policy.v1",
        "product_id": operation.product_id,
        "operation_ref": operation.operation_ref,
        "input_schema_ref": operation.input_schema_ref,
        "mode": mode,
        "payload_contract_id": payload_contract_id,
        "reference_array_field": reference_array_field,
      })
    }
  }
  fields["input_capture_policies"] = policies.to_json()
  output
}

///|
/// Read the explicit capture extension and reject unknown modes, ambiguous
/// ownership, incomplete catalog coverage and unrelated schema bindings.
pub fn decode_input_capture_policies_v1(value : Json) -> Array[Json] raise {
  let catalog = decode_capability_catalog_v1(value)
  let fields = wire_object(value, "capability catalog")
  guard fields.get("input_capture_policies") is Some(Array(policies)) &&
    policies.length() == catalog.operations.length() else {
    fail(
      "Preparation requires explicit owner capture policies; recompile the capability source bundle",
    )
  }
  for operation in catalog.operations {
    let matches = policies.filter(policy => {
      let declared = wire_object(policy, "input capture policy")
      wire_string(declared, "product_id") == operation.product_id &&
      wire_string(declared, "operation_ref") == operation.operation_ref
    })
    guard matches is [policy] else {
      fail("input capture policy owner is missing or ambiguous")
    }
    let declared = wire_object(policy, "input capture policy")
    let mode = wire_string(declared, "mode")
    let field = capture_policy_slot(declared, "reference_array_field")
    let contract = capture_policy_slot(declared, "payload_contract_id")
    guard wire_string(declared, "contract_id") ==
      "moonflow.input-capture-policy.v1" &&
      wire_string(declared, "input_schema_ref") == operation.input_schema_ref &&
      (
        (mode == "opaque-revalidated" && contract == "" && field == "") ||
        (
          mode == "reference-array-rebind" &&
          !contract.is_empty() &&
          field.length() > 0 &&
          field.length() <= 64 &&
          field.all(ch => {
            ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_'
          })
        )
      ) else {
      fail(
        "input capture policy is unsupported or differs from the owner schema",
      )
    }
  }
  policies
}
