///|
fn responsibility_change(
  run : RunProjection,
  id : String,
  actor : String,
) -> ResponsibilityChangeV1 {
  {
    contract_id: "moonflow.responsibility-change.v1",
    event_id: id,
    run_id: run.run_id,
    book_id: run.book_id,
    declaration_revision: run.declaration_revision,
    source_digest: run.source_digest,
    work_item_id: "research",
    action: if actor == "" {
      "clear"
    } else {
      "assign"
    },
    actor_id: actor,
    assigner_id: "operator-alice",
    expected_sequence: run.last_sequence,
    expected_event_id: run.applied_events.last().unwrap().event_id,
    recorded_at: "2026-10-15T01:00:00Z",
  }
}

///|
fn responsibility_rejects(
  run : RunProjection,
  change : ResponsibilityChangeV1,
) -> Bool {
  try {
    ignore(@moonflow.responsibility_event_v1(run, change))
    false
  } catch {
    _ => true
  }
}

///|
test "responsibility assignment reassign clear round trips and leaves execution state intact" {
  let run = @moonflow.replay("flow-selene-r1", owner_test_events())
  let item = run.find_item("research").unwrap()
  let item_before = item.to_json().stringify()
  let runnable = run.runnable_item_ids().copy()
  let outcome = run.outcome
  let change = responsibility_change(run, "assign-one", "bob")
  let assigned = @moonflow.responsibility_event_v1(run, change)
  assert_eq(run.last_sequence, 3)
  run.apply(assigned)
  assert_eq(item.to_json().stringify(), item_before)
  assert_eq(run.runnable_item_ids(), runnable)
  assert_eq(run.outcome, outcome)
  assert_eq(@moonflow.owner_summary_v1(run).next_actor_id, Some("bob"))
  guard @moonflow.projection_json(run) is { "items": Array(items), .. } &&
    items[0] is { "responsibility": Object(record), .. } else {
    fail("status responsibility must be a record, not an optional wrapper")
  }
  assert_eq(record.get("assigner_id"), Some(("operator-alice" : Json)))
  assert_true(
    @moonflow.owner_summary_text_v1(@moonflow.owner_summary_v1(run)).contains(
      "owner: bob",
    ),
  )
  let reopened = @moonflow.replay(
    run.run_id,
    @moonflow.decode_event_array(@moonflow.event_array_json(run.applied_events)),
  )
  assert_eq(@moonflow.responsibility_v1(reopened, "research"), Some(change))
  assert_eq(
    @moonflow.owner_summary_v1(reopened),
    @moonflow.owner_summary_v1(run),
  )
  reopened.apply(
    @moonflow.responsibility_event_v1(
      reopened,
      responsibility_change(reopened, "assign-two", "carol"),
    ),
  )
  assert_eq(@moonflow.owner_summary_v1(reopened).next_actor_id, Some("carol"))
  reopened.apply(
    @moonflow.responsibility_event_v1(
      reopened,
      responsibility_change(reopened, "clear-three", ""),
    ),
  )
  assert_true(@moonflow.owner_summary_v1(reopened).next_actor_id is None)
  assert_eq(
    @moonflow.responsibility_v1(reopened, "research").unwrap().action,
    "clear",
  )
  assert_eq(
    reopened.find_item("research").unwrap().to_json().stringify(),
    item_before,
  )
}

///|
test "responsibility duplicate IDs are idempotent even after later changes but conflicting payloads reject" {
  let run = @moonflow.replay("flow-selene-r1", owner_test_events())
  let first = responsibility_change(run, "same-id", "bob")
  let event = @moonflow.responsibility_event_v1(run, first)
  run.apply(event)
  run.apply(
    @moonflow.responsibility_event_v1(
      run,
      responsibility_change(run, "later-id", "carol"),
    ),
  )
  let head = run.last_sequence
  assert_eq(@moonflow.responsibility_event_v1(run, first), event)
  run.apply(event)
  assert_eq(run.last_sequence, head)
  assert_eq(@moonflow.owner_summary_v1(run).next_actor_id, Some("carol"))
  assert_true(responsibility_rejects(run, { ..first, actor_id: "eve", }))
  assert_true(responsibility_rejects(run, { ..first, assigner_id: "eve", }))
  assert_true(responsibility_rejects(run, { ..first, event_id: "owner-run", }))
}

///|
test "responsibility rejects stale head wrong run item revision and malformed named assignments" {
  let run = @moonflow.replay("flow-selene-r1", owner_test_events())
  let good = responsibility_change(run, "candidate", "bob")
  for
    bad in [
      { ..good, expected_sequence: 2, },
      { ..good, expected_event_id: "different-head", },
      { ..good, run_id: "other-run", },
      { ..good, work_item_id: "missing", },
      { ..good, book_id: "other-book", },
      { ..good, declaration_revision: "r2", },
      { ..good, source_digest: "sha256:other", },
      { ..good, assigner_id: " ", },
      { ..good, actor_id: " ", },
      { ..good, action: "clear", },
      { ..good, action: "approve", },
      { ..good, contract_id: "wrong", },
      { ..good, recorded_at: " ", },
    ] {
    assert_true(responsibility_rejects(run, bad))
    assert_eq(run.last_sequence, 3)
  }
}

///|
test "responsibility survives nonterminal status changes with unchanged readiness and review gates" {
  let run = @moonflow.replay("flow-selene-r1", owner_test_events())
  run.apply(
    @moonflow.responsibility_event_v1(
      run,
      responsibility_change(run, "assign", "bob"),
    ),
  )
  run.apply({ ..owner_test_result("succeeded"), sequence: 5, })
  assert_eq(run.find_item("research").unwrap().status, Review)
  assert_eq(@moonflow.owner_summary_v1(run).next_actor_id, Some("bob"))
  assert_eq(@moonflow.owner_summary_v1(run).next_role, Some("reviewer"))
  assert_true(run.find_item("research").unwrap().approvals.is_empty())
  let accepted_without_review = event(
    6,
    "invalid-accept",
    ItemAccepted,
    work_item_id="research",
  )
  let denied = try {
    run.apply(accepted_without_review)
    false
  } catch {
    _ => true
  }
  assert_true(denied)
  assert_eq(run.last_sequence, 5)
  assert_eq(run.find_item("research").unwrap().status, Review)
}

///|
test "responsibility terminal history retained without advertising a next actor" {
  let terminal_events : Array[EventKind] = [
    ItemCancelled,
    ItemSuperseded,
    ItemFailed,
  ]
  for terminal in terminal_events {
    let run = @moonflow.replay("flow-selene-r1", owner_test_events())
    run.apply(
      @moonflow.responsibility_event_v1(
        run,
        responsibility_change(run, "assign", "bob"),
      ),
    )
    run.apply(
      event(
        5,
        "terminal",
        terminal,
        work_item_id="research",
        detail="operator stop",
      ),
    )
    assert_true(@moonflow.owner_summary_v1(run).next_actor_id is None)
    assert_eq(
      @moonflow.responsibility_v1(run, "research").unwrap().actor_id,
      "bob",
    )
    assert_true(
      responsibility_rejects(run, responsibility_change(run, "late", "carol")),
    )
    assert_true(
      responsibility_rejects(run, responsibility_change(run, "late-clear", "")),
    )
  }
}

///|
test "responsibility legacy wire remains unchanged and new revisions cannot inherit assignments" {
  let old = owner_test_events()
  let encoded = @moonflow.event_array_json(old)
  assert_eq(
    @moonflow.event_array_json(@moonflow.decode_event_array(encoded)),
    encoded,
  )
  let parent = @moonflow.replay("flow-selene-r1", old)
  let before = @moonflow.owner_summary_v1(parent)
  parent.apply(
    @moonflow.responsibility_event_v1(
      parent,
      responsibility_change(parent, "assign", "bob"),
    ),
  )
  let child_events = old.map(event => {
    ..event,
    run_id: "child-run",
    declaration_revision: "r2",
    source_digest: "sha256:r2",
  })
  let child = @moonflow.replay("child-run", child_events)
  assert_true(@moonflow.responsibility_v1(child, "research") is None)
  assert_true(@moonflow.owner_summary_v1(child).next_actor_id is None)
  assert_false(@moonflow.owner_summary_is_current_v1(before, child))
  let parent_event = parent.applied_events.last().unwrap()
  let denied = try {
    child.apply(parent_event)
    false
  } catch {
    _ => true
  }
  assert_true(denied)
}

///|
test "responsibility replay rejects tampered payload identity and stale-head wire events" {
  let run = @moonflow.replay("flow-selene-r1", owner_test_events())
  let change = responsibility_change(run, "assign", "bob")
  let valid = @moonflow.responsibility_event_v1(run, change)
  for
    altered in [
      { ..change, expected_event_id: "fake-head", },
      { ..change, work_item_id: "different-item", },
      { ..change, event_id: "different-id", },
    ] {
    let forged = { ..valid, detail: altered.to_json().stringify(), }
    let denied = try {
      run.apply(forged)
      false
    } catch {
      _ => true
    }
    assert_true(denied)
    assert_eq(run.last_sequence, 3)
  }
}

///|
test "responsibility accepted history never becomes reviewer identity or a next action" {
  let run = @moonflow.replay("flow-selene-r1", owner_test_events())
  run.apply(
    @moonflow.responsibility_event_v1(
      run,
      responsibility_change(run, "assign", "coordinator-bob"),
    ),
  )
  run.apply({ ..owner_test_result("succeeded"), sequence: 5, })
  run.apply(
    event(
      6,
      "accepted",
      ItemAccepted,
      work_item_id="research",
      detail="review-1",
      artifact_id="evidence/exact-review.json",
      authority_id="reviewer-alice",
      result_id="result-1",
      attempt_id="attempt-1",
      output_digest="sha256:output",
    ),
  )
  let summary = @moonflow.owner_summary_v1(run)
  assert_eq(summary.actions.length(), 0)
  assert_true(summary.next_actor_id is None)
  assert_eq(summary.evidence[0].reviewer_id, "reviewer-alice")
  assert_eq(
    @moonflow.responsibility_v1(run, "research").unwrap().actor_id,
    "coordinator-bob",
  )
  assert_true(
    responsibility_rejects(run, responsibility_change(run, "late-clear", "")),
  )
}
