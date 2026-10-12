///|
fn owner_test_events() -> Array[RuntimeEvent] {
  [
    event(0, "owner-run", RunCreated),
    event(
      1,
      "owner-register",
      ItemRegistered,
      work_item_id="research",
      product_id="moonwiki",
    ),
    event(2, "owner-ready", ItemReady, work_item_id="research"),
    event(
      3,
      "owner-submit",
      AttemptSubmitted,
      work_item_id="research",
      detail="query-evidence",
      request_id="request-1",
      attempt_id="attempt-1",
      idempotency_key="key-1",
      attempt_status="submitted",
      input_digest="sha256:input",
    ),
  ]
}

///|
fn owner_test_result(status : String) -> RuntimeEvent {
  event(
    4,
    "owner-result",
    AttemptReconciled,
    work_item_id="research",
    request_id="request-1",
    result_id="result-1",
    attempt_id="attempt-1",
    idempotency_key="key-1",
    attempt_status=status,
    output_digest="sha256:output",
    output_artifacts=["evidence/exact-output.json"],
    error_kind=if status == "failed" { "provider-unavailable" } else { "" },
  )
}

///|
test "owner summary waiting retains ordered reasons and unknown ownership" {
  let events = owner_test_events()
  events.push(
    event(
      4,
      "owner-wait",
      ItemWaiting,
      work_item_id="research",
      detail="Await source evidence",
    ),
  )
  events.push(
    event(
      5,
      "owner-second",
      ItemRegistered,
      work_item_id="dependent",
      product_id="moonmoon",
      depends_on=["research", "missing"],
    ),
  )
  let run = @moonflow.replay("flow-selene-r1", events)
  let before = @moonflow.event_array_json(run.applied_events).stringify()
  let summary = @moonflow.owner_summary_v1(run)
  assert_eq(summary.actions[0].work_item_id, "research")
  assert_eq(summary.actions[0].reasons, ["Await source evidence"])
  assert_eq(summary.actions[1].depends_on, ["research", "missing"])
  assert_eq(summary.actions[1].reasons, [
    "Waiting for research: waiting", "Waiting for missing: dependency not recorded",
  ])
  assert_true(summary.next_actor_id is None)
  assert_true(summary.next_role is None)
  assert_eq(before, @moonflow.event_array_json(run.applied_events).stringify())
  assert_eq(summary.recorded_at, Some("2026-07-11T00:00:00Z"))
  assert_eq(summary.last_event_id, Some("owner-second"))
}

///|
test "owner summary review failed and unknown preserve the review and retry boundaries" {
  for status in ["succeeded", "failed", "unknown"] {
    let events = owner_test_events()
    events.push(owner_test_result(status))
    let run = @moonflow.replay("flow-selene-r1", events)
    let summary = @moonflow.owner_summary_v1(run)
    assert_eq(summary.evidence[0].artifacts, ["evidence/exact-output.json"])
    assert_eq(summary.evidence[0].attempt_id, "attempt-1")
    assert_eq(summary.evidence[0].result_id, "result-1")
    assert_true(summary.next_actor_id is None)
    match status {
      "succeeded" => {
        assert_eq(summary.outcome, "review")
        assert_eq(summary.next_role, Some("reviewer"))
        assert_eq(summary.evidence[0].output_digest, "sha256:output")
        assert_true(summary.next_action.contains("acceptance criteria"))
      }
      "failed" => {
        assert_eq(summary.outcome, "failed")
        assert_eq(summary.actions[0].reasons, ["provider-unavailable"])
        assert_true(summary.next_action.contains("governed recovery"))
        assert_false(summary.next_action.contains("Retry now"))
      }
      _ => {
        assert_eq(summary.actions[0].status, "unknown")
        assert_eq(
          summary.next_action,
          "Reconcile the unknown outcome before any retry",
        )
        assert_eq(summary.evidence[0].output_digest, "")
      }
    }
    guard @moonflow.projection_json(run) is { "owner_summary": embedded, .. } else {
      fail("missing host summary")
    }
    assert_eq(embedded, summary.to_json())
    assert_true(
      @moonflow.owner_summary_text_v1(summary).contains(summary.next_action),
    )
  }
}

///|
test "owner summary accepted evidence is internal only and is a nonaliasing snapshot" {
  let events = owner_test_events()
  events.push(owner_test_result("succeeded"))
  events.push(
    event(
      5,
      "owner-accepted",
      ItemAccepted,
      work_item_id="research",
      detail="review-1",
      artifact_id="evidence/exact-review.json",
      authority_id="reviewer-1",
      result_id="result-1",
      attempt_id="attempt-1",
      output_digest="sha256:output",
    ),
  )
  let run = @moonflow.replay("flow-selene-r1", events)
  let summary = @moonflow.owner_summary_v1(run)
  assert_eq(summary.outcome, "accepted")
  assert_eq(summary.actions.length(), 0)
  assert_true(summary.next_actor_id is None)
  assert_true(summary.next_role is None)
  assert_eq(summary.evidence[0].reviewer_id, "reviewer-1")
  assert_eq(summary.evidence[0].review_artifact, "evidence/exact-review.json")
  assert_true(
    summary.acceptance_boundary.contains("does not establish customer approval"),
  )
  assert_true(@moonflow.owner_summary_is_current_v1(summary, run))
  run.apply(
    event(
      6,
      "owner-later-evidence",
      ArtifactAttached,
      work_item_id="research",
      artifact_id="evidence/later.json",
    ),
  )
  assert_false(@moonflow.owner_summary_is_current_v1(summary, run))
  assert_false(summary.evidence[0].artifacts.contains("evidence/later.json"))
}

///|
test "owner summary child revision cannot reuse its parent's completion label" {
  let parent = accepted_parent_projection()
  let summary = @moonflow.owner_summary_v1(parent)
  let revision = @moonflow.revise_run(
    parent,
    revised_graph(),
    "owner-child",
    "evidence/revision.json",
    "2026-10-06T00:00:00Z",
  )
  let child = @moonflow.replay("robot-r2", revision.events)
  assert_false(@moonflow.owner_summary_is_current_v1(summary, child))
  let current = @moonflow.owner_summary_v1(child)
  assert_false(current.outcome == "accepted")
  assert_eq(current.declaration_revision, "r2")
  assert_eq(
    current.evidence[0].review_artifact,
    "evidence/review-research-r1.json",
  )
  assert_true(current.actions.any(action => action.work_item_id == "design-r2"))
  assert_eq(parent.outcome, "accepted")
}

///|
test "owner next action points to runnable upstream work before its waiting dependents" {
  let events = [
    event(0, "priority-run", RunCreated),
    event(
      1,
      "priority-dependent",
      ItemRegistered,
      work_item_id="dependent",
      product_id="moonmoon",
      depends_on=["upstream"],
    ),
    event(
      2,
      "priority-upstream",
      ItemRegistered,
      work_item_id="upstream",
      product_id="moonwiki",
    ),
    event(3, "priority-ready", ItemReady, work_item_id="upstream"),
  ]
  let summary = @moonflow.owner_summary_v1(
    @moonflow.replay("flow-selene-r1", events),
  )
  assert_eq(summary.actions.map(action => action.work_item_id), [
    "upstream", "dependent",
  ])
  assert_eq(summary.actions[1].reasons, ["Waiting for upstream: ready"])
}

///|
test "owner summary attention ordering remains stable with multiple blockers" {
  let events = [event(0, "ordered-run", RunCreated)]
  for id in ["first", "second", "third"] {
    events.push(
      event(
        events.length(),
        "register-" + id,
        ItemRegistered,
        work_item_id=id,
        product_id="moonwiki",
      ),
    )
    events.push(
      event(
        events.length(),
        "block-" + id,
        ItemBlocked,
        work_item_id=id,
        detail="Needs evidence for " + id,
      ),
    )
  }
  let summary = @moonflow.owner_summary_v1(
    @moonflow.replay("flow-selene-r1", events),
  )
  assert_eq(summary.actions.map(action => action.work_item_id), [
    "first", "second", "third",
  ])
  assert_true(
    summary.actions.all(action => {
      action.next_actor_id is None && action.next_role is None
    }),
  )
  assert_eq(summary.actions[1].reasons, ["Needs evidence for second"])
}
