///|
fn mermaid_raw_binding(timeout : String) -> String {
  "{\"contract_id\":\"moonflow.mermaid-plan-bindings.v1\",\"nodes\":{\"one\":{\"template_work_item_id\":\"root\",\"input_artifacts\":[\"requests/root.json\"],\"timeout_ms\":" +
  timeout +
  "}}}"
}

///|
fn mermaid_raw_import(
  bindings : String,
  source? : String = plan_diamond_graph().stringify(),
) -> @moonflow.MermaidPlanImportV1 raise {
  @moonflow.declared_plan_from_mermaid_text_v1(
    source, bindings, "flowchart LR\none", "raw-mermaid", "2026-07-31T00:00:00Z",
  )
}

///|
test "Mermaid raw JSON refuses fractional timeouts that round to whole doubles" {
  for
    number in [
      "1.000000000000000001", "0.999999999999999999", "86400000.000000001", "10.000000000000000001e-1",
      "1e-1000", "1e10000000000000000000000", "0", "-0.0", "86400001", "1.1", "1e-1",
    ] {
    assert_true(
      (try? mermaid_raw_import(mermaid_raw_binding(number))) is Err(_),
      msg=number,
    )
  }
}

///|
test "Mermaid raw JSON retains mathematically integral decimal exponent timeouts" {
  for
    (spelling, expected) in [
      ("1", 1),
      ("1.0", 1),
      ("1.000000000000000000000", 1),
      ("1e0", 1),
      ("1000e-3", 1),
      ("0.1e1", 1),
      ("1.2e1", 12),
      ("12.50e2", 1250),
      ("120000e-2", 1200),
      ("8.64E+7", 86400000),
      ("86400000.000000000000000", 86400000),
      ("8640000000000000000000000000000000000000000000000000000e-47", 86400000),
    ] {
    let imported = mermaid_raw_import(mermaid_raw_binding(spelling))
    assert_eq(imported.draft.edits[0].timeout_ms, expected, msg=spelling)
  }
}

///|
test "Mermaid raw JSON rejects repeated decoded keys at every binding level" {
  let original = mermaid_raw_binding("1")
  for
    text in [
      original.replace(
        old="\"template_work_item_id\":\"root\"",
        new="\"template_work_item_id\":\"missing-operation\",\"template_work_item_id\":\"root\"",
      ),
      original.replace(
        old="\"template_work_item_id\":\"root\"",
        new="\"template_work_item_id\":\"missing-operation\",\"template_work_item_\\u0069d\":\"root\"",
      ),
      original.replace(
        old="\"timeout_ms\":1",
        new="\"timeout_ms\":1.1,\"timeout_ms\":1",
      ),
      original.replace(old="\"nodes\":", new="\"nodes\":{},\"nodes\":"),
      original.replace(old="\"one\":", new="\"one\":{},\"\\u006fne\":"),
      original.replace(
        old="\"input_artifacts\":[\"requests/root.json\"]",
        new="\"input_artifacts\":[],\"input_artifacts\":[\"requests/root.json\"]",
      ),
    ] {
    try mermaid_raw_import(text) catch {
      error =>
        assert_true(error.to_string().contains("duplicate decoded object key"))
    } noraise {
      _ => fail("duplicate bindings accepted")
    }
  }
}

///|
test "Mermaid raw source JSON receives the same duplicate and exact timeout validation" {
  let original = plan_diamond_graph().stringify()
  for
    source in [
      original.replace(
        old="\"timeout_ms\":60000",
        new="\"timeout_ms\":60000.000000000001",
      ),
      original.replace(
        old="\"timeout_ms\":60000",
        new="\"timeout_ms\":1,\"timeout_ms\":60000",
      ),
      original.replace(
        old="\"graph_id\":",
        new="\"graph_id\":\"unselected\",\"graph_id\":",
      ),
    ] {
    assert_true(source != original)
    assert_true(
      (try? mermaid_raw_import(mermaid_raw_binding("1"), source~)) is Err(_),
    )
  }
  let good = original.replace(
    old="\"timeout_ms\":60000",
    new="\"timeout_ms\":6.0000e4",
  )
  assert_eq(
    mermaid_raw_import(mermaid_raw_binding("1"), source=good).draft.edits[0].timeout_ms,
    1,
  )
}

///|
test "Mermaid exact reader preserves escaped text and rejects malformed raw input" {
  let text = mermaid_raw_binding("1").replace(
    old="\"requests/root.json\"",
    new="\"requests/a\\\"b,{c}.json\"",
  )
  assert_eq(mermaid_raw_import(text).draft.edits[0].input_artifacts, [
    "requests/a\"b,{c}.json",
  ])
  for
    bad in [
      "",
      "{",
      "null",
      "[]",
      "{\"x\":\"\\",
      "{\"x\":01}",
      mermaid_raw_binding("1") + " false",
      "[".repeat(65) + "0" + "]".repeat(65),
    ] {
    assert_true((try? mermaid_raw_import(bad)) is Err(_))
  }
  assert_true((try? mermaid_raw_import(" ".repeat(2097153))) is Err(_))
}
