///|
fn readiness_restore(
  events : Array[@moonflow.RuntimeEvent],
) -> @moonflow.RunProjection raise {
  @moonflow.replay(
    "flow-r1",
    @moonflow.decode_event_array(@moonflow.event_array_json(events)),
  )
}

///|
fn readiness_attempt_events(
  status : @moonflow.AdapterAttemptStatus,
) -> Array[@moonflow.RuntimeEvent] raise {
  let events = adapter_projection_events()
  events.push(
    @moonflow.adapter_submission_event(
      readiness_restore(events),
      adapter_request(),
    ),
  )
  if status != @moonflow.Submitted {
    events.push(
      @moonflow.adapter_reconciliation_event(
        readiness_restore(events),
        adapter_result(
          status,
          output_digest="",
          error_kind=if status == @moonflow.Failed {
            "definitive-failure"
          } else {
            ""
          },
        ),
      ),
    )
  }
  events
}

///|
fn readiness_review(decision : String) -> @moonflow.AcceptanceReviewReceipt {
  let request = adapter_request()
  let result = adapter_result(@moonflow.Succeeded)
  {
    contract_id: "moonflow.acceptance-review.v1",
    review_id: "review-readiness-result",
    run_id: request.run_id,
    work_item_id: request.work_item_id,
    declaration_id: request.declaration_id,
    result_id: result.result_id,
    attempt_id: request.attempt_id,
    output_digest: result.output_digest,
    decision,
    criteria: request.acceptance_criteria.map(criterion => {
      criterion,
      satisfied: decision == "accepted",
      evidence_refs: result.output_artifacts.copy(),
      note: "Existing review policy is preserved.",
    }),
    reviewer_id: "readiness-fixture-reviewer",
    review_authority_id: "book-owner-review",
    receipt_artifact: "reviews/readiness.json",
    recorded_at: "2026-10-04T19:00:00Z",
  }
}

///|
test "readiness preserves unknown attempt across scheduler replay and direct retry" {
  let events = readiness_attempt_events(@moonflow.Unknown)
  let unknown = readiness_restore(events)
  let before = @moonflow.projection_json(unknown)
  assert_true(
    @moonflow.director_retry_decision(@moonflow.UnknownOutcome).requires_reconciliation,
  )
  for _ in 0..<3 {
    let current = readiness_restore(events)
    let suggestions = @moonflow.ready_events(current, "2026-10-04T19:00:00Z")
    assert_eq(suggestions.length(), 0)
    for suggestion in suggestions {
      events.push(suggestion)
    }
    assert_eq(@moonflow.projection_json(readiness_restore(events)), before)
  }
  let original = adapter_request()
  let retry = {
    ..original,
    request_id: "retry-request",
    attempt_id: "retry-attempt",
    idempotency_key: "retry-key",
  }
  try
    @moonflow.adapter_submission_event(readiness_restore(events), retry)
  catch {
    @moonflow.AdapterRuntimeItemNotReady(item_id~, status~) => {
      assert_eq(item_id, original.work_item_id)
      assert_eq(status, "blocked")
    }
    _ => fail("unexpected retry error")
  } noraise {
    _ => fail("unknown retry must require reconciliation")
  }
  assert_eq(@moonflow.adapter_submission_event(unknown, original), events[3])
  let repeated = @moonflow.adapter_reconciliation_event(
    unknown,
    adapter_result(@moonflow.Unknown, output_digest=""),
  )
  unknown.apply(repeated)
  assert_eq(@moonflow.projection_json(unknown), before)
  assert_eq(unknown.items[0].attempt_count, 1)
  assert_eq(
    unknown.items[0].blocker,
    "adapter outcome unknown; reconciliation required",
  )
}

///|
test "readiness excludes all unresolved attempt statuses in waiting and blocked states" {
  for
    attempt_status in [
      @moonflow.Submitted,
      @moonflow.Running,
      @moonflow.Unknown,
    ] {
    for kind in [@moonflow.ItemWaiting, @moonflow.ItemBlocked] {
      let events = readiness_attempt_events(attempt_status)
      let current = readiness_restore(events)
      if !(attempt_status == @moonflow.Unknown && kind == @moonflow.ItemBlocked) {
        events.push({
          ..events[2],
          sequence: current.last_sequence + 1,
          event_id: "paused-attempt",
          kind,
          detail: "Await original attempt",
        })
      }
      let paused = readiness_restore(events)
      assert_eq(paused.items[0].attempt_status, attempt_status.id())
      assert_eq(@moonflow.ready_events(paused, "later").length(), 0)
      assert_eq(paused.items[0].attempt_count, 1)
    }
  }
}

///|
test "readiness preserves legacy proposed waiting and blocked work without attempts" {
  for
    kind in [
      @moonflow.ItemRegistered,
      @moonflow.ItemWaiting,
      @moonflow.ItemBlocked,
    ] {
    let original = adapter_projection_events()
    let events = original[:2].to_owned()
    if kind != @moonflow.ItemRegistered {
      events.push({ ..original[2], kind, detail: "legacy blocker", })
    }
    let current = readiness_restore(events)
    assert_eq(current.items[0].attempt_status, "")
    let ready = @moonflow.ready_events(current, "later")
    assert_eq(ready.length(), 1)
    assert_eq(ready[0].sequence, current.last_sequence + 1)
    current.apply(ready[0])
    assert_eq(current.items[0].status, @moonflow.Ready)
    assert_eq(current.items[0].blocker, "")
    assert_eq(current.items[0].attempt_count, 0)
    assert_eq(@moonflow.ready_events(current, "later-again").length(), 0)
  }
}

///|
test "unknown resolution succeeds through existing review and releases dependencies" {
  let events = readiness_attempt_events(@moonflow.Unknown)
  let dependent = {
    ..events[1],
    sequence: events.length(),
    event_id: "register-dependent",
    work_item_id: "dependent",
    declaration_id: "dependent-declaration",
    depends_on: ["work-research"],
  }
  events.push(dependent)
  assert_eq(
    @moonflow.ready_events(readiness_restore(events), "before-result").length(),
    0,
  )
  let result = adapter_result(@moonflow.Succeeded, result_id="resolved-result")
  events.push(
    @moonflow.adapter_reconciliation_event(readiness_restore(events), result),
  )
  let review = readiness_restore(events)
  assert_eq(review.items[0].status, @moonflow.Review)
  assert_eq(review.items[0].blocker, "")
  assert_eq(@moonflow.ready_events(review, "before-review").length(), 0)
  let receipt = { ..readiness_review("accepted"), result_id: result.result_id, }
  events.push(@moonflow.acceptance_review_event(review, receipt))
  let accepted = readiness_restore(events)
  assert_eq(accepted.items[0].status, @moonflow.Accepted)
  assert_eq(accepted.items[0].attempt_count, 1)
  let ready = @moonflow.ready_events(accepted, "after-review")
  assert_eq(ready.length(), 1)
  assert_eq(ready[0].work_item_id, "dependent")
  events.push(ready[0])
  let restored = readiness_restore(events)
  assert_eq(restored.items[1].status, @moonflow.Ready)
}

///|
test "unknown definitive failure and cancellation remain terminal" {
  let outcomes : Array[@moonflow.AdapterAttemptStatus] = [
    @moonflow.Failed,
    @moonflow.Cancelled,
  ]
  for status in outcomes {
    let events = readiness_attempt_events(@moonflow.Unknown)
    let result = adapter_result(
      status,
      result_id="resolved-terminal",
      output_digest="",
      error_kind=if status == @moonflow.Failed {
        "definitive-failure"
      } else {
        ""
      },
    )
    events.push(
      @moonflow.adapter_reconciliation_event(readiness_restore(events), result),
    )
    let resolved = readiness_restore(events)
    assert_eq(resolved.items[0].attempt_status, status.id())
    assert_true(resolved.items[0].status.is_terminal())
    assert_eq(resolved.items[0].attempt_count, 1)
    assert_eq(@moonflow.ready_events(resolved, "later").length(), 0)
  }
}

///|
test "readiness keeps existing rejected-review retry behavior after resolved success" {
  let events = readiness_attempt_events(@moonflow.Submitted)
  events.push(
    @moonflow.adapter_reconciliation_event(
      readiness_restore(events),
      adapter_result(@moonflow.Succeeded),
    ),
  )
  events.push(
    @moonflow.acceptance_review_event(
      readiness_restore(events),
      readiness_review("rejected"),
    ),
  )
  let rejected = readiness_restore(events)
  assert_eq(rejected.items[0].status, @moonflow.Blocked)
  assert_eq(rejected.items[0].attempt_status, "succeeded")
  assert_eq(rejected.items[0].error_kind, "acceptance-rejected")
  let ready = @moonflow.ready_events(rejected, "later")
  assert_eq(ready.length(), 1)
  events.push(ready[0])
  let original = adapter_request()
  let retry = {
    ..original,
    request_id: "revised-request",
    attempt_id: "revised-attempt",
    idempotency_key: "revised-key",
  }
  events.push(
    @moonflow.adapter_submission_event(readiness_restore(events), retry),
  )
  assert_eq(readiness_restore(events).items[0].attempt_count, 2)
}

///|
test "readiness skips unresolved work without blocking independent work or event sequencing" {
  let events = readiness_attempt_events(@moonflow.Unknown)
  for id in ["independent-a", "independent-b"] {
    events.push({
      ..events[1],
      sequence: events.length(),
      event_id: "register-" + id,
      work_item_id: id,
      declaration_id: "declaration-" + id,
    })
  }
  let before = readiness_restore(events)
  let ready = @moonflow.ready_events(before, "later")
  assert_eq(ready.map(event => event.work_item_id), [
    "independent-a", "independent-b",
  ])
  assert_eq(ready.map(event => event.sequence), [
    before.last_sequence + 1,
    before.last_sequence + 2,
  ])
  for event in ready {
    events.push(event)
  }
  let after = readiness_restore(events)
  assert_eq(after.items[0].status, @moonflow.Blocked)
  assert_eq(after.items[0].attempt_status, "unknown")
  assert_eq(after.items[0].attempt_count, 1)
  assert_eq(after.items[1].status, @moonflow.Ready)
  assert_eq(after.items[2].status, @moonflow.Ready)
}
