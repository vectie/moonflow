///|
fn mermaid_bindings() -> Json {
  {
    "contract_id": "moonflow.mermaid-plan-bindings.v1",
    "nodes": {
      "gather": {
        "template_work_item_id": "root",
        "input_artifacts": ["requests/root.json"],
      },
      "build-red": {
        "template_work_item_id": "left",
        "input_artifacts": ["requests/red.json"],
      },
      "build-blue": {
        "template_work_item_id": "right",
        "input_artifacts": ["requests/blue.json"],
      },
      "publish": {
        "template_work_item_id": "join",
        "input_artifacts": ["requests/report.json"],
        "acceptance_criteria": ["Review the combined result"],
        "timeout_ms": 12000,
      },
    },
  }
}

///|
fn mermaid_diagram() -> String {
  (
    #|%% A diagram authored outside MoonFlow
    #|flowchart LR
    #|gather[Gather inputs] --> build-red[Red branch] --> publish["Review café"]
    #|gather --> build-blue[Blue branch]
    #|build-blue --> publish
  )
}

///|
fn mermaid_import(
  text : String,
  bindings? : Json = mermaid_bindings(),
) -> @moonflow.MermaidPlanImportV1 raise {
  @moonflow.declared_plan_from_mermaid_v1(
    plan_diamond_graph(),
    bindings,
    text,
    "mermaid",
    "2026-07-31T00:00:00Z",
  )
}

///|
test "Mermaid diamond creates editable exact-template work with original diagram" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let result = @moonflow.declared_plan_from_mermaid_v1(
    source,
    mermaid_bindings(),
    mermaid_diagram(),
    "mermaid",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(result.diagram, mermaid_diagram())
  assert_eq(result.direction, "LR")
  assert_eq(result.nodes.map(node => node.node_id), [
    "gather", "build-red", "publish", "build-blue",
  ])
  assert_eq(result.nodes.map(node => node.line_number), [3, 3, 3, 4])
  assert_eq(result.nodes[2].label, "Review café")
  assert_eq(result.edges.length(), 4)
  assert_eq(result.draft.edits[2].depends_on, ["build-red", "build-blue"])
  assert_eq(result.draft.edits[2].timeout_ms, 12000)
  assert_eq(result.draft.edits[2].acceptance_criteria, [
    "Review the combined result",
  ])
  assert_eq(result.draft.edits[1].acceptance_criteria, [
    "Review the exact left artifact",
  ])
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let prepared = @moonflow.prepare_declared_plan_v1(
    result.draft,
    catalog,
    "2026-07-31T00:00:00Z",
  )
  let run = @moonflow.replay(
    prepared.preparation_id,
    @moonflow.events_from_work_graph(prepared.graph),
  )
  for item in run.items {
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.required_claim, "digital-artifact")
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
  }
  let edited = @moonflow.edit_declared_plan_item_v1(result.draft, {
    ..result.draft.edits[2],
    timeout_ms: 24000,
  })
  assert_true(
    @moonflow.prepare_declared_plan_v1(edited, catalog, "2026-07-31T00:00:00Z").preparation_id !=
    prepared.preparation_id,
  )
  assert_eq(source.stringify(), before)
  assert_eq(
    @moonflow.decode_declared_plan_draft_v1(result.draft.to_json()),
    result.draft,
  )
}

///|
test "Mermaid accepts orientations isolated nodes forward references and last label" {
  for direction in ["TB", "TD", "BT", "LR", "RL"] {
    let diagram = "graph " +
      direction +
      "\r\n\r\n%% comment\r\npublish\r\nbuild-blue --> publish\r\ngather --> build-blue\r\ngather --> build-red\r\nbuild-red --> publish\r\npublish[Earlier]\r\npublish[Latest]\r\n"
    let result = mermaid_import(diagram)
    assert_eq(result.nodes[0].node_id, "publish")
    assert_eq(result.nodes[0].label, "Latest")
    assert_eq(result.nodes[0].line_number, 4)
    assert_eq(result.draft.edits[0].depends_on, ["build-blue", "build-red"])
    assert_eq(result.direction, direction)
  }
  let disconnected = mermaid_import(
    "flowchart TD\ngather\nbuild-red\nbuild-blue\npublish",
  )
  assert_eq(disconnected.edges.length(), 0)
  assert_true(disconnected.draft.edits.all(edit => edit.depends_on.is_empty()))
}

///|
test "Mermaid deterministic identity separates diagram text and exact materialized work" {
  let first = mermaid_import(mermaid_diagram())
  assert_eq(first, mermaid_import(mermaid_diagram()))
  let presentation = mermaid_import(
    mermaid_diagram().replace(old="Gather inputs", new="Collect source files"),
  )
  assert_eq(first.draft, presentation.draft)
  assert_true(first.diagram_digest != presentation.diagram_digest)
  let no_labels = mermaid_import(
    "graph TB\ngather --> build-red --> publish\ngather --> build-blue\nbuild-blue --> publish",
  )
  assert_eq(first.draft, no_labels.draft)
  assert_eq(first.diagram_digest.length(), 71)
  assert_eq(first.bindings_digest.length(), 71)
}

///|
test "Mermaid refuses cycles duplicate edges self edges and unsupported semantics" {
  for
    text in [
      "",
      "flowchart LR",
      "sequenceDiagram\ngather",
      "flowchart LR;\ngather",
      "flowchart LR\ngather --> gather",
      mermaid_diagram() + "\npublish --> gather",
      mermaid_diagram() + "\ngather --> build-red",
      "flowchart LR\ngather -->|approved| publish",
      "flowchart LR\ngather --- publish",
      "flowchart LR\ngather -.-> publish",
      "flowchart LR\ngather ---> publish",
      "flowchart LR\ngather ==> publish",
      "flowchart LR\ngather & build-red --> publish",
      "flowchart LR\ngather{Decision} --> publish",
      "flowchart LR\nsubgraph group\ngather\nend",
      "flowchart LR\ngather; publish",
      "flowchart LR\ngather --> publish %% inline",
      "flowchart LR\n%%{init: {}}%%\ngather",
      "flowchart LR\nclick gather callback",
      "flowchart LR\nclassDef red fill:red",
      "flowchart LR\ngather[bad <b>label</b>]",
      "flowchart LR\ngather[\"unterminated]",
      "flowchart LR\ngather[]",
      "flowchart LR\nend",
      "\u{FEFF}" + mermaid_diagram(),
    ] {
    assert_true((try? mermaid_import(text)) is Err(_), msg=text)
  }
}

///|
test "Mermaid requires every binding exactly and freezes contracts" {
  let top_cases : Array[(String, Json)] = [
    ("contract_id", "unknown"),
    ("operation", "new/operation@1.0.0"),
    ("nodes", Json::null()),
  ]
  for (key, value) in top_cases {
    guard mermaid_bindings() is Object(fields) else { fail("bindings") }
    fields[key] = value
    assert_true(
      (try? mermaid_import(mermaid_diagram(), bindings=Json::object(fields)))
      is Err(_),
    )
  }
  let node_cases : Array[(String, Json)] = [
    ("template_work_item_id", "unknown"),
    ("operation", "untrusted/run@1.0.0"),
    ("depends_on", ["gather"]),
    ("input_artifacts", ["../outside"]),
    ("input_artifacts", []),
    ("input_artifacts", ["a", "a"]),
    ("acceptance_criteria", []),
    ("timeout_ms", 0),
    ("timeout_ms", 1.5),
    ("timeout_ms", "12000"),
    ("timeout_ms", Json::null()),
  ]
  for (key, value) in node_cases {
    let bindings = mermaid_bindings()
    guard bindings is { "nodes": { "publish": Object(fields), .. }, .. } else {
      fail("bindings")
    }
    fields[key] = value
    assert_true(
      (try? mermaid_import(mermaid_diagram(), bindings~)) is Err(_),
      msg=key,
    )
  }
  let missing = mermaid_bindings()
  guard missing is { "nodes": Object(fields), .. } else { fail("bindings") }
  fields.remove("publish")
  assert_true(
    (try? mermaid_import(mermaid_diagram(), bindings=missing)) is Err(_),
  )
  fields["absent"] = {
    "template_work_item_id": "join",
    "input_artifacts": ["a"],
  }
  assert_true(
    (try? mermaid_import(mermaid_diagram(), bindings=missing)) is Err(_),
  )
}

///|
test "Mermaid node byte and arrow limits remain bounded" {
  let nodes : Map[String, Json] = Map([])
  let lines : Array[String] = ["flowchart TD"]
  for index in 0..<256 {
    let id = "job_\{index}"
    nodes[id] = {
      "template_work_item_id": "left",
      "input_artifacts": ["a.json"],
    }
    lines.push(id)
  }
  let bindings : Json = {
    "contract_id": "moonflow.mermaid-plan-bindings.v1",
    "nodes": nodes.to_json(),
  }
  assert_eq(mermaid_import(lines.join("\n"), bindings~).nodes.length(), 256)
  lines.push("job_256")
  assert_true((try? mermaid_import(lines.join("\n"), bindings~)) is Err(_))
  assert_true((try? mermaid_import(" ".repeat(1048577))) is Err(_))
  let unicode = "%%" + "茶".repeat(349526)
  assert_true(unicode.length() < 1048576)
  assert_true((try? mermaid_import(unicode)) is Err(_))
  let many = ["flowchart LR"]
  for from in 0..<128 {
    for to in 128..<161 {
      many.push("job_\{from} --> job_\{to}")
    }
  }
  try mermaid_import(many.join("\n"), bindings~) catch {
    error => assert_true(error.to_string().contains("4096 arrows"))
  } noraise {
    _ => fail("too many arrows accepted")
  }
}
