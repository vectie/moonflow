///|
fn history_accepted_events() -> Array[RuntimeEvent] {
  let events = owner_test_events()
  events.push(owner_test_result("unknown"))
  events.push({
    ..owner_test_result("succeeded"),
    sequence: 5,
    event_id: "confirmed",
    result_id: "result-confirmed",
    recorded_at: "2026-07-10T00:00:00Z",
  })
  events.push(
    event(
      6,
      "review-accepted",
      ItemAccepted,
      work_item_id="research",
      detail="review-1",
      artifact_id="evidence/review.json",
      authority_id="reviewer-1",
      result_id="result-confirmed",
      attempt_id="attempt-1",
      output_digest="sha256:output",
    ),
  )
  events
}

///|
fn assert_history_state(
  actual : @moonflow.RunHistoryStateV1?,
  expected : RuntimeItem?,
) -> Unit raise {
  match (actual, expected) {
    (None, None) => ()
    (Some(a), Some(e)) => {
      assert_eq(a.declaration_id, e.declaration_id)
      assert_eq(a.product_id, e.product_id)
      assert_eq(a.operation, e.operation)
      assert_eq(a.status, e.status.id())
      assert_eq(a.attempt_count, e.attempt_count)
      assert_eq(a.request_id, e.request_id)
      assert_eq(a.attempt_id, e.active_attempt_id)
      assert_eq(a.idempotency_key, e.idempotency_key)
      assert_eq(a.external_job_id, e.external_job_id)
      assert_eq(a.attempt_status, e.attempt_status)
      assert_eq(a.input_digest, e.input_digest)
      assert_eq(a.result_id, e.result_id)
      assert_eq(a.output_digest, e.output_digest)
      assert_eq(a.error_kind, e.error_kind)
      assert_eq(a.compensable, e.compensable)
      assert_eq(a.blocker, e.blocker)
      assert_eq(a.review_id, e.acceptance_review_id)
      assert_eq(a.review_artifact, e.acceptance_review_artifact)
      assert_eq(a.reviewer_id, e.acceptance_reviewer_id)
      assert_eq(a.retained_artifacts, e.artifacts)
      assert_eq(a.recorded_approvals, e.approvals)
    }
    _ => fail("history item presence disagrees with canonical replay")
  }
}

///|
test "history every before and after agrees with independent prefix replay" {
  let events = history_accepted_events()
  let original = @moonflow.event_array_json(events).stringify()
  let history = @moonflow.run_history_v1("flow-selene-r1", events)
  assert_eq(history.contract_id, "moonflow.run-history.v1")
  assert_eq(history.entries.length(), 7)
  assert_eq(history.head.last_event_id, "review-accepted")
  assert_eq(history.head.run_outcome, "accepted")
  assert_eq(history.selected_work_item_id, None)
  assert_true(history.to_json() is { "selected_work_item_id": Null, .. })
  assert_true(
    history.entries[0].to_json() is { "before": Null, "after": Null, .. },
  )
  let prefix : Array[RuntimeEvent] = []
  for i, e in events {
    let row = history.entries[i]
    let before = @moonflow.replay("flow-selene-r1", prefix)
    assert_history_state(row.before, before.find_item(e.work_item_id))
    assert_eq(row.run_outcome_before, before.outcome)
    prefix.push(e)
    let after = @moonflow.replay("flow-selene-r1", prefix)
    assert_history_state(row.after, after.find_item(e.work_item_id))
    assert_eq(row.run_outcome_after, after.outcome)
    assert_eq(row.event, @moonflow.runtime_event_json(e))
  }
  assert_eq(history.entries[4].after.unwrap().attempt_status, "unknown")
  assert_eq(history.entries[4].after.unwrap().output_digest, "")
  assert_eq(history.entries[5].before.unwrap().attempt_status, "unknown")
  assert_eq(history.entries[5].after.unwrap().status, "review")
  assert_eq(history.entries[5].after.unwrap().review_id, "")
  assert_eq(history.entries[6].after.unwrap().review_id, "review-1")
  assert_eq(history.entries[1].before, None)
  assert_eq(history.entries[0].after, None)
  assert_eq(original, @moonflow.event_array_json(events).stringify())
}

///|
test "history preserves earlier attempts and event evidence independently from retained state" {
  let events = owner_test_events()
  events.push(
    event(
      4,
      "pause",
      ItemWaiting,
      work_item_id="research",
      detail="no effect; input unavailable",
    ),
  )
  events.push(event(5, "resume", ItemReady, work_item_id="research"))
  events.push({
    ..events[3],
    sequence: 6,
    event_id: "submit-second",
    request_id: "request-2",
    attempt_id: "attempt-2",
    idempotency_key: "key-2",
    input_digest: "sha256:second",
  })
  events.push({
    ..owner_test_result("failed"),
    sequence: 7,
    event_id: "failed-second",
    request_id: "request-2",
    attempt_id: "attempt-2",
    idempotency_key: "key-2",
    result_id: "result-2",
  })
  let h = @moonflow.run_history_v1("flow-selene-r1", events)
  assert_eq(h.entries[3].after.unwrap().attempt_id, "attempt-1")
  assert_eq(h.entries[6].before.unwrap().attempt_id, "attempt-1")
  assert_eq(h.entries[6].after.unwrap().attempt_id, "attempt-2")
  assert_eq(h.entries[6].after.unwrap().attempt_count, 2)
  assert_eq(h.entries[7].after.unwrap().error_kind, "provider-unavailable")
  assert_eq(h.entries[7].after.unwrap().status, "failed")
  assert_eq(h.entries[4].event, @moonflow.runtime_event_json(events[4]))
  assert_eq(h.entries[4].before.unwrap().attempt_status, "submitted")
}

///|
test "history exact item selection validates unselected rows and retains full run head" {
  let events = history_accepted_events()
  events.push(
    event(
      7,
      "other",
      ItemRegistered,
      work_item_id="second",
      product_id="moonmoon",
      depends_on=["research"],
    ),
  )
  events.push(event(8, "other-ready", ItemReady, work_item_id="second"))
  let h = @moonflow.run_history_v1(
    "flow-selene-r1",
    events,
    work_item_id="research",
  )
  assert_eq(h.entries.length(), 6)
  assert_eq(h.canonical_event_count, 9)
  assert_eq(h.head.last_sequence, 8)
  assert_eq(h.head.last_event_id, "other-ready")
  assert_eq(h.head.run_outcome, "ready")
  assert_eq(h.selected_work_item_id, Some("research"))
  assert_eq(h.entries[0].event, @moonflow.runtime_event_json(events[1]))
  assert_true(
    (try? @moonflow.run_history_v1(
      "flow-selene-r1",
      events,
      work_item_id="missing",
    ))
    is Err(_),
  )
  events.push(event(9, "bad-other", ItemAccepted, work_item_id="second"))
  assert_true(
    (try? @moonflow.run_history_v1(
      "flow-selene-r1",
      events,
      work_item_id="research",
    ))
    is Err(_),
  )
}

///|
test "history collapses duplicate delivery but rejects conflicting and corrupt history" {
  let events = history_accepted_events()
  events.insert(2, events[1])
  events.push(events[0])
  let h = @moonflow.run_history_v1("flow-selene-r1", events)
  assert_eq(h.input_event_count, 9)
  assert_eq(h.canonical_event_count, 7)
  assert_eq(h.duplicate_event_count, 2)
  assert_eq(h.entries.length(), 7)
  assert_eq(h.entries[2].event, @moonflow.runtime_event_json(events[3]))
  for
    changed in [
      { ..events[1], detail: "conflict", },
      { ..events[1], event_id: "new-bad-sequence", },
      { ..events[1], event_id: "bad-source", source_digest: "sha256:other", },
      { ..events[1], event_id: "bad-run", run_id: "other", },
    ] {
    let invalid = events.copy()
    invalid.push(changed)
    assert_true(
      (try? @moonflow.run_history_v1("flow-selene-r1", invalid)) is Err(_),
    )
  }
}

///|
test "history snapshots and normalized events never alias caller or neighboring rows" {
  let events = history_accepted_events()
  let h = @moonflow.run_history_v1("flow-selene-r1", events)
  let before = h.to_json().stringify()
  events[1].input_artifacts.push("later-input")
  events[1].acceptance_criteria.push("later-criterion")
  events[4].output_artifacts.push("later-output")
  events.push(
    event(
      7,
      "later",
      ArtifactAttached,
      work_item_id="research",
      artifact_id="later",
    ),
  )
  assert_eq(before, h.to_json().stringify())
  h.entries[4].after.unwrap().retained_artifacts.push("mutated-report")
  assert_false(
    h.entries[5].before.unwrap().retained_artifacts.contains("mutated-report"),
  )
  assert_false(
    h.entries[5].after.unwrap().retained_artifacts.contains("mutated-report"),
  )
  assert_false(events[4].output_artifacts.contains("mutated-report"))
}

///|
test "history renders quoted evidence and preserves event sequence despite timestamps" {
  let events = history_accepted_events()
  events.push(
    event(
      7,
      "quoted-\n雪",
      ArtifactAttached,
      work_item_id="research",
      artifact_id="evidence/雪\n\"quote\"\u001b.json",
    ),
  )
  let h = @moonflow.run_history_v1("flow-selene-r1", events)
  let text = @moonflow.run_history_text_v1(h)
  assert_true(text.contains("#5 \"2026-07-10T00:00:00Z\""))
  assert_true(text.contains("event=\"quoted-\\n雪\""))
  assert_true(text.contains("attempt_status=\"unknown\""))
  assert_true(text.contains("recorded review: \"review-1\""))
  assert_true(text.contains("customer approval or payment"))
  assert_false(text.contains("\u001b"))
  assert_false(text.contains("quoted-\n雪"))
}

///|
test "history keeps checkpoint reuse distinct from fresh execution" {
  let migration = @moonflow.revise_run(
    accepted_parent_projection(),
    revised_graph(),
    "history-child",
    "evidence/revision.json",
    "2026-10-10T00:00:00Z",
  )
  let h = @moonflow.run_history_v1("robot-r2", migration.events)
  let checkpoints = h.entries.filter(e => {
    e.event is { "kind": String("checkpoint-reused"), .. }
  })
  assert_eq(checkpoints.length(), 1)
  assert_eq(checkpoints[0].before.unwrap().status, "ready")
  assert_eq(checkpoints[0].after.unwrap().status, "accepted")
  assert_eq(checkpoints[0].after.unwrap().attempt_count, 0)
  assert_eq(checkpoints[0].after.unwrap().review_id, "review-research-r1")
}

///|
test "history bounds include duplicates and empty histories retain explicit identity" {
  let empty = @moonflow.run_history_v1("empty", [])
  assert_eq(empty.entries, [])
  assert_eq(empty.head.last_sequence, -1)
  assert_eq(empty.head.last_event_id, "")
  assert_eq(empty.head.run_id, "empty")
  assert_true((try? @moonflow.run_history_v1("", [])) is Err(_))
  assert_true(
    (try? @moonflow.run_history_v1("empty", [], work_item_id="")) is Err(_),
  )
  assert_true(
    (try? @moonflow.run_history_v1("empty", [], work_item_id="absent"))
    is Err(_),
  )
  let duplicates = Array::make(4096, event(0, "same", RunCreated))
  let h = @moonflow.run_history_v1("flow-selene-r1", duplicates)
  assert_eq(h.entries.length(), 1)
  assert_eq(h.duplicate_event_count, 4095)
  duplicates.push(duplicates[0])
  assert_true(
    (try? @moonflow.run_history_v1("flow-selene-r1", duplicates)) is Err(_),
  )
}

///|
test "history rejection preserves receipt and attributes review only when recorded" {
  let events = owner_test_events()
  events.push(owner_test_result("succeeded"))
  events.push(
    event(
      5,
      "rejected-review",
      ItemBlocked,
      work_item_id="research",
      error_kind="acceptance-rejected",
      result_id="review-rejected",
      artifact_id="evidence/rejected-review.json",
      authority_id="reviewer-2",
      detail="Revise the declared input",
    ),
  )
  let h = @moonflow.run_history_v1("flow-selene-r1", events)
  let row = h.entries[5]
  assert_eq(row.before.unwrap().status, "review")
  assert_eq(row.before.unwrap().review_id, "")
  assert_eq(row.after.unwrap().status, "blocked")
  assert_eq(row.after.unwrap().result_id, "result-1")
  assert_eq(row.after.unwrap().review_id, "review-rejected")
  assert_eq(row.after.unwrap().reviewer_id, "reviewer-2")
  assert_eq(row.after.unwrap().retained_artifacts, [
    "evidence/exact-output.json", "evidence/rejected-review.json",
  ])
  assert_eq(row.after.unwrap().blocker, "Revise the declared input")
  assert_eq(row.event, @moonflow.runtime_event_json(events[5]))
}
