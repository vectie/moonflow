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
pub fn adapter_attempt_status_from_id(
  id : String,
) -> AdapterAttemptStatus raise {
  match id {
    "submitted" => Submitted
    "running" => Running
    "succeeded" => Succeeded
    "failed" => Failed
    "cancelled" => Cancelled
    "unknown" => Unknown
    _ => fail("unsupported adapter attempt status: \{id}")
  }
}

///|
pub(all) struct AdapterCapability {
  adapter_id : String
  product_id : String
  protocol : String
  operations : Array[String]
  authority_classes : Array[String]
  input_contracts : Array[String]
  output_contracts : Array[String]
  claim_ceiling : String
  healthy : Bool
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
  if self.input_contracts.is_empty() {
    issues.push("adapter input contracts are required")
  }
  if self.output_contracts.is_empty() {
    issues.push("adapter output contracts are required")
  }
  if claim_class_rank(self.claim_ceiling) is None {
    issues.push("unsupported claim ceiling: \{self.claim_ceiling}")
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
pub fn decode_adapter_capability(value : Json) -> AdapterCapability raise {
  let fields = wire_object(value, "MoonFlow adapter capability")
  {
    adapter_id: wire_string(fields, "adapter_id"),
    product_id: wire_string(fields, "product_id"),
    protocol: wire_string(fields, "protocol"),
    operations: wire_strings(fields, "operations"),
    authority_classes: wire_strings(fields, "authority_classes"),
    input_contracts: wire_strings(fields, "input_contracts"),
    output_contracts: wire_strings(fields, "output_contracts"),
    claim_ceiling: wire_string(fields, "claim_ceiling"),
    healthy: wire_bool(fields, "healthy"),
    supports_cancel: wire_bool(fields, "supports_cancel"),
    supports_reconcile: wire_bool(fields, "supports_reconcile"),
  }
}

///|
pub fn validate_adapter_capability(
  value : Json,
) -> AdapterCapability raise AdapterContractError {
  let capability = decode_adapter_capability(value) catch {
    error => raise InvalidAdapterRequest(["invalid capability: \{error}"])
  }
  let issues = capability.quality_issues()
  if !issues.is_empty() {
    raise InvalidAdapterRequest(issues)
  }
  capability
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
pub fn decode_adapter_request(value : Json) -> AdapterRequest raise {
  let fields = wire_object(value, "MoonFlow adapter request")
  {
    request_id: wire_string(fields, "request_id"),
    run_id: wire_string(fields, "run_id"),
    work_item_id: wire_string(fields, "work_item_id"),
    declaration_id: wire_string(fields, "declaration_id"),
    attempt_id: wire_string(fields, "attempt_id"),
    idempotency_key: wire_string(fields, "idempotency_key"),
    product_id: wire_string(fields, "product_id"),
    operation: wire_string(fields, "operation"),
    requested_authority: wire_string(fields, "requested_authority"),
    input_digest: wire_string(fields, "input_digest"),
    input_artifacts: wire_strings(fields, "input_artifacts", required=false),
    timeout_ms: wire_int(fields, "timeout_ms"),
    created_at: wire_string(fields, "created_at"),
  }
}

///|
pub(all) struct AdapterResult {
  result_id : String
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
  add_required_issue(issues, self.result_id, "result_id")
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
pub fn decode_adapter_result(value : Json) -> AdapterResult raise {
  let fields = wire_object(value, "MoonFlow adapter result")
  {
    result_id: wire_string(fields, "result_id"),
    request_id: wire_string(fields, "request_id"),
    attempt_id: wire_string(fields, "attempt_id"),
    idempotency_key: wire_string(fields, "idempotency_key"),
    product_id: wire_string(fields, "product_id"),
    external_job_id: wire_string(fields, "external_job_id", allow_empty=true),
    status: adapter_attempt_status_from_id(wire_string(fields, "status")),
    output_digest: wire_string(fields, "output_digest", allow_empty=true),
    output_artifacts: wire_strings(fields, "output_artifacts", required=false),
    error_kind: wire_string(fields, "error_kind", allow_empty=true),
    compensable: wire_bool(fields, "compensable"),
    recorded_at: wire_string(fields, "recorded_at"),
  }
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
  AdapterRuntimeItemUnavailable(String)
  AdapterRuntimeItemNotReady(item_id~ : String, status~ : String)
  AdapterAttemptUnavailable(String)
  AdapterReceiptConflict(String)
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

///|
pub fn adapter_submission_event(
  projection : RunProjection,
  request : AdapterRequest,
) -> RuntimeEvent raise AdapterContractError {
  let issues = request.quality_issues()
  if !issues.is_empty() {
    raise InvalidAdapterRequest(issues)
  }
  guard projection.find_item(request.work_item_id) is Some(item) else {
    raise AdapterRuntimeItemUnavailable(request.work_item_id)
  }
  let submission_event_id = "event-\{request.run_id}-attempt-\{request.attempt_id}-submitted"
  if item.request_id == request.request_id {
    require_adapter_identity(
      "attempt_id",
      item.active_attempt_id,
      request.attempt_id,
    )
    require_adapter_identity(
      "idempotency_key",
      item.idempotency_key,
      request.idempotency_key,
    )
    require_adapter_identity(
      "input_digest",
      item.input_digest,
      request.input_digest,
    )
    for previous in projection.applied_events {
      if previous.event_id == submission_event_id {
        return previous
      }
    }
    raise AdapterReceiptConflict(submission_event_id)
  }
  if item.status != Ready {
    raise AdapterRuntimeItemNotReady(
      item_id=item.work_item_id,
      status=item.status.id(),
    )
  }
  require_adapter_identity("run_id", projection.run_id, request.run_id)
  require_adapter_identity(
    "declaration_id",
    item.declaration_id,
    request.declaration_id,
  )
  require_adapter_identity("product_id", item.product_id, request.product_id)
  require_adapter_identity(
    "requested_authority",
    item.requested_authority,
    request.requested_authority,
  )
  require_adapter_identity("operation", item.operation, request.operation)
  {
    sequence: projection.last_sequence + 1,
    event_id: submission_event_id,
    run_id: request.run_id,
    work_item_id: request.work_item_id,
    kind: AttemptSubmitted,
    product_id: request.product_id,
    declaration_id: request.declaration_id,
    book_id: projection.book_id,
    declaration_revision: projection.declaration_revision,
    source_digest: projection.source_digest,
    requested_authority: request.requested_authority,
    acceptance_criteria: item.acceptance_criteria.copy(),
    operation: item.operation,
    input_contracts: item.input_contracts.copy(),
    output_contracts: item.output_contracts.copy(),
    required_claim: item.required_claim,
    input_artifacts: item.input_artifacts.copy(),
    timeout_ms: item.timeout_ms,
    request_id: request.request_id,
    result_id: "",
    attempt_id: request.attempt_id,
    idempotency_key: request.idempotency_key,
    external_job_id: "",
    attempt_status: "submitted",
    input_digest: request.input_digest,
    output_digest: "",
    output_artifacts: [],
    error_kind: "",
    compensable: false,
    depends_on: [],
    detail: request.operation,
    artifact_id: "",
    authority_id: "",
    recorded_at: request.created_at,
  }
}

///|
pub fn adapter_reconciliation_event(
  projection : RunProjection,
  result : AdapterResult,
) -> RuntimeEvent raise AdapterContractError {
  let issues = result.quality_issues()
  if !issues.is_empty() {
    raise InvalidAdapterResult(issues)
  }
  let mut found : RuntimeItem? = None
  for item in projection.items {
    if item.request_id == result.request_id {
      found = Some(item)
    }
  }
  guard found is Some(item) else {
    raise AdapterAttemptUnavailable(result.request_id)
  }
  require_adapter_identity(
    "attempt_id",
    item.active_attempt_id,
    result.attempt_id,
  )
  require_adapter_identity(
    "idempotency_key",
    item.idempotency_key,
    result.idempotency_key,
  )
  require_adapter_identity("product_id", item.product_id, result.product_id)
  let result_event_id = "event-\{projection.run_id}-adapter-result-\{result.result_id}"
  if item.result_id == result.result_id {
    let artifacts_match = result.output_artifacts.all(artifact => {
      item.artifacts.contains(artifact)
    })
    if item.attempt_status != result.status.id() ||
      item.external_job_id != result.external_job_id ||
      item.output_digest != result.output_digest ||
      item.error_kind != result.error_kind ||
      item.compensable != result.compensable ||
      !artifacts_match {
      raise AdapterReceiptConflict(result.result_id)
    }
    for previous in projection.applied_events {
      if previous.event_id == result_event_id {
        return previous
      }
    }
    raise AdapterReceiptConflict(result.result_id)
  }
  {
    sequence: projection.last_sequence + 1,
    event_id: result_event_id,
    run_id: projection.run_id,
    work_item_id: item.work_item_id,
    kind: AttemptReconciled,
    product_id: item.product_id,
    declaration_id: item.declaration_id,
    book_id: projection.book_id,
    declaration_revision: projection.declaration_revision,
    source_digest: projection.source_digest,
    requested_authority: item.requested_authority,
    acceptance_criteria: item.acceptance_criteria.copy(),
    operation: item.operation,
    input_contracts: item.input_contracts.copy(),
    output_contracts: item.output_contracts.copy(),
    required_claim: item.required_claim,
    input_artifacts: item.input_artifacts.copy(),
    timeout_ms: item.timeout_ms,
    request_id: result.request_id,
    result_id: result.result_id,
    attempt_id: result.attempt_id,
    idempotency_key: result.idempotency_key,
    external_job_id: result.external_job_id,
    attempt_status: result.status.id(),
    input_digest: item.input_digest,
    output_digest: result.output_digest,
    output_artifacts: result.output_artifacts.copy(),
    error_kind: result.error_kind,
    compensable: result.compensable,
    depends_on: [],
    detail: result.error_kind,
    artifact_id: "",
    authority_id: "",
    recorded_at: result.recorded_at,
  }
}
