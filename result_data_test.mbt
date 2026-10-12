///|
fn result_data_test_mapping(
  pointer? : String = "/metrics/score",
  index? : Int = 0,
) -> Json {
  {
    "contract_id": "moonflow.result-data-mapping.v1",
    "output_artifact_index": index,
    "columns": [{ "name": "score", "pointer": pointer }],
  }
}

///|
fn result_data_test_run(
  status? : String = "succeeded",
) -> @moonflow.RunProjection raise {
  let events = owner_test_events()
  events.push(owner_test_result(status))
  @moonflow.replay("flow-selene-r1", events)
}

///|
test "result values extract typed data and retain exact current result and independent heads" {
  let events = owner_test_events()
  events.push(owner_test_result("succeeded"))
  events.push(
    event(
      5,
      "attached",
      ArtifactAttached,
      work_item_id="research",
      artifact_id="evidence/not-output.json",
    ),
  )
  events.push(
    event(
      6,
      "accepted",
      ItemAccepted,
      work_item_id="research",
      detail="review-1",
      artifact_id="review.json",
      authority_id="reviewer",
      result_id="result-1",
      attempt_id="attempt-1",
      output_digest="sha256:output",
    ),
  )
  let accepted = @moonflow.replay("flow-selene-r1", events)
  let pending = @moonflow.replay(
    "flow-selene-r2",
    comparison_other_run(owner_test_events()),
  )
  let mapping : Json = {
    "contract_id": "moonflow.result-data-mapping.v1",
    "output_artifact_index": 0,
    "columns": [
      { "name": "score", "pointer": "/metrics/score" },
      { "name": "name", "pointer": "/name" },
      { "name": "ok", "pointer": "/ok" },
      { "name": "note", "pointer": "/note" },
      { "name": "tags", "pointer": "/tags" },
      { "name": "escaped", "pointer": "/a~1b/~0/0" },
      { "name": "object", "pointer": "/metrics" },
    ],
  }
  let bytes : Bytes = b"{\"metrics\":{\"score\":9.5},\"name\":\"=quoted,\\\"name\\\"\\nline\",\"ok\":true,\"note\":null,\"tags\":[1,false],\"a/b\":{\"~\":[42]}}"
  let artifacts : Map[String, Bytes] = { "evidence/exact-output.json": bytes }
  let before = @moonflow.projection_json(accepted).stringify()
  let table = @moonflow.result_data_table_v1(
    [pending, accepted],
    mapping,
    artifacts,
  )
  assert_eq(table.runs.map(r => r.run_id), ["flow-selene-r2", "flow-selene-r1"])
  assert_eq(table.rows[0].data_status, "no-successful-attempt")
  assert_true(table.rows[0].values["score"] is Null)
  let row = table.rows[1]
  assert_eq(row.source.status, "accepted")
  assert_eq(row.source.review_id, "review-1")
  assert_eq(row.result_event_id, "owner-result")
  assert_eq(row.artifact_ref, "evidence/exact-output.json")
  assert_eq(row.observed_size_bytes, bytes.length())
  assert_true(row.observed_sha256.has_prefix("sha256:"))
  assert_false(row.observed_sha256 == row.source.output_digest)
  assert_eq(row.values["score"], (9.5 : Json))
  assert_eq(row.values["ok"], (true : Json))
  assert_true(row.values["note"] is Null)
  assert_eq(row.values["tags"], ([1, false] : Json))
  assert_eq(row.values["escaped"], (42 : Json))
  assert_eq(row.values["object"], ({ "score": 9.5 } : Json))
  assert_eq(@moonflow.result_data_sources_v1([accepted], mapping), [
    "evidence/exact-output.json",
  ])
  let csv = @moonflow.result_data_csv_v1(table)
  assert_true(csv.contains("\"value:score\""))
  assert_true(csv.contains("\"[1,false]\""))
  assert_true(csv.contains("\"null\""))
  assert_eq(before, @moonflow.projection_json(accepted).stringify())
  accepted.items[0].artifacts.push("later")
  assert_false(row.source.retained_artifacts.contains("later"))
}

///|
test "result selection follows current success rather than historical or attached artifacts" {
  let events = owner_test_events()
  events.push({
    ..owner_test_result("unknown"),
    output_artifacts: ["stale.json"],
  })
  events.push({
    ..owner_test_result("succeeded"),
    sequence: 5,
    event_id: "resolved",
    output_artifacts: ["cover.txt", "metrics.json"],
  })
  events.push(
    event(
      6,
      "extra",
      ArtifactAttached,
      work_item_id="research",
      artifact_id="unrelated.json",
    ),
  )
  let run = @moonflow.replay("flow-selene-r1", events)
  let mapping = result_data_test_mapping(index=1)
  let table = @moonflow.result_data_table_v1([run], mapping, {
    "metrics.json": b"{\"metrics\":{\"score\":2}}",
  })
  assert_eq(table.rows[0].artifact_ref, "metrics.json")
  assert_eq(table.rows[0].result_event_id, "resolved")
  assert_eq(@moonflow.result_data_sources_v1([run], mapping), ["metrics.json"])
  // A later new attempt must not reuse the old success's values.
  let retried = owner_test_events()
  retried.push(owner_test_result("succeeded"))
  retried.push(
    event(
      5,
      "revision-requested",
      ItemBlocked,
      work_item_id="research",
      detail="changes requested",
    ),
  )
  retried.push(event(6, "retry-ready", ItemReady, work_item_id="research"))
  retried.push({
    ..retried[3],
    sequence: 7,
    event_id: "retry",
    attempt_id: "attempt-2",
    request_id: "request-2",
    idempotency_key: "key-2",
  })
  let waiting = @moonflow.replay("flow-selene-r1", retried)
  let empty = @moonflow.result_data_table_v1([waiting], mapping, {})
  assert_eq(empty.rows[0].source.attempt_id, "attempt-2")
  assert_eq(empty.rows[0].data_status, "no-successful-attempt")
}

///|
test "result data keeps failed unknown and checkpoint evidence out of extracted values" {
  for status in ["failed", "unknown"] {
    let table = @moonflow.result_data_table_v1(
      [result_data_test_run(status~)],
      result_data_test_mapping(),
      {},
    )
    assert_eq(table.rows[0].data_status, "no-successful-attempt")
    assert_eq(table.rows[0].artifact_ref, "")
  }
  let checkpoint = [
    event(0, "created", RunCreated),
    event(1, "registered", ItemRegistered, work_item_id="research"),
  ]
  checkpoint.push(
    event(
      2,
      "reused",
      CheckpointReused,
      work_item_id="research",
      detail="parent-checkpoint",
      artifact_id="review.json",
      authority_id="reviewer",
      result_id="result-old",
      attempt_id="attempt-old",
      output_digest="sha256:old",
      output_artifacts=["old-output.json", "old-review.json"],
    ),
  )
  let run = @moonflow.replay("flow-selene-r1", checkpoint)
  let table = @moonflow.result_data_table_v1(
    [run],
    result_data_test_mapping(),
    {},
  )
  assert_eq(table.rows[0].data_status, "checkpoint-only")
  assert_eq(table.rows[0].source.status, "accepted")
  assert_eq(
    @moonflow.result_data_sources_v1([run], result_data_test_mapping()),
    [],
  )
}

///|
test "result mapping filters exact operation and retains empty run identity" {
  let mapping : Json = {
    "contract_id": "moonflow.result-data-mapping.v1",
    "operation": "unmatched@1",
    "output_artifact_index": 0,
    "columns": [{ "name": "all", "pointer": "" }],
  }
  let table = @moonflow.result_data_table_v1(
    [result_data_test_run()],
    mapping,
    {},
  )
  assert_eq(table.rows.length(), 0)
  assert_eq(table.runs.length(), 1)
  assert_true(@moonflow.result_data_csv_v1(table).contains("value:all"))
  let run = result_data_test_run()
  assert_true((try? @moonflow.result_data_table_v1([], mapping, {})) is Err(_))
  assert_true(
    (try? @moonflow.result_data_table_v1([run, run], mapping, {})) is Err(_),
  )
  let root = @moonflow.result_data_table_v1(
    [run],
    result_data_test_mapping(pointer=""),
    { "evidence/exact-output.json": b"[1,2]" },
  )
  assert_eq(root.rows[0].values["score"], ([1, 2] : Json))
}

///|
test "result data refuses missing malformed selected data and invalid pointers without substitution" {
  let run = result_data_test_run()
  let mapping = result_data_test_mapping()
  for
    artifacts in [
      {},
      { "evidence/exact-output.json": b"{broken" },
      { "evidence/exact-output.json": b"{\"metrics\":{}}" },
    ] {
    assert_true(
      (try? @moonflow.result_data_table_v1([run], mapping, artifacts)) is Err(_),
    )
  }
  for
    pointer in [
      "not-a-pointer", "/bad~2escape", "/a/01", "/a/-", "/a/9", "/a/0/nested",
    ] {
    assert_true(
      (try? @moonflow.result_data_table_v1(
        [run],
        result_data_test_mapping(pointer~),
        { "evidence/exact-output.json": b"{\"a\":[1]}" },
      ))
      is Err(_),
    )
  }
  assert_true(
    (try? @moonflow.result_data_sources_v1(
      [run],
      result_data_test_mapping(index=2),
    ))
    is Err(_),
  )
  let unsafe_events = owner_test_events()
  unsafe_events.push({
    ..owner_test_result("succeeded"),
    output_artifacts: ["../outside.json"],
  })
  let unsafe_run = @moonflow.replay("flow-selene-r1", unsafe_events)
  assert_true(
    (try? @moonflow.result_data_sources_v1([unsafe_run], mapping)) is Err(_),
  )
}

///|
test "result mappings validate complete schema before any source requests" {
  let run = result_data_test_run(status="unknown")
  let invalid : Array[Json] = [
    {
      "contract_id": "other",
      "output_artifact_index": 0,
      "columns": [{ "name": "a", "pointer": "" }],
    },
    {
      "contract_id": "moonflow.result-data-mapping.v1",
      "output_artifact_index": 0.5,
      "columns": [{ "name": "a", "pointer": "" }],
    },
    {
      "contract_id": "moonflow.result-data-mapping.v1",
      "output_artifact_index": -1,
      "columns": [{ "name": "a", "pointer": "" }],
    },
    {
      "contract_id": "moonflow.result-data-mapping.v1",
      "output_artifact_index": 256,
      "columns": [{ "name": "a", "pointer": "" }],
    },
    {
      "contract_id": "moonflow.result-data-mapping.v1",
      "output_artifact_index": 0,
      "columns": [],
    },
    {
      "contract_id": "moonflow.result-data-mapping.v1",
      "output_artifact_index": 0,
      "columns": [
        { "name": "a", "pointer": "" },
        { "name": "a", "pointer": "/b" },
      ],
    },
    {
      "contract_id": "moonflow.result-data-mapping.v1",
      "output_artifact_index": 0,
      "columns": [{ "name": "a", "pointer": "", "optional": true }],
    },
    {
      "contract_id": "moonflow.result-data-mapping.v1",
      "output_artifact_index": 0,
      "columns": [{ "name": "a", "pointer": "" }],
      "fallback": true,
    },
  ]
  for mapping in invalid {
    assert_true(
      (try? @moonflow.result_data_sources_v1([run], mapping)) is Err(_),
    )
  }
}

///|
test "shared output references are loaded once with per-run identities and explicit file bounds" {
  let first = result_data_test_run()
  let second = @moonflow.replay(
    "flow-selene-r2",
    comparison_other_run(first.applied_events),
  )
  let mapping = result_data_test_mapping(pointer="")
  assert_eq(@moonflow.result_data_sources_v1([first, second], mapping), [
    "evidence/exact-output.json",
  ])
  let table = @moonflow.result_data_table_v1([first, second], mapping, {
    "evidence/exact-output.json": b"null",
  })
  assert_eq(table.rows.length(), 2)
  assert_eq(
    table.rows[0].observed_sha256,
    "sha256:74234e98afe7498fb5daf1f36ac2d78acc339464f950703b8c019892f982b90b",
  )
  assert_eq(table.rows[0].observed_sha256, table.rows[1].observed_sha256)
  assert_eq(table.rows[0].data_status, "extracted")
  assert_true(table.rows[0].values["score"] is Null)
  assert_eq(table.rows[1].source.run_id, "flow-selene-r2")
  assert_true(
    (try? @moonflow.result_data_sources_v1(Array::make(65, first), mapping))
    is Err(_),
  )
  let too_large = Bytes::make(1048577, 32)
  assert_true(
    (try? @moonflow.result_data_table_v1([first], mapping, {
      "evidence/exact-output.json": too_large,
    }))
    is Err(_),
  )
  assert_true(
    (try? @moonflow.result_data_table_v1([first], mapping, {
      "evidence/exact-output.json": b"\xff",
    }))
    is Err(_),
  )
}
