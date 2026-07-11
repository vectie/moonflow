///|
pub(all) enum AdapterAttemptStatus {
  Submitted
  Running
  Succeeded
  Failed
  Cancelled
  Unknown
} derive(Debug, Eq, Compare, Hash, ToJson)

///|
pub fn AdapterAttemptStatus::id(self : AdapterAttemptStatus) -> String {
  match self {
    Submitted => "submitted"
    Running => "running"
    Succeeded => "succeeded"
    Failed => "failed"
    Cancelled => "cancelled"
    Unknown => "unknown"
  }
}

///|
pub fn AdapterAttemptStatus::is_terminal(self : AdapterAttemptStatus) -> Bool {
  match self {
    Succeeded | Failed | Cancelled => true
    _ => false
  }
}

///|
pub(all) struct AdapterCapability {
  adapter_id : String
  product_id : String
  protocol : String
  operations : Array[String]
  authority_classes : Array[String]
  supports_cancel : Bool
  supports_reconcile : Bool
} derive(Debug, Eq, ToJson)

///|
pub fn authority_class_is_canonical(authority : String) -> Bool {
  [
    "observe", "cognitive-maintenance", "sandbox-execution", "workspace-mutation",
    "external-effect", "physical-effect",
  ].contains(authority)
}

///|
fn add_required_issue(
  issues : Array[String],
  value : String,
  field : String,
) -> Unit {
  if value.trim().is_empty() {
    issues.push("\{field} is required")
  }
}

///|
pub fn AdapterCapability::quality_issues(
  self : AdapterCapability,
) -> Array[String] {
  let issues : Array[String] = []
  add_required_issue(issues, self.adapter_id, "adapter_id")
  add_required_issue(issues, self.product_id, "product_id")
  add_required_issue(issues, self.protocol, "protocol")
  if self.operations.is_empty() {
    issues.push("adapter operations are required")
  }
  if self.authority_classes.is_empty() {
    issues.push("adapter authority classes are required")
  }
  for authority in self.authority_classes {
    if !authority_class_is_canonical(authority) {
      issues.push("unsupported authority class: \{authority}")
    }
  }
  if !self.supports_reconcile {
    issues.push("production adapters must support reconciliation")
  }
  issues
}

///|
pub(all) struct AdapterRequest {
  request_id : String
  run_id : String
  work_item_id : String
  declaration_id : String
  attempt_id : String
  idempotency_key : String
  product_id : String
  operation : String
  requested_authority : String
  input_digest : String
  input_artifacts : Array[String]
  timeout_ms : Int
  created_at : String
} derive(Debug, Eq, ToJson)

///|
pub fn AdapterRequest::quality_issues(self : AdapterRequest) -> Array[String] {
  let issues : Array[String] = []
  add_required_issue(issues, self.request_id, "request_id")
  add_required_issue(issues, self.run_id, "run_id")
  add_required_issue(issues, self.work_item_id, "work_item_id")
  add_required_issue(issues, self.declaration_id, "declaration_id")
  add_required_issue(issues, self.attempt_id, "attempt_id")
  add_required_issue(issues, self.idempotency_key, "idempotency_key")
  add_required_issue(issues, self.product_id, "product_id")
  add_required_issue(issues, self.operation, "operation")
  add_required_issue(issues, self.input_digest, "input_digest")
  add_required_issue(issues, self.created_at, "created_at")
  if !authority_class_is_canonical(self.requested_authority) {
    issues.push("requested_authority must be a canonical authority class")
  }
  if self.timeout_ms <= 0 {
    issues.push("timeout_ms must be positive")
  }
  issues
}

///|
pub(all) struct AdapterResult {
  request_id : String
  attempt_id : String
  idempotency_key : String
  product_id : String
  external_job_id : String
  status : AdapterAttemptStatus
  output_digest : String
  output_artifacts : Array[String]
  error_kind : String
  compensable : Bool
  recorded_at : String
} derive(Debug, Eq, ToJson)

///|
pub fn AdapterResult::quality_issues(self : AdapterResult) -> Array[String] {
  let issues : Array[String] = []
  add_required_issue(issues, self.request_id, "request_id")
  add_required_issue(issues, self.attempt_id, "attempt_id")
  add_required_issue(issues, self.idempotency_key, "idempotency_key")
  add_required_issue(issues, self.product_id, "product_id")
  add_required_issue(issues, self.recorded_at, "recorded_at")
  if self.status == Running && self.external_job_id.trim().is_empty() {
    issues.push("running result requires external_job_id")
  }
  if self.status == Succeeded && self.output_digest.trim().is_empty() {
    issues.push("succeeded result requires output_digest")
  }
  if self.status == Failed && self.error_kind.trim().is_empty() {
    issues.push("failed result requires error_kind")
  }
  issues
}

///|
pub(all) enum ReconciliationDecision {
  Pending
  ImportSuccess
  ImportFailure
  ImportCancellation
  InvestigateUnknown
} derive(Debug, Eq, Compare, Hash, ToJson)

///|
pub(all) suberror AdapterContractError {
  InvalidAdapterRequest(Array[String])
  InvalidAdapterResult(Array[String])
  AdapterIdentityMismatch(field~ : String, expected~ : String, actual~ : String)
} derive(Debug, Eq, ToJson)

///|
fn require_adapter_identity(
  field : String,
  expected : String,
  actual : String,
) -> Unit raise AdapterContractError {
  if expected != actual {
    raise AdapterIdentityMismatch(field~, expected~, actual~)
  }
}

///|
pub fn reconcile_adapter_result(
  request : AdapterRequest,
  result : AdapterResult,
) -> ReconciliationDecision raise AdapterContractError {
  let request_issues = request.quality_issues()
  if !request_issues.is_empty() {
    raise InvalidAdapterRequest(request_issues)
  }
  let result_issues = result.quality_issues()
  if !result_issues.is_empty() {
    raise InvalidAdapterResult(result_issues)
  }
  require_adapter_identity("request_id", request.request_id, result.request_id)
  require_adapter_identity("attempt_id", request.attempt_id, result.attempt_id)
  require_adapter_identity(
    "idempotency_key",
    request.idempotency_key,
    result.idempotency_key,
  )
  require_adapter_identity("product_id", request.product_id, result.product_id)
  match result.status {
    Submitted | Running => Pending
    Succeeded => ImportSuccess
    Failed => ImportFailure
    Cancelled => ImportCancellation
    Unknown => InvestigateUnknown
  }
}
