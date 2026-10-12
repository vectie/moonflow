///|
fn comparison_other_run(events : Array[RuntimeEvent]) -> Array[RuntimeEvent] {
  events.map(e => {
    ..e,
    run_id: "flow-selene-r2",
    declaration_revision: "r2",
    source_digest: "sha256:selene-r2",
  })
}

///|
fn comparison_report(
  before : Array[RuntimeEvent],
  after : Array[RuntimeEvent],
) -> @moonflow.RunComparisonV1 raise {
  @moonflow.compare_run_events_v1(
    "flow-selene-r1", before, "flow-selene-r2", after,
  )
}

///|
fn comparison_field(row : Json?, key : String) -> Json raise {
  guard row is Some(Object(fields)) else { fail("expected item snapshot") }
  guard fields.get(key) is Some(value) else { fail("expected item field") }
  value
}

///|
test "comparison unchanged item excludes changed run head and collapses duplicate delivery" {
  let before = history_accepted_events()
  let after = comparison_other_run(before)
  after.push(after[0])
  let result = comparison_report(before, after)
  assert_eq(result.contract_id, "moonflow.run-comparison.v1")
  assert_eq(result.unchanged_count, 1)
  assert_eq(result.changed_count, 0)
  assert_eq(result.rows[0].changed_fields, [])
  assert_eq(result.before_head.declaration_revision, "r1")
  assert_eq(result.after_head.declaration_revision, "r2")
  assert_eq(result.after_head.last_sequence, 6)
  assert_eq(result.rows[0].before, result.rows[0].after)
  assert_eq(result.rows[0].retained_artifacts_added, [])
}

///|
test "comparison pairs renamed work by declaration and reports exact declaration changes" {
  let before = owner_test_events()
  let after = comparison_other_run(before).map(e => {
    ..e,
    work_item_id: if e.work_item_id == "research" {
      "renamed"
    } else {
      e.work_item_id
    },
  })
  after[1] = {
    ..after[1],
    acceptance_criteria: ["changed criterion"],
    input_artifacts: ["input/second.json"],
    timeout_ms: 2000,
  }
  let report = comparison_report(before, after)
  assert_eq(report.changed_count, 1)
  assert_eq(report.added_count, 0)
  assert_eq(report.removed_count, 0)
  assert_eq(report.rows[0].changed_fields, [
    "work_item_id", "acceptance_criteria", "input_artifacts", "timeout_ms",
  ])
  assert_eq(comparison_field(report.rows[0].before, "work_item_id"), "research")
  assert_eq(comparison_field(report.rows[0].after, "work_item_id"), "renamed")
}

///|
test "comparison uses declaration identity and before order followed by after-only order" {
  let before = [
    event(0, "created", RunCreated),
    event(1, "old-a", ItemRegistered, work_item_id="a", declaration_id="old-a"),
    event(2, "keep", ItemRegistered, work_item_id="keep", declaration_id="keep"),
    event(3, "old-b", ItemRegistered, work_item_id="b", declaration_id="old-b"),
  ]
  let after = comparison_other_run([
    event(0, "created", RunCreated),
    event(1, "new-b", ItemRegistered, work_item_id="b", declaration_id="new-b"),
    event(2, "keep", ItemRegistered, work_item_id="keep", declaration_id="keep"),
    event(3, "new-a", ItemRegistered, work_item_id="a", declaration_id="new-a"),
  ])
  let report = comparison_report(before, after)
  assert_eq(report.rows.map(r => r.declaration_id), [
    "old-a", "keep", "old-b", "new-b", "new-a",
  ])
  assert_eq(report.rows.map(r => r.change), [
    "removed", "unchanged", "removed", "added", "added",
  ])
  assert_eq(report.added_count, 2)
  assert_eq(report.removed_count, 2)
  assert_true(report.rows[0].to_json() is { "after": Null, .. })
  assert_true(report.rows[3].to_json() is { "before": Null, .. })
  assert_eq(report.rows[0].changed_fields, [])
  let reverse = @moonflow.compare_run_events_v1(
    "flow-selene-r2", after, "flow-selene-r1", before,
  )
  assert_eq(reverse.rows.map(r => r.declaration_id), [
    "new-b", "keep", "new-a", "old-a", "old-b",
  ])
  assert_eq(reverse.rows[0].change, "removed")
}

///|
test "comparison unknown outcome to review retains exact receipt and artifact delta without acceptance" {
  let before = owner_test_events()
  before.push(owner_test_result("unknown"))
  let after = comparison_other_run(owner_test_events())
  after.push(comparison_other_run([owner_test_result("succeeded")])[0])
  let report = comparison_report(before, after)
  assert_eq(report.before_head.run_outcome, "blocked")
  assert_eq(report.after_head.run_outcome, "review")
  let row = report.rows[0]
  assert_eq(comparison_field(row.before, "attempt_status"), "unknown")
  assert_eq(comparison_field(row.after, "attempt_status"), "succeeded")
  assert_eq(comparison_field(row.after, "review_id"), "")
  assert_true(row.changed_fields.contains("output_digest"))
  assert_true(row.changed_fields.contains("blocker"))
  assert_eq(row.retained_artifacts_added, [])
  let text = @moonflow.run_comparison_text_v1(report)
  assert_true(text.contains("\"unknown\" -> \"succeeded\""))
  assert_true(text.contains("customer approval or payment"))
}

///|
test "comparison retains checkpoint reuse rather than treating it as another attempt" {
  let before = history_accepted_events()
  let after = comparison_other_run([before[0], before[1], before[2]])
  after.push({
    ..after[2],
    sequence: 3,
    event_id: "reused",
    kind: CheckpointReused,
    result_id: "result-confirmed",
    attempt_id: "attempt-1",
    output_digest: "sha256:output",
    detail: "review-1",
    artifact_id: "evidence/review.json",
    authority_id: "reviewer-1",
    output_artifacts: ["evidence/exact-output.json"],
  })
  let report = comparison_report(before, after)
  assert_eq(report.after_head.run_outcome, "accepted")
  assert_eq(
    comparison_field(report.rows[0].after, "attempt_status"),
    "checkpoint-reused",
  )
  assert_eq(comparison_field(report.rows[0].after, "attempt_count"), 0)
  assert_eq(comparison_field(report.rows[0].after, "review_id"), "review-1")
  assert_true(report.rows[0].changed_fields.contains("attempt_status"))
  assert_true(report.rows[0].changed_fields.contains("attempt_count"))
}

///|
test "comparison tracks directional retained artifact additions removals and review rejection" {
  let before = history_accepted_events()
  let after = comparison_other_run(owner_test_events())
  after.push({
    ..comparison_other_run([owner_test_result("succeeded")])[0],
    output_artifacts: ["output/new.json"],
  })
  after.push({
    ..comparison_other_run([
      event(
        5,
        "rejected",
        ItemBlocked,
        work_item_id="research",
        error_kind="acceptance-rejected",
        result_id="review-rejected",
        artifact_id="review/new.json",
        authority_id="reviewer-new",
        detail="Need a revision",
      ),
    ])[0],
  })
  let report = comparison_report(before, after)
  let row = report.rows[0]
  assert_eq(row.retained_artifacts_added, ["output/new.json", "review/new.json"])
  assert_eq(row.retained_artifacts_removed, [
    "evidence/exact-output.json", "evidence/review.json",
  ])
  assert_eq(comparison_field(row.after, "review_id"), "review-rejected")
  assert_eq(comparison_field(row.after, "status"), "blocked")
  let reverse = @moonflow.compare_run_events_v1(
    "flow-selene-r2", after, "flow-selene-r1", before,
  )
  assert_eq(
    reverse.rows[0].retained_artifacts_added,
    row.retained_artifacts_removed,
  )
  assert_eq(
    reverse.rows[0].retained_artifacts_removed,
    row.retained_artifacts_added,
  )
}

///|
test "comparison snapshots cannot be changed through caller arrays or other side" {
  let before = history_accepted_events()
  let after = comparison_other_run(before)
  let report = comparison_report(before, after)
  let json = report.to_json().stringify()
  before[1].input_artifacts.push("later-input")
  before[1].acceptance_criteria.push("later-criterion")
  before[5].output_artifacts.push("later-output")
  assert_eq(report.to_json().stringify(), json)
  guard report.rows[0].before is Some(Object(fields)) else {
    fail("missing before")
  }
  guard fields["retained_artifacts"] is Array(artifacts) else {
    fail("missing artifacts")
  }
  artifacts.push("mutated-report")
  assert_eq(comparison_field(report.rows[0].after, "retained_artifacts"), [
    "evidence/exact-output.json", "evidence/review.json",
  ])
}

///|
test "comparison rejects unrelated empty ambiguous and corrupt histories on either side" {
  let before = history_accepted_events()
  let after = comparison_other_run(before)
  assert_true(
    (try? @moonflow.compare_run_events_v1(
      "flow-selene-r1", before, "flow-selene-r1", before,
    ))
    is Err(_),
  )
  assert_true((try? comparison_report([], after)) is Err(_))
  assert_true((try? comparison_report(before, [])) is Err(_))
  assert_true(
    (try? comparison_report(
      before,
      after.map(e => { ..e, book_id: "another-book", }),
    ))
    is Err(_),
  )
  for
    bad in [
      { ..after[0], event_id: "conflict", },
      { ..after[0], source_digest: "sha256:conflict", },
      {
        ..after[1],
        sequence: 7,
        event_id: "duplicate-declaration",
        work_item_id: "another-item",
      },
      {
        ..after[1],
        sequence: 8,
        event_id: "gap",
        work_item_id: "another-item",
      },
    ] {
    let invalid = after.copy()
    invalid.push(bad)
    assert_true((try? comparison_report(before, invalid)) is Err(_))
    assert_true(
      (try? @moonflow.compare_run_events_v1(
        "flow-selene-r2", invalid, "flow-selene-r1", before,
      ))
      is Err(_),
    )
  }
}

///|
test "comparison supports empty declared runs and bounds duplicate events and item counts" {
  let before = [event(0, "created", RunCreated)]
  let after = comparison_other_run(before)
  assert_eq(comparison_report(before, after).rows, [])
  let duplicates = Array::make(4096, before[0])
  assert_eq(comparison_report(duplicates, after).rows, [])
  duplicates.push(before[0])
  assert_true((try? comparison_report(duplicates, after)) is Err(_))
  for i in 0..<256 {
    before.push(
      event(i + 1, "register-\{i}", ItemRegistered, work_item_id="item-\{i}"),
    )
  }
  assert_eq(comparison_report(before, after).removed_count, 256)
  before.push(event(257, "too-many", ItemRegistered, work_item_id="too-many"))
  assert_true((try? comparison_report(before, after)) is Err(_))
}

///|
test "comparison quotes control characters and treats list order as an exact difference" {
  let before = [
    event(0, "created", RunCreated),
    event(
      1,
      "register",
      ItemRegistered,
      work_item_id="row\n雪",
      declaration_id="decl\u001b",
      acceptance_criteria=["first", "second"],
    ),
  ]
  let after = comparison_other_run(before)
  after[1] = { ..after[1], acceptance_criteria: ["second", "first"], }
  let report = comparison_report(before, after)
  assert_eq(report.rows[0].changed_fields, ["acceptance_criteria"])
  let text = @moonflow.run_comparison_text_v1(report)
  assert_true(text.contains("row\\n雪"))
  assert_false(text.contains("row\n雪"))
  assert_false(text.contains("\u001b"))
}

///|
test "comparison detects every declared field independently" {
  let before = [
    event(0, "created", RunCreated),
    event(1, "register", ItemRegistered, work_item_id="item"),
    event(2, "register-other", ItemRegistered, work_item_id="item-other"),
  ]
  let changes : Array[(String, Json)] = [
    ("work_item_id", "renamed"),
    ("product_id", "other-product"),
    ("requested_authority", "sandbox-execution"),
    ("acceptance_criteria", ["changed criterion"]),
    ("operation", "other-operation"),
    ("input_contracts", ["input.v2"]),
    ("output_contracts", ["output.v2"]),
    ("required_claim", "digital-artifact"),
    ("input_artifacts", ["input/second.json"]),
    ("timeout_ms", 2000),
    ("depends_on", ["item-other"]),
  ]
  for pair in changes {
    let (key, value) = pair
    let after = comparison_other_run(before)
    let changed = @moonflow.runtime_event_json(after[1])
    guard changed is Object(fields) else { fail("expected event") }
    fields[key] = value
    after[1] = @moonflow.decode_runtime_event(changed)
    let report = comparison_report(before, after)
    assert_eq(report.rows[0].changed_fields, [key])
    assert_eq(comparison_field(report.rows[0].after, key), value)
  }
}

///|
test "comparison exposes changed recorded digest even when artifact paths are identical" {
  let before = history_accepted_events()
  let after = comparison_other_run(before).map(e => {
    ..e,
    output_digest: if e.output_digest.is_empty() {
      ""
    } else {
      "sha256:new-output"
    },
  })
  let report = comparison_report(before, after)
  assert_eq(report.rows[0].changed_fields, ["output_digest"])
  assert_eq(report.rows[0].retained_artifacts_added, [])
  assert_eq(report.rows[0].retained_artifacts_removed, [])
  assert_eq(comparison_field(report.rows[0].after, "status"), "accepted")
}
