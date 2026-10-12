///|
pub(all) struct GraphFieldChangeV1 {
  field : String
  before_present : Bool
  before : Json
  after_present : Bool
  after : Json
} derive(Debug, Eq, ToJson)

///|
pub(all) struct GraphItemChangeV1 {
  declaration_id : String
  change : String
  before : Json
  after : Json
  fields : Array[GraphFieldChangeV1]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct DeclaredGraphComparisonV1 {
  contract_id : String
  book_id : String
  before_graph_digest : String
  after_graph_digest : String
  graph_fields : Array[GraphFieldChangeV1]
  declaration_order_changed : Bool
  items : Array[GraphItemChangeV1]
  before_impact : ChangeImpactV1
  after_impact : ChangeImpactV1
} derive(Debug, Eq, ToJson)

///|
fn graph_comparison_fields(
  before : Map[String, Json],
  after : Map[String, Json],
  skip_items~ : Bool,
) -> Array[GraphFieldChangeV1] {
  let keys = before.keys().to_array()
  for key in after.keys() {
    if !before.contains(key) {
      keys.push(key)
    }
  }
  keys.sort_by((a, b) => a.lexical_compare(b))
  keys.filter_map(key => {
    if skip_items && key == "items" {
      return None
    }
    let old = before.get(key)
    let next = after.get(key)
    let equal = match (old, next) {
      (Some(a), Some(b)) => plan_canonical_json(a) == plan_canonical_json(b)
      (None, None) => true
      _ => false
    }
    if equal {
      None
    } else {
      Some({
        field: key,
        before_present: before.contains(key),
        before: old.unwrap_or(Json::null()),
        after_present: after.contains(key),
        after: next.unwrap_or(Json::null()),
      })
    }
  })
}

///|
fn graph_comparison_source(graph : Json) -> Json raise {
  let encoded = graph.stringify()
  guard encoded.length() <= 1048576 else {
    fail("Graph comparison source exceeds 1,048,576 UTF-16 code units")
  }
  let copy = @json.parse(encoded, max_nesting_depth=64)
  let items = catalog_json_values(wire_object(copy, "graph"), "items")
  guard items.length() <= 256 else {
    fail("Graph comparison source must contain at most 256 work items")
  }
  // Validate both complete graphs, even when their declarations are equal.
  ignore(plan_edits_from_graph(copy))
  let seen : Array[String] = []
  for item in items {
    let id = wire_string(wire_object(item, "item"), "declaration_id")
    guard !seen.contains(id) else {
      fail("Graph comparison requires unique declaration_id: \{id}")
    }
    seen.push(id)
  }
  copy
}

///|
fn graph_comparison_impact(
  graph : Json,
  seeds : Array[String],
) -> ChangeImpactV1 raise {
  if seeds.is_empty() {
    {
      contract_id: "moonflow.change-impact.v1",
      source_graph_digest: plan_digest(graph),
      changed_item_ids: [],
      affected_items: [],
      unaffected_item_ids: plan_edits_from_graph(graph).map(edit => {
        edit.work_item_id
      }),
    }
  } else {
    declared_change_impact_v1(graph, seeds)
  }
}

///|
/// Compare unimported declared graphs by stable declaration identity. Every
/// top-level item field is compared, including unknown metadata; object key
/// order is ignored, arrays are ordered. Impacts describe potential downstream
/// effects on each graph, never execution or checkpoint eligibility.
pub fn compare_declared_graphs_v1(
  before_graph : Json,
  after_graph : Json,
) -> DeclaredGraphComparisonV1 raise {
  let before = graph_comparison_source(before_graph)
  let after = graph_comparison_source(after_graph)
  let before_fields = wire_object(before, "before graph")
  let after_fields = wire_object(after, "after graph")
  let book_id = wire_string(before_fields, "book_id")
  guard book_id == wire_string(after_fields, "book_id") else {
    fail("Graph comparison requires the same book_id")
  }
  let before_items = catalog_json_values(before_fields, "items")
  let after_items = catalog_json_values(after_fields, "items")
  let before_by_id : Map[String, Json] = {}
  let after_by_id : Map[String, Json] = {}
  for item in before_items {
    before_by_id[wire_string(wire_object(item, "item"), "declaration_id")] = item
  }
  for item in after_items {
    after_by_id[wire_string(wire_object(item, "item"), "declaration_id")] = item
  }
  let ids = before_by_id.keys().to_array()
  for id in after_by_id.keys() {
    if !before_by_id.contains(id) {
      ids.push(id)
    }
  }
  let before_seeds : Array[String] = []
  let after_seeds : Array[String] = []
  let items = ids.map(id => {
    let old = before_by_id.get(id).unwrap_or(Json::null())
    let next = after_by_id.get(id).unwrap_or(Json::null())
    let fields = match (old, next) {
      (Object(a), Object(b)) => graph_comparison_fields(a, b, skip_items=false)
      _ => []
    }
    let change = if !before_by_id.contains(id) {
      "added"
    } else if !after_by_id.contains(id) {
      "removed"
    } else if fields.is_empty() {
      "unchanged"
    } else {
      "changed"
    }
    if change != "unchanged" {
      if old is Object(value) {
        before_seeds.push(wire_string(value, "work_item_id"))
      }
      if next is Object(value) {
        after_seeds.push(wire_string(value, "work_item_id"))
      }
    }
    GraphItemChangeV1::{
      declaration_id: id,
      change,
      before: old,
      after: next,
      fields,
    }
  })
  {
    contract_id: "moonflow.declared-graph-comparison.v1",
    book_id,
    before_graph_digest: plan_digest(before),
    after_graph_digest: plan_digest(after),
    graph_fields: graph_comparison_fields(
      before_fields,
      after_fields,
      skip_items=true,
    ),
    declaration_order_changed: before_by_id.keys().to_array() !=
    after_by_id.keys().to_array(),
    items,
    before_impact: graph_comparison_impact(before, before_seeds),
    after_impact: graph_comparison_impact(after, after_seeds),
  }
}

///|
fn graph_comparison_field_text(field : GraphFieldChangeV1) -> String {
  let before = if field.before_present {
    field.before.stringify()
  } else {
    "<absent>"
  }
  let after = if field.after_present {
    field.after.stringify()
  } else {
    "<absent>"
  }
  "  " + field.field.to_json().stringify() + ": " + before + " -> " + after
}

///|
pub fn declared_graph_comparison_text_v1(
  report : DeclaredGraphComparisonV1,
) -> String {
  let lines = [
    "Declared graph comparison for " + report.book_id.to_json().stringify(),
    "Before: " + report.before_graph_digest,
    "After: " + report.after_graph_digest,
    "Potential dependency effects only; no execution, acceptance or checkpoint decision.",
    "Declaration order changed: " + report.declaration_order_changed.to_string(),
    "Graph fields:",
  ]
  for field in report.graph_fields {
    lines.push(graph_comparison_field_text(field))
  }
  for item in report.items {
    lines.push(
      item.change + " declaration " + item.declaration_id.to_json().stringify(),
    )
    if item.change == "added" {
      lines.push("  after: " + item.after.stringify())
    }
    if item.change == "removed" {
      lines.push("  before: " + item.before.stringify())
    }
    for field in item.fields {
      lines.push(graph_comparison_field_text(field))
    }
  }
  for
    (label, impact) in [
      ("Before", report.before_impact),
      ("After", report.after_impact),
    ] {
    lines.push(
      label + " changed items: " + impact.changed_item_ids.to_json().stringify(),
    )
    lines.push(
      label +
      " downstream items: " +
      impact.affected_items.to_json().stringify(),
    )
    lines.push(
      label +
      " unaffected items: " +
      impact.unaffected_item_ids.to_json().stringify(),
    )
  }
  lines.join("\n")
}
