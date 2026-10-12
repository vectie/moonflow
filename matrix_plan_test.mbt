///|
fn matrix_fixture() -> Json {
  {
    "contract_id": "moonflow.matrix-plan.v1",
    "item_prefix": "study",
    "template_work_item_id": "left",
    "axes": [
      {
        "name": "size",
        "values": [
          { "key": "small", "value": 12.5 },
          { "key": "wide", "value": 25 },
        ],
      },
      {
        "name": "style",
        "values": [
          { "key": "plain", "value": null },
          {
            "key": "rich",
            "value": { "label": "雪, \"red\"\n", "flags": [true, false] },
          },
        ],
      },
    ],
    "bindings": [
      { "target_pointer": "/request_id", "value_pointer": "/id" },
      { "target_pointer": "/size", "value_pointer": "/parameters/size" },
      { "target_pointer": "/style", "value_pointer": "/parameters/style" },
      { "target_pointer": "/label", "value_pointer": "/keys/style" },
    ],
  }
}

///|
fn matrix_request() -> Json {
  {
    "request_id": "template",
    "size": 0,
    "style": {},
    "label": "",
    "retained": [1, "exact"],
  }
}

///|
fn matrix_import(value : Json) -> @moonflow.MatrixPlanImportV1 raise {
  @moonflow.declared_plan_from_matrix_v1(
    plan_diamond_graph(),
    value,
    matrix_request(),
    "matrix",
    "2026-07-31T00:00:00Z",
  )
}

///|
test "matrix generates every typed combination in last axis fastest order" {
  let result = matrix_import(matrix_fixture())
  let expected_ids = [
    "study--small--plain", "study--small--rich", "study--wide--plain", "study--wide--rich",
  ]
  assert_eq(result.payloads.artifacts.map(a => a.work_item_id), expected_ids)
  assert_eq(result.combinations.length(), 4)
  for i, artifact in result.payloads.artifacts {
    assert_eq(@json.parse(artifact.json_text), {
      "request_id": expected_ids[i].to_json(),
      "size": if i < 2 {
        (12.5 : Double).to_json()
      } else {
        (25 : Int).to_json()
      },
      "style": if i % 2 == 0 {
        Json::null()
      } else {
        { "label": "雪, \"red\"\n", "flags": [true, false] }
      },
      "label": if i % 2 == 0 {
        "plain".to_json()
      } else {
        "rich".to_json()
      },
      "retained": [1, "exact"],
    })
    assert_eq(result.payloads.draft.edits[i].depends_on, [])
  }
  let prepared = @moonflow.prepare_declared_plan_v1(
    result.payloads.draft,
    @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
    "2026-07-31T00:00:00Z",
  )
  let run = @moonflow.replay(
    prepared.preparation_id,
    @moonflow.events_from_work_graph(prepared.graph),
  )
  assert_eq(run.items.length(), 4)
  for item in run.items {
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.required_claim, "digital-artifact")
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
  }
}

///|
test "matrix identity is deterministic and nested values are detached from caller" {
  let fixture = matrix_fixture()
  let result = matrix_import(fixture)
  assert_eq(result, matrix_import(matrix_fixture()))
  let before = result.to_json().stringify()
  guard fixture is Object(fields) else { fail("fixture") }
  guard fields["axes"] is Array(axes) else { fail("axes") }
  guard axes[1] is Object(axis) else { fail("axis") }
  guard axis["values"] is Array(values) else { fail("values") }
  guard values[1] is Object(choice) else { fail("choice") }
  guard choice["value"] is Object(value) else { fail("value") }
  value["label"] = "changed".to_json()
  assert_eq(result.to_json().stringify(), before)
  assert_true(matrix_import(fixture).matrix_digest != result.matrix_digest)
  let reordered = [axes[1], axes[0]]
  fields["axes"] = reordered.to_json()
  let changed_order = matrix_import(fixture)
  assert_eq(
    changed_order.payloads.artifacts[0].work_item_id,
    "study--plain--small",
  )
}

///|
test "matrix preflights the Cartesian bound and supports exactly 256 rows" {
  guard matrix_fixture() is Object(fields) else { fail("fixture") }
  let dimensions = Array::makei(16, i => {
    ({ "key": "v\{i}", "value": i.to_json() } : Json)
  })
  fields["axes"] = [
    { "name": "size", "values": dimensions.to_json() },
    { "name": "style", "values": dimensions.to_json() },
  ]
  let exact = matrix_import(Json::object(fields))
  assert_eq(exact.combinations.length(), 256)
  dimensions.push({ "key": "v16", "value": 16 })
  fields["axes"] = [
    { "name": "size", "values": dimensions.to_json() },
    { "name": "style", "values": dimensions.to_json() },
  ]
  assert_true((try? matrix_import(Json::object(fields))) is Err(_))
  fields["axes"] = [].to_json()
  assert_true((try? matrix_import(Json::object(fields))) is Err(_))
  fields["axes"] = Array::makei(9, i => {
    ({ "name": "a\{i}", "values": [{ "key": "one", "value": 1 }] } : Json)
  }).to_json()
  assert_true((try? matrix_import(Json::object(fields))) is Err(_))
}

///|
test "matrix rejects ambiguous identities duplicate axes and malformed choices" {
  for
    key in ["", "a--b", "a-", "-a", "../a", "with space", "雪", "x".repeat(65)] {
    guard matrix_fixture() is Object(fields) else { fail("fixture") }
    fields["item_prefix"] = key.to_json()
    assert_true((try? matrix_import(Json::object(fields))) is Err(_))
    fields["item_prefix"] = "study".to_json()
    fields["axes"] = [
      { "name": "size", "values": [{ "key": key.to_json(), "value": 1 }] },
    ]
    assert_true((try? matrix_import(Json::object(fields))) is Err(_))
  }
  let invalid_axes : Array[Json] = [
    [
      { "name": "same", "values": [{ "key": "a", "value": 1 }] },
      { "name": "same", "values": [{ "key": "b", "value": 2 }] },
    ],
    [{ "name": "bad/name", "values": [{ "key": "a", "value": 1 }] }],
    [{ "name": "size", "values": [] }],
    [
      {
        "name": "size",
        "values": [{ "key": "a", "value": 1 }, { "key": "a", "value": 2 }],
      },
    ],
    [{ "name": "size", "values": [{ "key": "a" }] }],
    [{ "name": "size", "values": [{ "key": "a", "value": 1, "extra": true }] }],
  ]
  for axes in invalid_axes {
    guard matrix_fixture() is Object(fields) else { fail("fixture") }
    fields["axes"] = axes.to_json()
    assert_true((try? matrix_import(Json::object(fields))) is Err(_))
  }
}

///|
test "matrix refuses invalid bindings source selection and overlong generated identities" {
  for
    binding in [
      { "target_pointer": "", "value_pointer": "/id" },
      { "target_pointer": "/missing", "value_pointer": "/id" },
      { "target_pointer": "/size", "value_pointer": "/parameters/unknown" },
    ] {
    guard matrix_fixture() is Object(fields) else { fail("fixture") }
    fields["bindings"] = [binding].to_json()
    assert_true((try? matrix_import(Json::object(fields))) is Err(_))
  }
  guard matrix_fixture() is Object(fields) else { fail("fixture") }
  fields["requested_authority"] = "expanded".to_json()
  assert_true((try? matrix_import(Json::object(fields))) is Err(_))
  fields.remove("requested_authority")
  fields["template_work_item_id"] = "absent".to_json()
  assert_true((try? matrix_import(Json::object(fields))) is Err(_))
  fields["template_work_item_id"] = "left".to_json()
  fields["item_prefix"] = "p".repeat(64).to_json()
  fields["axes"] = [
    {
      "name": "size",
      "values": [{ "key": "k".repeat(64).to_json(), "value": 1 }],
    },
  ]
  assert_true((try? matrix_import(Json::object(fields))) is Err(_))
}

///|
test "matrix rejects oversized expanded records without materializing payloads" {
  guard matrix_fixture() is Object(fields) else { fail("fixture") }
  fields["axes"] = [
    {
      "name": "size",
      "values": [{ "key": "big", "value": "x".repeat(550000).to_json() }],
    },
    {
      "name": "style",
      "values": [{ "key": "a", "value": null }, { "key": "b", "value": null }],
    },
  ]
  assert_true((try? matrix_import(Json::object(fields))) is Err(_))
}
