///|
/// A named operator's coordination record, never execution authority.
pub(all) struct ResponsibilityChangeV1 {
  contract_id : String
  event_id : String
  run_id : String
  book_id : String
  declaration_revision : String
  source_digest : String
  work_item_id : String
  action : String
  actor_id : String
  assigner_id : String
  expected_sequence : Int
  expected_event_id : String
  recorded_at : String
} derive(Debug, Eq, ToJson)

///|
pub fn decode_responsibility_change_v1(
  value : Json,
) -> ResponsibilityChangeV1 raise {
  let fields = wire_object(value, "responsibility change")
  {
    contract_id: wire_string(fields, "contract_id"),
    event_id: wire_string(fields, "event_id"),
    run_id: wire_string(fields, "run_id"),
    book_id: wire_string(fields, "book_id"),
    declaration_revision: wire_string(fields, "declaration_revision"),
    source_digest: wire_string(fields, "source_digest"),
    work_item_id: wire_string(fields, "work_item_id"),
    action: wire_string(fields, "action"),
    actor_id: wire_string(fields, "actor_id", allow_empty=true),
    assigner_id: wire_string(fields, "assigner_id"),
    expected_sequence: wire_int(fields, "expected_sequence"),
    expected_event_id: wire_string(fields, "expected_event_id"),
    recorded_at: wire_string(fields, "recorded_at"),
  }
}

///|
fn responsibility_payload_v1(
  event : RuntimeEvent,
) -> ResponsibilityChangeV1 raise FlowError {
  decode_responsibility_change_v1(@json.parse(event.detail)) catch {
    _ => raise InvalidResponsibility("invalid responsibility payload")
  }
}

///|
fn validate_responsibility_event_v1(
  projection : RunProjection,
  event : RuntimeEvent,
) -> Unit raise FlowError {
  let change = responsibility_payload_v1(event)
  if change.contract_id != "moonflow.responsibility-change.v1" ||
    change.assigner_id.trim().is_empty() ||
    change.recorded_at.trim().is_empty() ||
    (change.action != "assign" && change.action != "clear") ||
    (change.action == "assign" && change.actor_id.trim().is_empty()) ||
    (change.action == "clear" && change.actor_id != "") {
    raise InvalidResponsibility(
      "explicit assign/clear, named assigner and recorded time required",
    )
  }
  if change.run_id != event.run_id ||
    change.book_id != event.book_id ||
    change.declaration_revision != event.declaration_revision ||
    change.source_digest != event.source_digest ||
    change.work_item_id != event.work_item_id ||
    change.event_id != event.event_id ||
    change.recorded_at != event.recorded_at ||
    change.expected_sequence + 1 != event.sequence {
    raise InvalidResponsibility("payload and event identity mismatch")
  }
  guard projection.find_item(change.work_item_id) is Some(item) else {
    raise MissingWorkItem(change.work_item_id)
  }
  if item.status.is_terminal() {
    raise InvalidResponsibility(
      "terminal work item cannot receive responsibility changes",
    )
  }
  if change.expected_sequence != projection.last_sequence ||
    projection.applied_events.last().map(head => head.event_id) !=
    Some(change.expected_event_id) {
    raise InvalidResponsibility("responsibility expected-head conflict")
  }
}

///|
/// Construct an append-only event. Exact retries return their original event;
/// changed payloads sharing an ID fail, including after later events arrive.
pub fn responsibility_event_v1(
  projection : RunProjection,
  change : ResponsibilityChangeV1,
) -> RuntimeEvent raise FlowError {
  for previous in projection.applied_events {
    if previous.event_id == change.event_id {
      if previous.kind == ResponsibilityChanged &&
        responsibility_payload_v1(previous) == change {
        return previous
      }
      raise ConflictingDuplicateEvent(change.event_id)
    }
  }
  let mut registered : RuntimeEvent? = None
  for event in projection.applied_events {
    if event.kind == ItemRegistered && event.work_item_id == change.work_item_id {
      registered = Some(event)
    }
  }
  guard registered is Some(registration) else {
    raise MissingWorkItem(change.work_item_id)
  }
  let event = {
    ..registration,
    sequence: change.expected_sequence + 1,
    event_id: change.event_id,
    run_id: change.run_id,
    book_id: change.book_id,
    declaration_revision: change.declaration_revision,
    source_digest: change.source_digest,
    kind: ResponsibilityChanged,
    detail: change.to_json().stringify(),
    recorded_at: change.recorded_at,
  }
  // Validate on an independent replay; the caller's projection stays untouched.
  let validation = replay(projection.run_id, projection.applied_events)
  validation.apply(event)
  event
}

///|
/// Last explicit record, including clear and terminal history. No inheritance
/// across revisions; it reads only this run's validated event history.
pub fn responsibility_v1(
  projection : RunProjection,
  work_item_id : String,
) -> ResponsibilityChangeV1? {
  let mut latest = None
  for event in projection.applied_events {
    if event.kind == ResponsibilityChanged && event.work_item_id == work_item_id {
      latest = Some(responsibility_payload_v1(event)) catch { _ => None }
    }
  }
  latest
}
