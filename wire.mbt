///|
fn wire_object(value : Json, label : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => fail("\{label} must be a JSON object")
  }
}

///|
fn wire_string(
  fields : Map[String, Json],
  key : String,
  allow_empty? : Bool = false,
) -> String raise {
  match fields.get(key) {
    Some(String(value)) if allow_empty || !value.trim().is_empty() => value
    _ => fail("missing or invalid string field: \{key}")
  }
}

///|
fn wire_int(fields : Map[String, Json], key : String) -> Int raise {
  match fields.get(key) {
    Some(Number(value, ..)) => value.to_int()
    _ => fail("missing or invalid integer field: \{key}")
  }
}

///|
fn wire_bool(
  fields : Map[String, Json],
  key : String,
  default? : Bool = false,
) -> Bool raise {
  match fields.get(key) {
    Some(True) => true
    Some(False) => false
    None => default
    _ => fail("missing or invalid boolean field: \{key}")
  }
}

///|
fn wire_strings(
  fields : Map[String, Json],
  key : String,
  required? : Bool = true,
) -> Array[String] raise {
  match fields.get(key) {
    Some(Array(values)) =>
      values.map(value => {
        match value {
          String(text) if !text.trim().is_empty() => text
          _ => fail("field \{key} must contain only strings")
        }
      })
    None if !required => []
    _ => fail("missing or invalid string array field: \{key}")
  }
}

///|
fn work_graph_has_cycle(items : Array[Json]) -> Bool raise {
  let processed : Array[String] = []
  for ;; {
    let before = processed.length()
    for item_value in items {
      let item = wire_object(item_value, "Work item")
      let work_item_id = wire_string(item, "work_item_id")
      if !processed.contains(work_item_id) {
        let dependencies = wire_strings(item, "depends_on", required=false)
        if dependencies.all(dependency => processed.contains(dependency)) {
          processed.push(work_item_id)
        }
      }
    }
    if processed.length() == items.length() || processed.length() == before {
      break
    }
  }
  processed.length() != items.length()
}

///|
pub fn event_kind_from_id(id : String) -> EventKind raise {
  match id {
    "run-created" => RunCreated
    "item-registered" => ItemRegistered
    "item-ready" => ItemReady
    "item-started" => ItemStarted
    "item-waiting" => ItemWaiting
    "item-blocked" => ItemBlocked
    "item-review-requested" => ItemReviewRequested
    "item-accepted" => ItemAccepted
    "item-failed" => ItemFailed
    "item-cancelled" => ItemCancelled
    "item-superseded" => ItemSuperseded
    "artifact-attached" => ArtifactAttached
    "approval-granted" => ApprovalGranted
    "attempt-submitted" => AttemptSubmitted
    "attempt-reconciled" => AttemptReconciled
    "checkpoint-reused" => CheckpointReused
    _ => fail("unsupported MoonFlow event kind: \{id}")
  }
}

///|
pub fn decode_runtime_event(value : Json) -> RuntimeEvent raise {
  let fields = wire_object(value, "MoonFlow event")
  {
    sequence: wire_int(fields, "sequence"),
    event_id: wire_string(fields, "event_id"),
    run_id: wire_string(fields, "run_id"),
    work_item_id: wire_string(fields, "work_item_id", allow_empty=true),
    kind: event_kind_from_id(wire_string(fields, "kind")),
    product_id: wire_string(fields, "product_id", allow_empty=true),
    declaration_id: wire_string(fields, "declaration_id", allow_empty=true),
    book_id: wire_string(fields, "book_id"),
    declaration_revision: wire_string(fields, "declaration_revision"),
    source_digest: wire_string(fields, "source_digest"),
    requested_authority: wire_string(
      fields,
      "requested_authority",
      allow_empty=true,
    ),
    acceptance_criteria: wire_strings(
      fields,
      "acceptance_criteria",
      required=false,
    ),
    request_id: wire_string(fields, "request_id", allow_empty=true),
    result_id: wire_string(fields, "result_id", allow_empty=true),
    attempt_id: wire_string(fields, "attempt_id", allow_empty=true),
    idempotency_key: wire_string(fields, "idempotency_key", allow_empty=true),
    external_job_id: wire_string(fields, "external_job_id", allow_empty=true),
    attempt_status: wire_string(fields, "attempt_status", allow_empty=true),
    input_digest: wire_string(fields, "input_digest", allow_empty=true),
    output_digest: wire_string(fields, "output_digest", allow_empty=true),
    output_artifacts: wire_strings(fields, "output_artifacts", required=false),
    error_kind: wire_string(fields, "error_kind", allow_empty=true),
    compensable: wire_bool(fields, "compensable"),
    depends_on: wire_strings(fields, "depends_on", required=false),
    detail: wire_string(fields, "detail", allow_empty=true),
    artifact_id: wire_string(fields, "artifact_id", allow_empty=true),
    authority_id: wire_string(fields, "authority_id", allow_empty=true),
    recorded_at: wire_string(fields, "recorded_at"),
  }
}

///|
pub fn runtime_event_json(event : RuntimeEvent) -> Json {
  {
    "sequence": event.sequence,
    "event_id": event.event_id,
    "run_id": event.run_id,
    "work_item_id": event.work_item_id,
    "kind": event.kind.id(),
    "product_id": event.product_id,
    "declaration_id": event.declaration_id,
    "book_id": event.book_id,
    "declaration_revision": event.declaration_revision,
    "source_digest": event.source_digest,
    "requested_authority": event.requested_authority,
    "acceptance_criteria": event.acceptance_criteria.to_json(),
    "request_id": event.request_id,
    "result_id": event.result_id,
    "attempt_id": event.attempt_id,
    "idempotency_key": event.idempotency_key,
    "external_job_id": event.external_job_id,
    "attempt_status": event.attempt_status,
    "input_digest": event.input_digest,
    "output_digest": event.output_digest,
    "output_artifacts": event.output_artifacts.to_json(),
    "error_kind": event.error_kind,
    "compensable": event.compensable,
    "depends_on": event.depends_on.to_json(),
    "detail": event.detail,
    "artifact_id": event.artifact_id,
    "authority_id": event.authority_id,
    "recorded_at": event.recorded_at,
  }
}

///|
pub fn decode_event_array(value : Json) -> Array[RuntimeEvent] raise {
  match value {
    Array(values) => values.map(value => decode_runtime_event(value))
    _ => fail("MoonFlow event store must be a JSON array")
  }
}

///|
pub fn event_array_json(events : Array[RuntimeEvent]) -> Json {
  Json::array(events.map(event => runtime_event_json(event)))
}

///|
pub fn projection_json(projection : RunProjection) -> Json {
  let items : Array[Json] = projection.items.map(item => {
    (
      {
        "work_item_id": item.work_item_id,
        "declaration_id": item.declaration_id,
        "product_id": item.product_id,
        "requested_authority": item.requested_authority,
        "acceptance_criteria": item.acceptance_criteria.to_json(),
        "depends_on": item.depends_on.to_json(),
        "status": item.status.id(),
        "attempt_count": item.attempt_count,
        "request_id": item.request_id,
        "result_id": item.result_id,
        "active_attempt_id": item.active_attempt_id,
        "idempotency_key": item.idempotency_key,
        "external_job_id": item.external_job_id,
        "attempt_status": item.attempt_status,
        "operation": item.operation,
        "input_digest": item.input_digest,
        "output_digest": item.output_digest,
        "error_kind": item.error_kind,
        "compensable": item.compensable,
        "blocker": item.blocker,
        "acceptance_review_id": item.acceptance_review_id,
        "acceptance_review_artifact": item.acceptance_review_artifact,
        "acceptance_reviewer_id": item.acceptance_reviewer_id,
        "artifacts": item.artifacts.to_json(),
        "approvals": item.approvals.to_json(),
      } : Json)
  })
  {
    "protocol": "moonflow.run-projection.v3",
    "run_id": projection.run_id,
    "book_id": projection.book_id,
    "declaration_revision": projection.declaration_revision,
    "source_digest": projection.source_digest,
    "last_sequence": projection.last_sequence,
    "outcome": projection.outcome,
    "runnable_item_ids": projection.runnable_item_ids().to_json(),
    "items": items,
  }
}

///|
pub fn events_from_work_graph(value : Json) -> Array[RuntimeEvent] raise {
  let fields = wire_object(value, "MoonFlow Work graph")
  let contract_id = wire_string(fields, "contract_id")
  if contract_id != protocol_id() {
    fail("unsupported Work graph contract: \{contract_id}")
  }
  let run_id = wire_string(fields, "graph_id")
  let book_id = wire_string(fields, "book_id")
  let declaration_revision = wire_string(fields, "declaration_revision")
  let source_digest = wire_string(fields, "source_digest")
  let recorded_at = wire_string(fields, "recorded_at")
  let items = match fields.get("items") {
    Some(Array(values)) => values
    _ => fail("Work graph requires items array")
  }
  if items.is_empty() {
    fail("Work graph requires at least one item")
  }
  let item_ids : Array[String] = []
  for item_value in items {
    let item = wire_object(item_value, "Work item")
    let work_item_id = wire_string(item, "work_item_id")
    if item_ids.contains(work_item_id) {
      fail("duplicate work_item_id: \{work_item_id}")
    }
    item_ids.push(work_item_id)
  }
  for item_value in items {
    let item = wire_object(item_value, "Work item")
    let work_item_id = wire_string(item, "work_item_id")
    for dependency in wire_strings(item, "depends_on", required=false) {
      if dependency == work_item_id {
        fail("work item cannot depend on itself: \{work_item_id}")
      }
      if !item_ids.contains(dependency) {
        fail("unknown dependency \{dependency} for \{work_item_id}")
      }
    }
    let requested_authority = wire_string(item, "requested_authority")
    if ![
        "observe", "cognitive-maintenance", "sandbox-execution", "workspace-mutation",
        "external-effect", "physical-effect",
      ].contains(requested_authority) {
      fail(
        "unsupported requested_authority \{requested_authority} for \{work_item_id}",
      )
    }
  }
  if work_graph_has_cycle(items) {
    fail("Work graph contains a dependency cycle")
  }
  let events : Array[RuntimeEvent] = [
    {
      sequence: 0,
      event_id: "event-\{run_id}-created",
      run_id,
      work_item_id: "",
      kind: RunCreated,
      product_id: "moonflow",
      declaration_id: "",
      book_id,
      declaration_revision,
      source_digest,
      requested_authority: "",
      acceptance_criteria: [],
      request_id: "",
      result_id: "",
      attempt_id: "",
      idempotency_key: "",
      external_job_id: "",
      attempt_status: "",
      input_digest: "",
      output_digest: "",
      output_artifacts: [],
      error_kind: "",
      compensable: false,
      depends_on: [],
      detail: "",
      artifact_id: "",
      authority_id: "",
      recorded_at,
    },
  ]
  for item_value in items {
    let item = wire_object(item_value, "Work item")
    let work_item_id = wire_string(item, "work_item_id")
    events.push({
      sequence: events.length(),
      event_id: "event-\{run_id}-register-\{work_item_id}",
      run_id,
      work_item_id,
      kind: ItemRegistered,
      product_id: wire_string(item, "product_id"),
      declaration_id: wire_string(item, "declaration_id"),
      book_id,
      declaration_revision,
      source_digest,
      requested_authority: wire_string(item, "requested_authority"),
      acceptance_criteria: wire_strings(item, "acceptance_criteria"),
      request_id: "",
      result_id: "",
      attempt_id: "",
      idempotency_key: "",
      external_job_id: "",
      attempt_status: "",
      input_digest: "",
      output_digest: "",
      output_artifacts: [],
      error_kind: "",
      compensable: false,
      depends_on: wire_strings(item, "depends_on", required=false),
      detail: "",
      artifact_id: "",
      authority_id: "",
      recorded_at,
    })
  }
  let projection = replay(run_id, events)
  for item in projection.items {
    if item.depends_on.is_empty() {
      events.push({
        sequence: events.length(),
        event_id: "event-\{run_id}-ready-\{item.work_item_id}",
        run_id,
        work_item_id: item.work_item_id,
        kind: ItemReady,
        product_id: item.product_id,
        declaration_id: item.declaration_id,
        book_id,
        declaration_revision,
        source_digest,
        requested_authority: item.requested_authority,
        acceptance_criteria: item.acceptance_criteria.copy(),
        request_id: "",
        result_id: "",
        attempt_id: "",
        idempotency_key: "",
        external_job_id: "",
        attempt_status: "",
        input_digest: "",
        output_digest: "",
        output_artifacts: [],
        error_kind: "",
        compensable: false,
        depends_on: [],
        detail: "",
        artifact_id: "",
        authority_id: "",
        recorded_at,
      })
    }
  }
  ignore(replay(run_id, events))
  events
}

///|
pub fn ready_events(
  projection : RunProjection,
  recorded_at : String,
) -> Array[RuntimeEvent] {
  let events : Array[RuntimeEvent] = []
  let mut sequence = projection.last_sequence + 1
  for item in projection.items {
    if item.status == Proposed ||
      item.status == Waiting ||
      item.status == Blocked {
      let mut ready = true
      for dependency_id in item.depends_on {
        let mut accepted = false
        for dependency in projection.items {
          if dependency.work_item_id == dependency_id &&
            dependency.status == Accepted {
            accepted = true
          }
        }
        if !accepted {
          ready = false
        }
      }
      if ready {
        events.push({
          sequence,
          event_id: "event-\{projection.run_id}-ready-\{item.work_item_id}-\{sequence}",
          run_id: projection.run_id,
          work_item_id: item.work_item_id,
          kind: ItemReady,
          product_id: item.product_id,
          declaration_id: item.declaration_id,
          book_id: projection.book_id,
          declaration_revision: projection.declaration_revision,
          source_digest: projection.source_digest,
          requested_authority: item.requested_authority,
          acceptance_criteria: item.acceptance_criteria.copy(),
          request_id: "",
          result_id: "",
          attempt_id: "",
          idempotency_key: "",
          external_job_id: "",
          attempt_status: "",
          input_digest: "",
          output_digest: "",
          output_artifacts: [],
          error_kind: "",
          compensable: false,
          depends_on: [],
          detail: "",
          artifact_id: "",
          authority_id: "",
          recorded_at,
        })
        sequence += 1
      }
    }
  }
  events
}
