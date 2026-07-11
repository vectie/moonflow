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
fn wire_strings(
  fields : Map[String, Json],
  key : String,
  required? : Bool = true,
) -> Array[String] raise {
  match fields.get(key) {
    Some(Array(values)) => values.map(value =>
      match value {
        String(text) => text
        _ => fail("field \{key} must contain only strings")
      },
    )
    None if !required => []
    _ => fail("missing or invalid string array field: \{key}")
  }
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
  let items : Array[Json] = projection.items.map(item => ({
    "work_item_id": item.work_item_id,
    "product_id": item.product_id,
    "depends_on": item.depends_on.to_json(),
    "status": item.status.id(),
    "attempt_count": item.attempt_count,
    "blocker": item.blocker,
    "artifacts": item.artifacts.to_json(),
    "approvals": item.approvals.to_json(),
  } : Json))
  {
    "protocol": "moonflow.run-projection.v1",
    "run_id": projection.run_id,
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
  let recorded_at = wire_string(fields, "recorded_at")
  let items = match fields.get("items") {
    Some(Array(values)) => values
    _ => fail("Work graph requires items array")
  }
  let events : Array[RuntimeEvent] = [
    {
      sequence: 0,
      event_id: "event-\{run_id}-created",
      run_id,
      work_item_id: "",
      kind: RunCreated,
      product_id: "moonflow",
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
    if item.status == Proposed || item.status == Waiting || item.status == Blocked {
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
