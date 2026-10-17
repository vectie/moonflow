///|
/// One diagram node bound explicitly to an original source operation.
pub(all) struct MermaidPlanNodeV1 {
  node_id : String
  label : String
  line_number : Int
  template_work_item_id : String
} derive(Debug, Eq, ToJson)

///|
/// Imported arrows point from prerequisite to dependent work.
pub(all) struct MermaidPlanEdgeV1 {
  prerequisite : String
  dependent : String
  line_number : Int
} derive(Debug, Eq, ToJson)

///|
/// The original diagram is retained verbatim. Labels are presentation only;
/// every operation contract comes from an explicitly named source template.
pub(all) struct MermaidPlanImportV1 {
  contract_id : String
  diagram : String
  diagram_digest : String
  bindings_digest : String
  direction : String
  nodes : Array[MermaidPlanNodeV1]
  edges : Array[MermaidPlanEdgeV1]
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
fn mermaid_node_token(token : String, line : Int) -> (String, String?) raise {
  let token = token.trim().to_owned()
  let (id, label) = match token.find("[") {
    Some(start) => {
      guard token.has_suffix("]") else {
        fail("Mermaid line \{line}: node label requires a closing ]")
      }
      let id = token[:start].trim().to_owned()
      let text = token[start + 1:token.length() - 1].to_owned()
      let label = if text.has_prefix("\"") &&
        text.has_suffix("\"") &&
        text.length() >= 2 {
        text[1:text.length() - 1].to_owned()
      } else {
        text
      }
      guard !label.contains("[") &&
        !label.contains("]") &&
        !label.contains("\"") &&
        !label.contains(";") &&
        !label.contains("<") &&
        !label.contains(">") &&
        !label.contains("`") &&
        !label.contains("\\") &&
        !label.trim().is_empty() else {
        fail("Mermaid line \{line}: unsupported or empty node label")
      }
      (id, Some(label))
    }
    None => (token, None)
  }
  guard !id.is_empty() &&
    id.length() <= 128 &&
    id != "end" &&
    id
    .iter()
    .all(ch => {
      match ch {
        'a'..='z' | 'A'..='Z' | '0'..='9' | '_' | '-' => true
        _ => false
      }
    }) else {
    fail("Mermaid line \{line}: unsupported node or statement: \{token}")
  }
  (id, label)
}

///|
fn mermaid_known_fields(
  value : Json,
  allowed : Array[String],
  label : String,
) -> Map[String, Json] raise {
  let fields = wire_object(value, label)
  for key, _ in fields {
    guard allowed.contains(key) else { fail("\{label}: unknown field \{key}") }
  }
  fields
}

///|
/// Turn a small Mermaid flowchart into a normal editable declared plan.
/// Supports graph/flowchart direction headers, isolated nodes, rectangular
/// labels, --> chains and full-line %% comments. Unsupported statements fail.
/// All diagram nodes require exact bindings; input payloads are never inferred.
pub fn declared_plan_from_mermaid_v1(
  source_graph : Json,
  bindings_value : Json,
  diagram : String,
  draft_id : String,
  recorded_at : String,
) -> MermaidPlanImportV1 raise {
  let raw = @utf8.encode(diagram)
  guard raw.length() <= 1048576 else {
    fail("Mermaid input exceeds 1,048,576 UTF-8 bytes")
  }
  guard !diagram.has_prefix("\u{FEFF}") else {
    fail("Mermaid BOM is unsupported")
  }
  let ids : Array[String] = []
  let labels : Map[String, String] = Map([])
  let first_lines : Map[String, Int] = Map([])
  let edges : Array[MermaidPlanEdgeV1] = []
  let mut direction : String? = None
  for index, line_view in diagram.split("\n").to_array() {
    let line = line_view.trim().to_owned()
    let number = index + 1
    if line.is_empty() || (line.has_prefix("%%") && !line.has_prefix("%%{")) {
      continue
    }
    if direction is None {
      let words = line.split(" ").filter(word => !word.is_empty()).to_array()
      guard words.length() == 2 &&
        ["flowchart", "graph"].contains(words[0].to_owned()) &&
        ["TD", "TB", "BT", "LR", "RL"].contains(words[1].to_owned()) else {
        fail(
          "Mermaid line \{number}: expected graph/flowchart and TD, TB, BT, LR or RL",
        )
      }
      direction = Some(words[1].to_owned())
      continue
    }
    guard !line.contains(";") else {
      fail(
        "Mermaid line \{number}: use one statement per line, without semicolons",
      )
    }
    guard !line.contains("--->") else {
      fail("Mermaid line \{number}: only --> arrows are supported")
    }
    let tokens = line.split("-->").to_array()
    let chain : Array[String] = []
    for token in tokens {
      let (id, label) = mermaid_node_token(token.to_owned(), number)
      if !first_lines.contains(id) {
        guard ids.length() < 256 else {
          fail("Mermaid requires at most 256 nodes")
        }
        ids.push(id)
        first_lines[id] = number
      }
      if label is Some(text) {
        // Mermaid renders the last explicit label; it never supplies work semantics.
        labels[id] = text
      }
      chain.push(id)
    }
    for position in 1..<chain.length() {
      let prerequisite = chain[position - 1]
      let dependent = chain[position]
      guard prerequisite != dependent else {
        fail("Mermaid line \{number}: self dependency")
      }
      guard !edges.any(edge => {
        edge.prerequisite == prerequisite && edge.dependent == dependent
      }) else {
        fail(
          "Mermaid line \{number}: repeated dependency \{prerequisite} --> \{dependent}",
        )
      }
      guard edges.length() < 4096 else {
        fail("Mermaid requires at most 4096 arrows")
      }
      edges.push({ prerequisite, dependent, line_number: number, })
    }
  }
  guard direction is Some(direction) && !ids.is_empty() else {
    fail("Mermaid requires a header and 1..256 nodes")
  }
  let bindings = mermaid_known_fields(
    bindings_value,
    ["contract_id", "nodes"],
    "Mermaid bindings",
  )
  guard bindings.get("contract_id") == Some("moonflow.mermaid-plan-bindings.v1") else {
    fail("unsupported Mermaid binding contract")
  }
  guard bindings.get("nodes") is Some(Object(bound)) else {
    fail("Mermaid bindings.nodes must be an object")
  }
  for id, _ in bound {
    guard ids.contains(id) else {
      fail("Mermaid binding names a node absent from the diagram: \{id}")
    }
  }
  // Validate exact numeric spellings before the shared source-plan decoder
  // converts any inherited timeout to Int.
  for
    item in catalog_json_values(
      wire_object(source_graph, "source graph"),
      "items",
    ) {
    let fields = wire_object(item, "source work item")
    guard fields.get("timeout_ms") is Some(timeout) else {
      fail("source work item timeout_ms required")
    }
    ignore(mermaid_timeout(timeout, "source work item"))
  }
  // The shared draft serializer re-parses numbers when validating its digest.
  // Normalize only after exact timeout validation, so valid decimal/exponent
  // spellings remain usable without changing the retained raw source receipt.
  let source_graph = @json.parse(source_graph.stringify())
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  let templates : Map[String, String] = Map([])
  let edits : Array[PlanItemEditV1] = []
  let nodes : Array[MermaidPlanNodeV1] = []
  for id in ids {
    guard bound.get(id) is Some(binding) else {
      fail("Mermaid node has no explicit binding: \{id}")
    }
    let fields = mermaid_known_fields(
      binding,
      [
        "template_work_item_id", "input_artifacts", "acceptance_criteria", "timeout_ms",
      ],
      "Mermaid node \{id}",
    )
    let template_id = wire_string(fields, "template_work_item_id")
    guard original.edits.filter(edit => edit.work_item_id == template_id).get(0)
      is Some(template) else {
      fail(
        "Mermaid node \{id}: template is not an original source item: \{template_id}",
      )
    }
    guard !original.edits.any(edit => edit.work_item_id == id) else {
      fail("Mermaid node must use a new ID, not a source work item ID: \{id}")
    }
    let inputs = match fields.get("input_artifacts") {
      Some(value) =>
        records_plan_strings(value, "Mermaid node \{id} input_artifacts")
      None => fail("Mermaid node \{id}: input_artifacts required")
    }
    let criteria = match fields.get("acceptance_criteria") {
      Some(value) =>
        records_plan_strings(value, "Mermaid node \{id} acceptance_criteria")
      None => template.acceptance_criteria.copy()
    }
    let timeout_ms = match fields.get("timeout_ms") {
      Some(value) => mermaid_timeout(value, "Mermaid node \{id}")
      None => template.timeout_ms
    }
    edits.push({
      work_item_id: id,
      input_artifacts: inputs,
      depends_on: edges
      .filter(edge => edge.dependent == id)
      .map(edge => edge.prerequisite),
      acceptance_criteria: criteria,
      timeout_ms,
    })
    templates[id] = template_id
    nodes.push({
      node_id: id,
      label: labels.get(id).unwrap_or(id),
      line_number: first_lines[id],
      template_work_item_id: template_id,
    })
  }
  let draft = declared_plan_from_form_v1(
    {
      "contract_id": "moonflow.declared-plan-form-input.v2",
      "source_kind": "existing-graph",
      "source_graph": source_graph,
      "edits": edits.to_json(),
      "added_templates": templates.to_json(),
    },
    draft_id,
    recorded_at,
  )
  {
    contract_id: "moonflow.mermaid-plan-import.v1",
    diagram,
    diagram_digest: "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(raw)),
    bindings_digest: plan_digest(bindings_value),
    direction,
    nodes,
    edges,
    draft,
  }
}
