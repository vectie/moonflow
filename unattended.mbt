///|
pub(all) struct UnattendedDriver {
  adapter_id : String
  executable : String
  arguments : Array[String]
  expected_output_artifacts : Array[String]
  reviewer_id : String
  reviewer_executable : String
  reviewer_arguments : Array[String]
  review_authority_id : String
  budget_request : @pipeline.AutonomyBudgetUsage
} derive(Debug, Eq)

///|
pub(all) struct UnattendedManifest {
  contract_id : String
  gate_executable : String
  gate_arguments : Array[String]
  max_cycles : Int
  drivers : Array[UnattendedDriver]
} derive(Debug, Eq)

///|
fn decode_unattended_driver(value : Json) -> UnattendedDriver raise {
  let fields = wire_object(value, "MoonFlow unattended driver")
  guard fields.get("budget_request") is Some(budget_request) else {
    fail("MoonFlow unattended driver requires budget_request")
  }
  {
    adapter_id: wire_string(fields, "adapter_id"),
    executable: wire_string(fields, "executable"),
    arguments: wire_strings(fields, "arguments", required=false),
    expected_output_artifacts: wire_strings(fields, "expected_output_artifacts"),
    reviewer_id: wire_string(fields, "reviewer_id"),
    reviewer_executable: wire_string(fields, "reviewer_executable"),
    reviewer_arguments: wire_strings(
      fields,
      "reviewer_arguments",
      required=false,
    ),
    review_authority_id: wire_string(fields, "review_authority_id"),
    budget_request: @pipeline.decode_autonomy_budget_usage(budget_request),
  }
}

///|
pub fn decode_unattended_manifest(value : Json) -> UnattendedManifest raise {
  let fields = wire_object(value, "MoonFlow unattended manifest")
  guard fields.get("drivers") is Some(Array(drivers)) else {
    fail("MoonFlow unattended manifest requires drivers")
  }
  let manifest = {
    contract_id: wire_string(fields, "contract_id"),
    gate_executable: wire_string(fields, "gate_executable"),
    gate_arguments: wire_strings(fields, "gate_arguments", required=false),
    max_cycles: wire_int(fields, "max_cycles"),
    drivers: drivers.map(decode_unattended_driver),
  }
  let issues = manifest.quality_issues()
  if !issues.is_empty() {
    fail("invalid MoonFlow unattended manifest: \{issues.join("; ")}")
  }
  manifest
}

///|
pub fn UnattendedManifest::quality_issues(
  self : UnattendedManifest,
) -> Array[String] {
  let issues : Array[String] = []
  if self.contract_id != "moonflow.unattended-manifest.v1" {
    issues.push("unsupported unattended manifest contract")
  }
  if self.gate_executable.trim().is_empty() {
    issues.push("gate_executable is required")
  }
  if self.max_cycles < 1 || self.max_cycles > 10000 {
    issues.push("max_cycles must be between 1 and 10000")
  }
  if self.drivers.is_empty() {
    issues.push("at least one unattended driver is required")
  }
  let ids : Array[String] = []
  for driver in self.drivers {
    if ids.contains(driver.adapter_id) {
      issues.push("duplicate unattended driver: \{driver.adapter_id}")
    } else {
      ids.push(driver.adapter_id)
    }
    if driver.executable.trim().is_empty() {
      issues.push("driver executable is required: \{driver.adapter_id}")
    }
    if driver.reviewer_id == driver.adapter_id {
      issues.push("reviewer identity must be independent: \{driver.adapter_id}")
    }
    if driver.reviewer_executable.trim().is_empty() {
      issues.push("reviewer executable is required: \{driver.adapter_id}")
    }
    if driver.review_authority_id.trim().is_empty() {
      issues.push("review authority is required: \{driver.adapter_id}")
    }
    if driver.expected_output_artifacts.is_empty() {
      issues.push(
        "expected output artifacts are required: \{driver.adapter_id}",
      )
    }
    for artifact in driver.expected_output_artifacts {
      if !artifact_ref_is_workspace_relative(artifact) {
        issues.push("invalid expected output artifact: \{artifact}")
      }
    }
    for issue in driver.budget_request.quality_issues() {
      issues.push("driver \{driver.adapter_id}: \{issue}")
    }
  }
  issues
}

///|
pub fn UnattendedManifest::find_driver(
  self : UnattendedManifest,
  adapter_id : String,
) -> UnattendedDriver? {
  for driver in self.drivers {
    if driver.adapter_id == adapter_id {
      return Some(driver)
    }
  }
  None
}

///|
pub fn render_unattended_arguments(
  arguments : Array[String],
  workspace : String,
  request_artifact : String,
  result_artifact : String,
  receipt_artifact : String,
  review_artifact : String,
) -> Array[String] {
  arguments.map(argument => {
    argument
    .replace(old="{workspace}", new=workspace)
    .replace(old="{request}", new=request_artifact)
    .replace(old="{result}", new=result_artifact)
    .replace(old="{receipt}", new=receipt_artifact)
    .replace(old="{review}", new=review_artifact)
  })
}
