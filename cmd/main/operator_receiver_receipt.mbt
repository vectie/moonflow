///|
priv struct OperatorReceiverCriterion {
  criterion : String
  satisfied : Bool
  evidence_refs : Array[String]
  note : String
}

///|
priv struct OperatorReceiverAuthority {
  requested_authority : String
  decision : String
  receipt_ref : String
}

///|
priv struct OperatorReceiverReview {
  review_id : String
  decision : String
  reviewer_id : String
  review_authority_id : String
  criteria : Array[OperatorReceiverCriterion]
}

///|
priv struct OperatorReceiverReceiptInput {
  receipt_id : String
  handoff_token : String
  handoff_digest : String
  run_id : String
  work_item_id : String
  declaration_id : String
  product_id : String
  operation : String
  request_id : String
  attempt_id : String
  idempotency_key : String
  decision : String
  output_contracts : Array[String]
  output_artifacts : Array[String]
  output_digest : String
  authority : OperatorReceiverAuthority
  review : OperatorReceiverReview
  owner_id : String
  recorded_at : String
  json : Json
}

///|
fn receiver_strict_object(
  value : Json,
  allowed : Array[String],
) -> Map[String, Json] raise {
  guard value is Object(fields) else {
    fail("receiver value must be an object")
  }
  for key, _ in fields {
    if !allowed.contains(key) {
      fail("unsupported receiver field: \{key}")
    }
  }
  fields
}

///|
fn receiver_string(
  fields : Map[String, Json],
  key : String,
  allow_empty? : Bool = false,
) -> String raise {
  guard fields.get(key) is Some(String(value)) else {
    fail("receiver field must be text: \{key}")
  }
  if !allow_empty && value.trim().is_empty() {
    fail("receiver field is required: \{key}")
  }
  value
}

///|
fn receiver_bool(fields : Map[String, Json], key : String) -> Bool raise {
  match fields.get(key) {
    Some(True) => true
    Some(False) => false
    _ => fail("receiver field must be boolean: \{key}")
  }
}

///|
fn receiver_strings(
  fields : Map[String, Json],
  key : String,
) -> Array[String] raise {
  guard fields.get(key) is Some(Array(values)) else {
    fail("receiver field must be an array: \{key}")
  }
  let result : Array[String] = []
  for value in values {
    guard value is String(text) && !text.trim().is_empty() else {
      fail("receiver array must contain non-empty text: \{key}")
    }
    if result.contains(text) {
      fail("receiver array contains a duplicate: \{key}")
    }
    result.push(text)
  }
  result
}

///|
fn decode_operator_receiver_receipt(
  value : Json,
) -> OperatorReceiverReceiptInput raise {
  let fields = receiver_strict_object(value, [
    "contract_id", "contract_version", "receipt_id", "handoff_token", "handoff_digest",
    "run_id", "work_item_id", "declaration_id", "product_id", "operation", "request_id",
    "attempt_id", "idempotency_key", "decision", "output_contracts", "output_artifacts",
    "output_digest", "authority", "review", "owner_id", "recorded_at",
  ])
  if receiver_string(fields, "contract_id") != "moonflow.receiver-receipt.v1" ||
    receiver_string(fields, "contract_version") != "1.0.0" {
    fail("unsupported MoonFlow receiver receipt contract")
  }
  guard fields.get("authority") is Some(authority_json) &&
    fields.get("review") is Some(review_json) else {
    fail("receiver authority and review are required")
  }
  let authority_fields = receiver_strict_object(authority_json, [
    "requested_authority", "decision", "receipt_ref",
  ])
  let authority : OperatorReceiverAuthority = {
    requested_authority: receiver_string(
      authority_fields, "requested_authority",
    ),
    decision: receiver_string(authority_fields, "decision"),
    receipt_ref: receiver_string(
      authority_fields,
      "receipt_ref",
      allow_empty=true,
    ),
  }
  let review_fields = receiver_strict_object(review_json, [
    "review_id", "decision", "reviewer_id", "review_authority_id", "criteria",
  ])
  guard review_fields.get("criteria") is Some(Array(criteria_json)) else {
    fail("receiver review criteria must be an array")
  }
  let criteria : Array[OperatorReceiverCriterion] = []
  for criterion_json in criteria_json {
    let criterion_fields = receiver_strict_object(criterion_json, [
      "criterion", "satisfied", "evidence_refs", "note",
    ])
    criteria.push({
      criterion: receiver_string(criterion_fields, "criterion"),
      satisfied: receiver_bool(criterion_fields, "satisfied"),
      evidence_refs: receiver_strings(criterion_fields, "evidence_refs"),
      note: receiver_string(criterion_fields, "note"),
    })
  }
  {
    receipt_id: receiver_string(fields, "receipt_id"),
    handoff_token: receiver_string(fields, "handoff_token"),
    handoff_digest: receiver_string(fields, "handoff_digest"),
    run_id: receiver_string(fields, "run_id"),
    work_item_id: receiver_string(fields, "work_item_id"),
    declaration_id: receiver_string(fields, "declaration_id"),
    product_id: receiver_string(fields, "product_id"),
    operation: receiver_string(fields, "operation"),
    request_id: receiver_string(fields, "request_id"),
    attempt_id: receiver_string(fields, "attempt_id"),
    idempotency_key: receiver_string(fields, "idempotency_key"),
    decision: receiver_string(fields, "decision"),
    output_contracts: receiver_strings(fields, "output_contracts"),
    output_artifacts: receiver_strings(fields, "output_artifacts"),
    output_digest: receiver_string(fields, "output_digest", allow_empty=true),
    authority,
    review: {
      review_id: receiver_string(review_fields, "review_id"),
      decision: receiver_string(review_fields, "decision"),
      reviewer_id: receiver_string(review_fields, "reviewer_id"),
      review_authority_id: receiver_string(review_fields, "review_authority_id"),
      criteria,
    },
    owner_id: receiver_string(fields, "owner_id"),
    recorded_at: receiver_string(fields, "recorded_at"),
    json: value,
  }
}

///|
fn operator_payload_object(
  handoff : OperatorPublishedHandoff,
  key : String,
) -> Map[String, Json] raise {
  guard handoff.payload is Object(payload) &&
    payload.get(key) is Some(Object(fields)) else {
    fail("operator handoff payload is malformed: \{key}")
  }
  fields
}

///|
fn operator_payload_pack_id(handoff : OperatorPublishedHandoff) -> String raise {
  receiver_string(operator_payload_object(handoff, "app_entrypoint"), "pack_id")
}

///|
fn operator_payload_input_digest(
  handoff : OperatorPublishedHandoff,
) -> String raise {
  receiver_string(operator_payload_object(handoff, "inputs"), "digest")
}

///|
async fn load_operator_handoff_for_token(
  directory : String,
  run_id : String,
  token : String,
) -> OperatorPublishedHandoff {
  if !operator_token_is_safe(token) {
    fail("invalid MoonFlow receiver token")
  }
  let catalog = read_json(directory + "/operator-actions.json")
  guard catalog is Object(fields) &&
    operator_json_string(fields, "contract_id")
    is Some("moonflow.operator-actions.v2") &&
    operator_json_string(fields, "contract_version") is Some("2.1.0") &&
    operator_json_string(fields, "run_id") is Some(bound_run_id) &&
    bound_run_id == run_id &&
    fields.get("actions") is Some(Array(actions)) else {
    fail("MoonFlow receiver action catalog is unavailable")
  }
  let mut found : OperatorPublishedHandoff? = None
  for value in actions {
    guard value is Object(action) &&
      operator_json_string(action, "action_id") is Some(action_id) &&
      operator_json_string(action, "handoff_ref") is Some(handoff_ref) &&
      action.get("receiver") is Some(Object(receiver)) &&
      operator_json_string(receiver, "handoff_token") is Some(candidate) else {
      continue
    }
    if candidate != token {
      continue
    }
    if found is Some(_) ||
      !handoff_ref.has_prefix("operator-handoffs/") ||
      handoff_ref.contains("..") ||
      handoff_ref.contains("\\") {
      fail("MoonFlow receiver token is ambiguous or untrusted")
    }
    let decoded = decode_operator_published_handoff(
      read_json(directory + "/" + handoff_ref),
      action_id,
      handoff_ref,
      run_id,
    )
    guard decoded is Some(handoff) && handoff.token == token else {
      fail("MoonFlow receiver handoff binding mismatch")
    }
    found = Some(handoff)
  }
  guard found is Some(handoff) else {
    fail("MoonFlow receiver handoff not found")
  }
  handoff
}

///|
fn receiver_require_identity(
  field : String,
  expected : String,
  actual : String,
) -> Unit raise {
  if expected != actual {
    fail(
      "MoonFlow receiver identity mismatch for \{field}: expected \{expected}, got \{actual}",
    )
  }
}

///|
async fn validate_operator_receiver_receipt(
  workspace : String,
  projection : @moonflow.RunProjection,
  item : @moonflow.RuntimeItem,
  handoff : OperatorPublishedHandoff,
  receipt : OperatorReceiverReceiptInput,
) -> Unit {
  ignore(safe_id(receipt.receipt_id, "receipt_id"))
  ignore(safe_id(receipt.review.review_id, "review_id"))
  if receipt.decision != "accepted" && receipt.decision != "denied" {
    fail("receiver decision must be accepted or denied")
  }
  receiver_require_identity(
    "handoff_token",
    handoff.token,
    receipt.handoff_token,
  )
  receiver_require_identity(
    "handoff_digest",
    handoff.digest,
    receipt.handoff_digest,
  )
  receiver_require_identity("run_id", projection.run_id, receipt.run_id)
  receiver_require_identity(
    "work_item_id",
    item.work_item_id,
    receipt.work_item_id,
  )
  receiver_require_identity(
    "declaration_id",
    item.declaration_id,
    receipt.declaration_id,
  )
  receiver_require_identity("product_id", item.product_id, receipt.product_id)
  receiver_require_identity("operation", item.operation, receipt.operation)
  receiver_require_identity(
    "request_id",
    handoff.request_id,
    receipt.request_id,
  )
  receiver_require_identity(
    "attempt_id",
    handoff.attempt_id,
    receipt.attempt_id,
  )
  receiver_require_identity(
    "idempotency_key",
    handoff.idempotency_key,
    receipt.idempotency_key,
  )
  receiver_require_identity(
    "requested_authority",
    item.requested_authority,
    receipt.authority.requested_authority,
  )
  if receipt.output_contracts != item.output_contracts {
    fail("receiver output contracts do not match the declared work item")
  }
  if receipt.review.criteria.length() != item.acceptance_criteria.length() {
    fail("receiver review must cover every declared acceptance criterion")
  }
  for index in 0..<item.acceptance_criteria.length() {
    let criterion = receipt.review.criteria[index]
    if criterion.criterion != item.acceptance_criteria[index] {
      fail("receiver review criteria changed order or text")
    }
    for evidence_ref in criterion.evidence_refs {
      if !receipt.output_artifacts.contains(evidence_ref) {
        fail("receiver criterion evidence is not an output artifact")
      }
      validate_artifact_ref(workspace, evidence_ref)
    }
  }
  let current_input_digest = declared_input_digest(
    workspace,
    item.input_artifacts,
  )
  receiver_require_identity(
    "input_digest",
    operator_payload_input_digest(handoff),
    current_input_digest,
  )
  if !operator_payload_matches_item(
      handoff,
      projection,
      item,
      Some(current_input_digest),
      operator_payload_pack_id(handoff),
    ) {
    fail("receiver handoff no longer matches the current run projection")
  }
  for artifact_ref in receipt.output_artifacts {
    validate_artifact_ref(workspace, artifact_ref)
  }
  if receipt.decision == "accepted" {
    if receipt.output_artifacts.is_empty() ||
      receipt.output_digest.trim().is_empty() ||
      receipt.authority.decision != "granted" ||
      receipt.authority.receipt_ref.trim().is_empty() ||
      !receipt.output_artifacts.contains(receipt.authority.receipt_ref) ||
      receipt.review.decision != "accepted" ||
      receipt.review.criteria.any(criterion => {
        !criterion.satisfied || criterion.evidence_refs.is_empty()
      }) {
      fail(
        "accepted receiver receipts require outputs, granted authority, and complete review evidence",
      )
    }
    validate_artifact_ref(workspace, receipt.authority.receipt_ref)
    let actual_output_digest = declared_input_digest(
      workspace,
      receipt.output_artifacts,
    )
    receiver_require_identity(
      "output_digest",
      actual_output_digest,
      receipt.output_digest,
    )
  } else {
    if !["granted", "denied"].contains(receipt.authority.decision) ||
      !["accepted", "rejected"].contains(receipt.review.decision) ||
      (
        receipt.authority.decision != "denied" &&
        receipt.review.decision != "rejected"
      ) ||
      (
        receipt.review.decision == "rejected" &&
        receipt.review.criteria.all(criterion => criterion.satisfied)
      ) {
      fail("denied receiver receipt lacks a bound denial decision")
    }
    if receipt.authority.receipt_ref != "" {
      validate_artifact_ref(workspace, receipt.authority.receipt_ref)
    }
  }
}

///|
fn operator_receiver_record_relative(run_id : String, token : String) -> String {
  ".moonsuite/products/moonflow/runs/" +
  run_id +
  "/operator-receipts/" +
  token +
  ".json"
}

///|
fn operator_receiver_record_json(
  run_id : String,
  handoff : OperatorPublishedHandoff,
  receipt : OperatorReceiverReceiptInput,
  stage : String,
) -> Json {
  let receipt_ref = operator_receiver_record_relative(run_id, handoff.token)
  let receipt_digest = "sha256:" +
    sha256_hex(@utf8.encode(receipt.json.stringify()))
  {
    "contract_id": "moonflow.receiver-receipt-record.v1",
    "contract_version": "1.0.0",
    "stage": stage,
    "handoff_token": handoff.token,
    "handoff_digest": handoff.digest,
    "decision": receipt.decision,
    "receipt_id": receipt.receipt_id,
    "receipt_ref": receipt_ref,
    "receipt_digest": receipt_digest,
    "recorded_at": receipt.recorded_at,
    "submission": receipt.json,
  }
}

///|
fn receiver_record_stage(record : Json) -> String {
  match record {
    Object(fields) =>
      match fields.get("stage") {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn operator_receiver_status_json(
  run_id : String,
  handoff : OperatorPublishedHandoff,
  record : Json?,
  projection : @moonflow.RunProjection,
) -> Json {
  let (status, stage, receipt_ref, receipt_digest, recorded_at) = match record {
    Some(Object(fields)) =>
      (
        operator_json_string(fields, "decision").unwrap_or("stale"),
        operator_json_string(fields, "stage").unwrap_or("stale"),
        operator_json_string(fields, "receipt_ref").unwrap_or(""),
        operator_json_string(fields, "receipt_digest").unwrap_or(""),
        operator_json_string(fields, "recorded_at").unwrap_or(""),
      )
    _ => ("pending", "published", "", "", "")
  }
  let item_status = match handoff.payload {
    Object(payload) =>
      match payload.get("run") {
        Some(Object(run)) =>
          match operator_json_string(run, "work_item_id") {
            Some(item_id) =>
              match projection.find_item(item_id) {
                Some(item) => item.status.id()
                None => "missing"
              }
            None => "missing"
          }
        _ => "missing"
      }
    _ => "missing"
  }
  let endpoint = operator_receiver_path(run_id, handoff.token)
  {
    "contract_id": "moonflow.receiver-status.v1",
    "contract_version": "1.0.0",
    "run_id": run_id,
    "handoff_token": handoff.token,
    "handoff_digest": handoff.digest,
    "status": status,
    "stage": stage,
    "work_item_status": item_status,
    "run_outcome": projection.outcome,
    "projection_sequence": projection.last_sequence,
    "receipt_ref": receipt_ref,
    "receipt_digest": receipt_digest,
    "receipt_recorded_at": recorded_at,
    "intake_path": endpoint,
    "status_path": endpoint + "/status",
    "receipt_path": endpoint + "/receipt",
    "return_path": "/?activity=flow",
  }
}

///|
fn receiver_denial_detail(receipt : OperatorReceiverReceiptInput) -> String {
  let notes = receipt.review.criteria
    .filter(criterion => !criterion.satisfied)
    .map(criterion => criterion.criterion + ": " + criterion.note)
  if notes.is_empty() {
    "Receiver denied receipt " + receipt.receipt_id
  } else {
    "Receiver denied receipt " + receipt.receipt_id + ": " + notes.join("; ")
  }
}

///|
async fn apply_operator_receiver_record(
  workspace : String,
  run_id : String,
  handoff : OperatorPublishedHandoff,
  receipt : OperatorReceiverReceiptInput,
  record_path : String,
) -> @moonflow.RunProjection {
  let events = load_events(workspace, run_id)
  let mut projection = @moonflow.replay(run_id, events)
  guard projection.find_item(receipt.work_item_id) is Some(item) else {
    fail("receiver work item no longer exists")
  }
  validate_operator_receiver_receipt(
    workspace, projection, item, handoff, receipt,
  )
  let receipt_ref = operator_receiver_record_relative(run_id, handoff.token)
  if receipt.decision == "accepted" && item.status == @moonflow.Accepted {
    receiver_require_identity(
      "accepted_attempt_id",
      handoff.attempt_id,
      item.active_attempt_id,
    )
    receiver_require_identity(
      "accepted_result_id",
      "receiver-result-" + receipt.receipt_id,
      item.result_id,
    )
    receiver_require_identity(
      "accepted_review_id",
      receipt.review.review_id,
      item.acceptance_review_id,
    )
    receiver_require_identity(
      "accepted_receipt_ref",
      receipt_ref,
      item.acceptance_review_artifact,
    )
  } else if receipt.decision == "denied" && item.status == @moonflow.Failed {
    let event_id = "event-\{run_id}-receiver-denied-\{receipt.receipt_id}"
    if !projection.applied_event_ids.contains(event_id) {
      fail("receiver denial conflicts with the terminal work item")
    }
  } else {
    if item.status != @moonflow.Ready {
      fail("receiver receipt is stale for work item state \{item.status.id()}")
    }
    if receipt.decision == "accepted" {
      let request : @moonflow.AdapterRequest = {
        request_id: handoff.request_id,
        run_id,
        book_id: projection.book_id,
        work_item_id: item.work_item_id,
        declaration_id: item.declaration_id,
        attempt_id: handoff.attempt_id,
        idempotency_key: handoff.idempotency_key,
        product_id: item.product_id,
        operation: item.operation,
        requested_authority: item.requested_authority,
        acceptance_criteria: item.acceptance_criteria.copy(),
        input_contracts: item.input_contracts.copy(),
        output_contracts: item.output_contracts.copy(),
        required_claim: item.required_claim,
        input_digest: operator_payload_input_digest(handoff),
        input_artifacts: item.input_artifacts.copy(),
        timeout_ms: item.timeout_ms,
        created_at: receipt.recorded_at,
      }
      events.push(@moonflow.adapter_submission_event(projection, request))
      projection = @moonflow.replay(run_id, events)
      let result : @moonflow.AdapterResult = {
        result_id: "receiver-result-" + receipt.receipt_id,
        request_id: handoff.request_id,
        attempt_id: handoff.attempt_id,
        idempotency_key: handoff.idempotency_key,
        product_id: item.product_id,
        external_job_id: receipt.receipt_id,
        status: @moonflow.Succeeded,
        output_digest: receipt.output_digest,
        output_artifacts: receipt.output_artifacts.copy(),
        error_kind: "",
        compensable: false,
        recorded_at: receipt.recorded_at,
      }
      events.push(@moonflow.adapter_reconciliation_event(projection, result))
      projection = @moonflow.replay(run_id, events)
      let review : @moonflow.AcceptanceReviewReceipt = {
        contract_id: "moonflow.acceptance-review.v1",
        review_id: receipt.review.review_id,
        run_id,
        work_item_id: item.work_item_id,
        declaration_id: item.declaration_id,
        result_id: result.result_id,
        attempt_id: handoff.attempt_id,
        output_digest: receipt.output_digest,
        decision: "accepted",
        criteria: [
          for criterion in receipt.review.criteria => {
            {
              criterion: criterion.criterion,
              satisfied: criterion.satisfied,
              evidence_refs: criterion.evidence_refs.copy(),
              note: criterion.note,
            }
          }
        ],
        reviewer_id: receipt.review.reviewer_id,
        review_authority_id: receipt.review.review_authority_id,
        receipt_artifact: receipt_ref,
        recorded_at: receipt.recorded_at,
      }
      events.push(@moonflow.acceptance_review_event(projection, review))
      projection = @moonflow.replay(run_id, events)
      for ready in @moonflow.ready_events(projection, receipt.recorded_at) {
        events.push(ready)
      }
    } else {
      events.push({
        sequence: projection.last_sequence + 1,
        event_id: "event-\{run_id}-receiver-denied-\{receipt.receipt_id}",
        run_id,
        work_item_id: item.work_item_id,
        kind: @moonflow.ItemFailed,
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
        request_id: handoff.request_id,
        result_id: "receiver-denied-" + receipt.receipt_id,
        attempt_id: handoff.attempt_id,
        idempotency_key: handoff.idempotency_key,
        external_job_id: receipt.receipt_id,
        attempt_status: "failed",
        input_digest: operator_payload_input_digest(handoff),
        output_digest: receipt.output_digest,
        output_artifacts: receipt.output_artifacts.copy(),
        error_kind: "receiver-denied",
        compensable: false,
        depends_on: [],
        detail: receiver_denial_detail(receipt),
        artifact_id: receipt_ref,
        authority_id: receipt.review.review_authority_id,
        recorded_at: receipt.recorded_at,
      })
    }
    projection = persist_run(workspace, run_id, events)
  }
  let applied_record = operator_receiver_record_json(
    run_id, handoff, receipt, "applied",
  )
  write_json(record_path, applied_record)
  // Refresh the action catalog after the journal stage becomes durable.
  publish_operator_handoffs(workspace, run_dir(workspace, run_id), projection)
  projection
}

///|
async fn receive_operator_receipt(
  workspace : String,
  run_id : String,
  token : String,
  submission_ref : String,
) -> Unit {
  validate_artifact_ref(workspace, submission_ref)
  let directory = run_dir(workspace, run_id)
  let handoff = load_operator_handoff_for_token(directory, run_id, token)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let receipt = decode_operator_receiver_receipt(
    read_json(root + "/" + submission_ref),
  )
  let events = load_events(workspace, run_id)
  let projection = @moonflow.replay(run_id, events)
  guard projection.find_item(receipt.work_item_id) is Some(item) else {
    fail("receiver work item does not exist")
  }
  validate_operator_receiver_receipt(
    workspace, projection, item, handoff, receipt,
  )
  let record_dir = directory + "/operator-receipts"
  ensure_directory(record_dir)
  let record_path = record_dir + "/" + token + ".json"
  let received = operator_receiver_record_json(
    run_id, handoff, receipt, "received",
  )
  if @fs.exists(record_path) {
    let existing = read_json(record_path)
    let received_digest = match received {
      Object(fields) => operator_json_string(fields, "receipt_digest")
      _ => None
    }
    guard existing is Object(existing_fields) &&
      operator_json_string(existing_fields, "receipt_digest") == received_digest &&
      existing_fields.get("submission") == Some(receipt.json) else {
      fail("receiver token already has a different receipt")
    }
  } else {
    write_json(record_path, received)
  }
  let updated = apply_operator_receiver_record(
    workspace, run_id, handoff, receipt, record_path,
  )
  println(
    operator_receiver_status_json(
      run_id,
      handoff,
      Some(read_json(record_path)),
      updated,
    ).stringify(indent=2),
  )
}

///|
async fn recover_operator_receipts(workspace : String, run_id : String) -> Unit {
  let directory = run_dir(workspace, run_id)
  let record_dir = directory + "/operator-receipts"
  if !@fs.exists(record_dir) {
    println(
      (
        {
          "contract_id": "moonflow.receiver-recovery.v1",
          "run_id": run_id,
          "recovered": 0,
        } : Json).stringify(),
    )
    return
  }
  let mut recovered = 0
  for name in @fs.readdir(record_dir) {
    if !name.has_suffix(".json") {
      continue
    }
    let token = name[0:name.length() - 5].to_owned()
    if !operator_token_is_safe(token) {
      fail("untrusted receiver journal filename")
    }
    let record_path = record_dir + "/" + name
    let record = read_json(record_path)
    if receiver_record_stage(record) != "received" {
      continue
    }
    guard record is Object(fields) &&
      fields.get("submission") is Some(submission) else {
      fail("receiver journal is malformed")
    }
    let handoff = load_operator_handoff_for_token(directory, run_id, token)
    let receipt = decode_operator_receiver_receipt(submission)
    ignore(
      apply_operator_receiver_record(
        workspace, run_id, handoff, receipt, record_path,
      ),
    )
    recovered += 1
  }
  println(
    (
      {
        "contract_id": "moonflow.receiver-recovery.v1",
        "run_id": run_id,
        "recovered": recovered,
      } : Json).stringify(),
  )
}

///|
async fn show_operator_receiver_status(
  workspace : String,
  run_id : String,
  token : String,
) -> Unit {
  let directory = run_dir(workspace, run_id)
  let handoff = load_operator_handoff_for_token(directory, run_id, token)
  let projection = @moonflow.replay(run_id, load_events(workspace, run_id))
  let record_path = directory + "/operator-receipts/" + token + ".json"
  let record = if @fs.exists(record_path) {
    Some(read_json(record_path))
  } else {
    None
  }
  println(
    operator_receiver_status_json(run_id, handoff, record, projection).stringify(
      indent=2,
    ),
  )
}
