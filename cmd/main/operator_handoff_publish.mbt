///|
fn operator_capability_snapshot_name() -> String {
  "operator-capability-catalog.json"
}

///|
fn operator_action_id(run_id : String, work_item_id : String) -> String {
  "open-" +
  sha256_hex(@utf8.encode(run_id + "\n" + work_item_id))[0:24].to_owned()
}

///|
fn operator_capability_for_item(
  catalog : @moonflow.CapabilityCatalogV1?,
  item : @moonflow.RuntimeItem,
) -> @moonflow.CapabilityOperationV1? {
  guard catalog is Some(value) else { return None }
  for operation in value.operations {
    if operation.operation_ref == item.operation &&
      operation.product_id == item.product_id {
      return Some(operation)
    }
  }
  None
}

///|
fn operator_entrypoint_json(pack_id : String) -> Json {
  {
    "kind": "pack-manifest",
    "pack_id": pack_id,
    "entrypoint_id": "",
    "path": "/pack-apps/" + pack_id + "/",
    "fallback_path": "",
  }
}

///|
fn operator_pack_id(
  item : @moonflow.RuntimeItem,
  capability : @moonflow.CapabilityOperationV1?,
) -> String {
  match capability {
    Some(value) => value.pack_id
    None => item.product_id
  }
}

///|
fn operator_capability_status(
  capability : @moonflow.CapabilityOperationV1?,
) -> String {
  if capability is Some(_) {
    "catalog-bound"
  } else {
    "not-declared"
  }
}

///|
fn operator_review_status(
  capability : @moonflow.CapabilityOperationV1?,
) -> String {
  match capability {
    Some(value) if value.review_required => "required"
    Some(_) => "not-required"
    None => "not-declared"
  }
}

///|
async fn operator_evidence_refs_json(
  workspace : String,
  projection : @moonflow.RunProjection,
  item : @moonflow.RuntimeItem,
  capability : @moonflow.CapabilityOperationV1?,
) -> Array[Json]? {
  let refs : Array[Json] = [
    {
      "kind": "source-graph",
      "reference": "projection.json",
      "digest": projection.source_digest,
    },
  ]
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace)) catch {
    _ => return None
  }
  for artifact_ref in item.input_artifacts {
    validate_artifact_ref(root, artifact_ref) catch {
      _ => return None
    }
    let digest = sha256_hex(
      @fs.read_file(root + "/" + artifact_ref).binary() catch {
        _ => return None
      },
    )
    refs.push({
      "kind": "input-artifact",
      "reference": artifact_ref,
      "digest": "sha256:" + digest,
    })
  }
  match capability {
    Some(value) => {
      validate_artifact_ref(root, value.health_evidence_ref) catch {
        _ => return None
      }
      let actual = "sha256:" +
        sha256_hex(
          @fs.read_file(root + "/" + value.health_evidence_ref).binary() catch {
            _ => return None
          },
        )
      if actual != value.health_evidence_digest {
        return None
      }
      refs.push({
        "kind": "capability-health",
        "reference": value.health_evidence_ref,
        "digest": actual,
      })
    }
    None => ()
  }
  Some(refs)
}

///|
fn operator_handoff_payload_json(
  projection : @moonflow.RunProjection,
  item : @moonflow.RuntimeItem,
  capability : @moonflow.CapabilityOperationV1?,
  input_digest : String,
  evidence_refs : Array[Json],
) -> Json {
  let review_required = match capability {
    Some(value) => value.review_required
    None => false
  }
  let claim_ceiling = match capability {
    Some(value) => value.claim_ceiling
    None => item.required_claim
  }
  {
    "action_kind": "open-product",
    "run": {
      "run_id": projection.run_id,
      "book_id": projection.book_id,
      "work_item_id": item.work_item_id,
      "declaration_id": item.declaration_id,
      "product_id": item.product_id,
      "operation": item.operation,
      "issued_projection_sequence": projection.last_sequence,
      "issued_work_item_status": item.status.id(),
      "issued_run_outcome": projection.outcome,
    },
    "authority": {
      "requested_authority": item.requested_authority,
      "status": "requested",
      "granted": false,
    },
    "contracts": {
      "capability_status": operator_capability_status(capability),
      "input_contracts": item.input_contracts,
      "output_contracts": item.output_contracts,
      "required_claim": item.required_claim,
      "claim_ceiling": claim_ceiling,
    },
    "inputs": { "digest": input_digest, "artifacts": item.input_artifacts },
    "evidence": {
      "source_digest": projection.source_digest,
      "refs": Json::array(evidence_refs),
    },
    "review": {
      "required": review_required,
      "status": operator_review_status(capability),
      "acceptance_criteria": item.acceptance_criteria,
    },
    "app_entrypoint": operator_entrypoint_json(
      operator_pack_id(item, capability),
    ),
  }
}

///|
fn operator_handoff_payload_digest(payload : Json) -> String {
  "sha256:" + sha256_hex(@utf8.encode(payload.stringify()))
}

///|
fn operator_handoff_token(payload_digest : String) -> String {
  guard payload_digest.has_prefix("sha256:") && payload_digest.length() == 71 else {
    return ""
  }
  payload_digest[7:].to_owned()
}

///|
fn operator_receiver_path(run_id : String, token : String) -> String {
  "/api/moonflow/runs/" + run_id + "/handoffs/" + token
}

///|
fn operator_receiver_json(
  run_id : String,
  token : String,
  payload_digest : String,
) -> Json {
  let endpoint = operator_receiver_path(run_id, token)
  {
    "handoff_token": token,
    "handoff_digest": payload_digest,
    "request_id": "receiver-request-" + token[0:24].to_owned(),
    "attempt_id": "receiver-attempt-" + token[0:24].to_owned(),
    "idempotency_key": "receiver-" + token,
    "intake_path": endpoint,
    "status_path": endpoint + "/status",
    "receipt_path": endpoint + "/receipt",
    "return_path": "/?activity=flow",
  }
}

///|
fn operator_handoff_json(
  action_id : String,
  handoff_ref : String,
  payload : Json,
) -> Json {
  let payload_digest = operator_handoff_payload_digest(payload)
  let token = operator_handoff_token(payload_digest)
  {
    "contract_id": "moonflow.operator-handoff.v2",
    "contract_version": "2.0.0",
    "handoff_id": action_id,
    "handoff_ref": handoff_ref,
    "binding": operator_receiver_json(
      match payload {
        Object(fields) =>
          match fields.get("run") {
            Some(Object(run)) =>
              match run.get("run_id") {
                Some(String(value)) => value
                _ => ""
              }
            _ => ""
          }
        _ => ""
      },
      token,
      payload_digest,
    ),
    "payload": payload,
  }
}

///|
priv struct OperatorPublishedHandoff {
  action_id : String
  handoff_ref : String
  token : String
  digest : String
  request_id : String
  attempt_id : String
  idempotency_key : String
  payload : Json
}

///|
fn operator_json_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() => Some(value)
    _ => None
  }
}

///|
fn operator_token_is_safe(value : String) -> Bool {
  value.length() == 64 &&
  value.iter().all(ch => (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f'))
}

///|
fn decode_operator_published_handoff(
  value : Json,
  expected_action_id : String,
  expected_handoff_ref : String,
  expected_run_id : String,
) -> OperatorPublishedHandoff? {
  guard value is Object(fields) &&
    operator_json_string(fields, "contract_id")
    is Some("moonflow.operator-handoff.v2") &&
    operator_json_string(fields, "contract_version") is Some("2.0.0") &&
    operator_json_string(fields, "handoff_id") is Some(action_id) &&
    operator_json_string(fields, "handoff_ref") is Some(handoff_ref) &&
    fields.get("binding") is Some(Object(binding)) &&
    fields.get("payload") is Some(payload) &&
    operator_json_string(binding, "handoff_token") is Some(token) &&
    operator_json_string(binding, "handoff_digest") is Some(digest) &&
    operator_json_string(binding, "request_id") is Some(request_id) &&
    operator_json_string(binding, "attempt_id") is Some(attempt_id) &&
    operator_json_string(binding, "idempotency_key") is Some(idempotency_key) &&
    operator_json_string(binding, "intake_path") is Some(intake_path) &&
    operator_json_string(binding, "status_path") is Some(status_path) &&
    operator_json_string(binding, "receipt_path") is Some(receipt_path) &&
    operator_json_string(binding, "return_path") is Some("/?activity=flow") else {
    return None
  }
  let endpoint = operator_receiver_path(expected_run_id, token)
  if action_id != expected_action_id ||
    handoff_ref != expected_handoff_ref ||
    !operator_token_is_safe(token) ||
    digest != operator_handoff_payload_digest(payload) ||
    token != operator_handoff_token(digest) ||
    request_id != "receiver-request-" + token[0:24].to_owned() ||
    attempt_id != "receiver-attempt-" + token[0:24].to_owned() ||
    idempotency_key != "receiver-" + token ||
    intake_path != endpoint ||
    status_path != endpoint + "/status" ||
    receipt_path != endpoint + "/receipt" {
    return None
  }
  Some({
    action_id,
    handoff_ref,
    token,
    digest,
    request_id,
    attempt_id,
    idempotency_key,
    payload,
  })
}

///|
fn operator_payload_matches_item(
  handoff : OperatorPublishedHandoff,
  projection : @moonflow.RunProjection,
  item : @moonflow.RuntimeItem,
  input_digest : String?,
  pack_id : String,
) -> Bool {
  guard handoff.payload is Object(payload) &&
    payload.get("run") is Some(Object(run)) &&
    payload.get("authority") is Some(Object(authority)) &&
    payload.get("inputs") is Some(Object(inputs)) &&
    payload.get("evidence") is Some(Object(evidence)) &&
    payload.get("app_entrypoint") is Some(Object(entrypoint)) &&
    operator_json_string(payload, "action_kind") is Some("open-product") &&
    operator_json_string(run, "run_id") is Some(run_id) &&
    operator_json_string(run, "book_id") is Some(book_id) &&
    operator_json_string(run, "work_item_id") is Some(work_item_id) &&
    operator_json_string(run, "declaration_id") is Some(declaration_id) &&
    operator_json_string(run, "product_id") is Some(product_id) &&
    operator_json_string(run, "operation") is Some(operation) &&
    operator_json_string(authority, "requested_authority")
    is Some(requested_authority) &&
    operator_json_string(inputs, "digest") is Some(bound_input_digest) &&
    operator_json_string(evidence, "source_digest") is Some(source_digest) &&
    operator_json_string(entrypoint, "pack_id") is Some(bound_pack_id) else {
    return false
  }
  run_id == projection.run_id &&
  book_id == projection.book_id &&
  work_item_id == item.work_item_id &&
  declaration_id == item.declaration_id &&
  product_id == item.product_id &&
  operation == item.operation &&
  requested_authority == item.requested_authority &&
  source_digest == projection.source_digest &&
  bound_pack_id == pack_id &&
  (input_digest is None || input_digest == Some(bound_input_digest))
}

///|
priv struct OperatorReceiverReceiptProjection {
  status : String
  receipt_ref : String
  receipt_digest : String
  recorded_at : String
}

///|
async fn operator_receiver_receipt_projection(
  directory : String,
  handoff : OperatorPublishedHandoff,
  item : @moonflow.RuntimeItem,
) -> OperatorReceiverReceiptProjection {
  let path = directory + "/operator-receipts/" + handoff.token + ".json"
  if !@fs.exists(path) {
    return {
      status: if item.status == @moonflow.Ready {
        "pending"
      } else {
        "stale"
      },
      receipt_ref: "",
      receipt_digest: "",
      recorded_at: "",
    }
  }
  let value = read_json(path) catch {
    _ =>
      return {
        status: "stale",
        receipt_ref: "",
        receipt_digest: "",
        recorded_at: "",
      }
  }
  guard value is Object(fields) &&
    operator_json_string(fields, "contract_id")
    is Some("moonflow.receiver-receipt-record.v1") &&
    operator_json_string(fields, "contract_version") is Some("1.0.0") &&
    operator_json_string(fields, "handoff_token") is Some(bound_token) &&
    operator_json_string(fields, "handoff_digest") is Some(bound_digest) &&
    operator_json_string(fields, "decision") is Some(decision) &&
    operator_json_string(fields, "receipt_ref") is Some(receipt_ref) &&
    operator_json_string(fields, "receipt_digest") is Some(receipt_digest) &&
    operator_json_string(fields, "recorded_at") is Some(recorded_at) &&
    ["accepted", "denied"].contains(decision) &&
    bound_token == handoff.token &&
    bound_digest == handoff.digest else {
    return {
      status: "stale",
      receipt_ref: "",
      receipt_digest: "",
      recorded_at: "",
    }
  }
  { status: decision, receipt_ref, receipt_digest, recorded_at }
}

///|
fn operator_action_json(
  projection : @moonflow.RunProjection,
  item : @moonflow.RuntimeItem,
  capability : @moonflow.CapabilityOperationV1?,
  handoff : OperatorPublishedHandoff,
  receipt : OperatorReceiverReceiptProjection,
) -> Json {
  let review_required = match capability {
    Some(value) => value.review_required
    None => false
  }
  let claim_ceiling = match capability {
    Some(value) => value.claim_ceiling
    None => item.required_claim
  }
  let enabled = receipt.status == "pending" && item.status == @moonflow.Ready
  let endpoint = operator_receiver_path(projection.run_id, handoff.token)
  {
    "action_id": handoff.action_id,
    "action_kind": "open-product",
    "label": if enabled {
      "Open " + item.product_id
    } else {
      "Receiver " + receipt.status + " · " + item.product_id
    },
    "summary": if enabled {
      "Continue " +
      item.work_item_id +
      " through its declared product entrypoint and return a bound receipt."
    } else {
      "The receiver handoff for " +
      item.work_item_id +
      " is " +
      receipt.status +
      "."
    },
    "status": receipt.status,
    "enabled": enabled,
    "run_id": projection.run_id,
    "work_item_id": item.work_item_id,
    "declaration_id": item.declaration_id,
    "product_id": item.product_id,
    "operation": item.operation,
    "requested_authority": item.requested_authority,
    "authority_status": if receipt.status == "accepted" {
      "granted-by-receipt"
    } else if receipt.status == "denied" {
      "denied-by-receipt"
    } else {
      "requested"
    },
    "claim_ceiling": claim_ceiling,
    "capability_status": operator_capability_status(capability),
    "input_contracts": item.input_contracts,
    "output_contracts": item.output_contracts,
    "evidence_refs": match handoff.payload {
      Object(payload) =>
        match payload.get("evidence") {
          Some(Object(evidence)) =>
            match evidence.get("refs") {
              Some(Array(values)) => Json::array(values)
              _ => Json::array([])
            }
          _ => Json::array([])
        }
      _ => Json::array([])
    },
    "review_required": review_required,
    "review_status": if receipt.status == "accepted" {
      "accepted"
    } else if receipt.status == "denied" {
      "denied"
    } else {
      operator_review_status(capability)
    },
    "acceptance_criteria": item.acceptance_criteria,
    "handoff_ref": handoff.handoff_ref,
    "receiver": {
      "handoff_token": handoff.token,
      "handoff_digest": handoff.digest,
      "request_id": handoff.request_id,
      "attempt_id": handoff.attempt_id,
      "idempotency_key": handoff.idempotency_key,
      "intake_path": endpoint,
      "status_path": endpoint + "/status",
      "receipt_path": endpoint + "/receipt",
      "return_path": "/?activity=flow",
      "status": receipt.status,
      "receipt_ref": receipt.receipt_ref,
      "receipt_digest": receipt.receipt_digest,
      "receipt_recorded_at": receipt.recorded_at,
    },
    "app_entrypoint": operator_entrypoint_json(
      operator_pack_id(item, capability),
    ),
  }
}

///|
async fn load_operator_capability_catalog(
  directory : String,
) -> @moonflow.CapabilityCatalogV1? {
  let path = directory + "/" + operator_capability_snapshot_name()
  if !@fs.exists(path) {
    return None
  }
  Some(@moonflow.decode_capability_catalog_v1(read_json(path))) catch {
    _ => None
  }
}

///|
async fn persist_operator_capability_catalog(
  workspace : String,
  run_id : String,
  catalog : @moonflow.CapabilityCatalogV1,
) -> Unit {
  let directory = run_dir(workspace, run_id)
  if !@fs.exists(directory) {
    @fs.mkdir(directory, permission=0o755, recursive=true)
  }
  write_json(
    directory + "/" + operator_capability_snapshot_name(),
    catalog.to_json(),
  )
}

///|
async fn publish_operator_handoffs(
  workspace : String,
  directory : String,
  projection : @moonflow.RunProjection,
) -> Unit {
  let published_path = directory + "/operator-actions.json"
  if @fs.exists(published_path) {
    let existing = read_json(published_path) catch { _ => Json::null() }
    let existing_contract = match existing {
      Object(fields) =>
        match fields.get("contract_id") {
          Some(String(value)) => value
          _ => ""
        }
      _ => ""
    }
    // Explicit authority-bound action materializations remain authoritative.
    if existing_contract == "moonflow.operator-actions.v1" {
      return
    }
  }
  let handoff_directory = directory + "/operator-handoffs"
  if !@fs.exists(handoff_directory) {
    @fs.mkdir(handoff_directory, permission=0o755, recursive=true)
  }
  let catalog = load_operator_capability_catalog(directory)
  let actions : Array[Json] = []
  for item in projection.items {
    let action_id = operator_action_id(projection.run_id, item.work_item_id)
    let handoff_ref = "operator-handoffs/" + action_id + ".json"
    let handoff_path = directory + "/" + handoff_ref
    let capability = operator_capability_for_item(catalog, item)
    let pack_id = operator_pack_id(item, capability)
    let current_input_digest = if item.status == @moonflow.Ready {
      Some(declared_input_digest(workspace, item.input_artifacts)) catch {
        _ => None
      }
    } else {
      None
    }
    let published = if @fs.exists(handoff_path) {
      decode_operator_published_handoff(
        read_json(handoff_path) catch {
          _ => Json::null()
        },
        action_id,
        handoff_ref,
        projection.run_id,
      )
    } else if item.status == @moonflow.Ready &&
      current_input_digest is Some(input_digest) {
      match
        operator_evidence_refs_json(workspace, projection, item, capability) {
        Some(evidence_refs) => {
          let payload = operator_handoff_payload_json(
            projection, item, capability, input_digest, evidence_refs,
          )
          let handoff_json = operator_handoff_json(
            action_id, handoff_ref, payload,
          )
          write_json(handoff_path, handoff_json)
          decode_operator_published_handoff(
            handoff_json,
            action_id,
            handoff_ref,
            projection.run_id,
          )
        }
        None => None
      }
    } else {
      None
    }
    guard published is Some(handoff) else { continue }
    if !operator_payload_matches_item(
        handoff, projection, item, current_input_digest, pack_id,
      ) {
      continue
    }
    let receipt = operator_receiver_receipt_projection(directory, handoff, item)
    actions.push(
      operator_action_json(projection, item, capability, handoff, receipt),
    )
  }
  write_json(published_path, {
    "contract_id": "moonflow.operator-actions.v2",
    "contract_version": "2.1.0",
    "run_id": projection.run_id,
    "projection_sequence": projection.last_sequence,
    "source_digest": projection.source_digest,
    "actions": Json::array(actions),
  })
}
