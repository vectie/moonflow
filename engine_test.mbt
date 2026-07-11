///|
fn event(
  sequence : Int,
  event_id : String,
  kind : EventKind,
  work_item_id? : String = "",
  product_id? : String = "",
  depends_on? : Array[String] = [],
  detail? : String = "",
  artifact_id? : String = "",
  authority_id? : String = "",
  declaration_id? : String = "",
  requested_authority? : String = "observe",
  acceptance_criteria? : Array[String] = ["declared criteria pass"],
) -> RuntimeEvent {
  let source_declaration = if kind == ItemRegistered &&
    declaration_id.is_empty() {
    "declaration-\{work_item_id}"
  } else {
    declaration_id
  }
  {
    sequence,
    event_id,
    run_id: "flow-selene-r1",
    work_item_id,
    kind,
    product_id,
    declaration_id: source_declaration,
    book_id: "selene",
    declaration_revision: "r1",
    source_digest: "sha256:selene-r1",
    requested_authority,
    acceptance_criteria,
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
    depends_on,
    detail,
    artifact_id,
    authority_id,
    recorded_at: "2026-07-11T00:00:00Z",
  }
}

///|
test "event replay preserves dependencies and accepted completion" {
  let events = [
    event(0, "event-run", RunCreated),
    event(
      1,
      "event-register-research",
      ItemRegistered,
      work_item_id="research",
      product_id="moonwiki",
    ),
    event(2, "event-ready-research", ItemReady, work_item_id="research"),
    event(3, "event-start-research", ItemStarted, work_item_id="research"),
    event(
      4,
      "event-review-research",
      ItemReviewRequested,
      work_item_id="research",
    ),
    event(
      5,
      "event-accept-research",
      ItemAccepted,
      work_item_id="research",
      detail="review://research-acceptance",
    ),
    event(
      6,
      "event-register-sim",
      ItemRegistered,
      work_item_id="simulate",
      product_id="moonmoon",
      depends_on=["research"],
    ),
    event(7, "event-ready-sim", ItemReady, work_item_id="simulate"),
    event(8, "event-start-sim", ItemStarted, work_item_id="simulate"),
    event(9, "event-review-sim", ItemReviewRequested, work_item_id="simulate"),
    event(
      10,
      "event-accept-sim",
      ItemAccepted,
      work_item_id="simulate",
      detail="review://simulation-acceptance",
    ),
  ]
  let projection = @moonflow.replay("flow-selene-r1", events)
  assert_eq(projection.outcome, "accepted")
  assert_eq(projection.items.length(), 2)
  assert_eq(projection.items[1].attempt_count, 1)
}

///|
test "duplicate delivery is idempotent" {
  let projection = @moonflow.empty_projection("flow-selene-r1")
  let created = event(0, "event-run", RunCreated)
  projection.apply(created)
  projection.apply(created)
  assert_eq(projection.last_sequence, 0)
  assert_eq(projection.applied_event_ids.length(), 1)
}

///|
test "conflicting duplicate event fails closed" {
  let projection = @moonflow.empty_projection("flow-selene-r1")
  projection.apply(event(0, "event-run", RunCreated))
  try
    projection.apply(
      event(0, "event-run", RunCreated, detail="conflicting payload"),
    )
  catch {
    ConflictingDuplicateEvent(event_id) => assert_eq(event_id, "event-run")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected conflicting duplicate failure")
  }
}

///|
test "dependency gate fails closed" {
  let projection = @moonflow.empty_projection("flow-selene-r1")
  projection.apply(event(0, "event-run", RunCreated))
  projection.apply(
    event(
      1,
      "event-register-sim",
      ItemRegistered,
      work_item_id="simulate",
      product_id="moonmoon",
      depends_on=["research"],
    ),
  )
  try
    projection.apply(
      event(2, "event-ready-sim", ItemReady, work_item_id="simulate"),
    )
  catch {
    DependencyNotAccepted(item_id~, dependency_id~) => {
      assert_eq(item_id, "simulate")
      assert_eq(dependency_id, "research")
    }
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected dependency failure")
  }
}

///|
test "restart replay produces the same projection" {
  let events = [
    event(0, "event-run", RunCreated),
    event(
      1,
      "event-register",
      ItemRegistered,
      work_item_id="research",
      product_id="moonwiki",
    ),
    event(2, "event-ready", ItemReady, work_item_id="research"),
    event(3, "event-start", ItemStarted, work_item_id="research"),
    event(
      4,
      "event-blocked",
      ItemBlocked,
      work_item_id="research",
      detail="source evidence is incomplete",
    ),
  ]
  let first = @moonflow.replay("flow-selene-r1", events)
  let restored = @moonflow.replay("flow-selene-r1", events)
  assert_true(first == restored)
  assert_eq(restored.outcome, "blocked")
  assert_eq(restored.items[0].blocker, "source evidence is incomplete")
}

///|
test "acceptance requires an explicit review receipt" {
  let events = [
    event(0, "event-run", RunCreated),
    event(
      1,
      "event-register",
      ItemRegistered,
      work_item_id="research",
      product_id="moonwiki",
    ),
    event(2, "event-ready", ItemReady, work_item_id="research"),
    event(3, "event-start", ItemStarted, work_item_id="research"),
    event(4, "event-review", ItemReviewRequested, work_item_id="research"),
  ]
  let projection = @moonflow.replay("flow-selene-r1", events)
  try
    projection.apply(
      event(5, "event-accept", ItemAccepted, work_item_id="research"),
    )
  catch {
    MissingAcceptanceReview(item_id) => assert_eq(item_id, "research")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected missing acceptance review to fail")
  }
}

///|
test "workspace boundary rejects path escape" {
  assert_true(
    @moonflow.path_is_within_workspace(
      "/Users/kq/moonsuite", "/Users/kq/moonsuite/books/selene",
    ),
  )
  assert_false(
    @moonflow.path_is_within_workspace(
      "/Users/kq/moonsuite", "/Users/kq/moonsuite/../Workspace/moonbook",
    ),
  )
  assert_false(
    @moonflow.path_is_within_workspace(
      "/Users/kq/moonsuite", "/Users/kq/moonsuite-old",
    ),
  )
  assert_true(
    @moonflow.artifact_ref_is_workspace_relative(
      "books/selene/outputs/evidence.json",
    ),
  )
  assert_false(
    @moonflow.artifact_ref_is_workspace_relative("../Workspace/evidence.json"),
  )
  assert_false(
    @moonflow.artifact_ref_is_workspace_relative(
      "/Users/kq/moonsuite/evidence.json",
    ),
  )
}
