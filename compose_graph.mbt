///|
fn composition_safe_id(value : String) -> Bool {
  catalog_safe_identifier(value) && value != "." && !value.contains("..")
}

///|
/// Compose complete declared graphs into new work. No source state or acceptance
/// is carried forward. Inputs remain relative to one shared workspace.
pub fn compose_declared_graph_v1(request : Json) -> Json raise {
  let fields = wire_object(request, "graph composition")
  guard wire_string(fields, "contract_id") ==
    "moonflow.graph-composition-input.v1" else {
    fail("unsupported graph composition contract")
  }
  let graph_id = wire_string(fields, "graph_id")
  let book_id = wire_string(fields, "book_id")
  let recorded_at = wire_string(fields, "recorded_at")
  guard composition_safe_id(graph_id) && composition_safe_id(book_id) else {
    fail("composition graph_id and book_id must be safe identifiers")
  }
  guard catalog_timestamp_is_canonical(recorded_at) else {
    fail("composition recorded_at must be canonical UTC")
  }
  let sources = catalog_json_values(fields, "sources")
  guard sources.length() >= 2 && sources.length() <= 16 else {
    fail("composition requires 2..16 sources")
  }
  let links = catalog_json_values(fields, "links")
  guard links.length() <= 256 else {
    fail("composition supports at most 256 links")
  }
  let identity = plan_digest(request)
  let aliases : Array[String] = []
  let items : Array[Json] = []
  let by_id : Map[String, Json] = {}
  let owners : Map[String, String] = {}
  let provenance : Array[Json] = []
  for source_value in sources {
    let source = wire_object(source_value, "composition source")
    let alias = wire_string(source, "alias")
    guard composition_safe_id(alias) && !aliases.contains(alias) else {
      fail("composition source alias must be safe and unique: \{alias}")
    }
    aliases.push(alias)
    let graph = match source.get("graph") {
      Some(value) => @json.parse(value.stringify())
      None => fail("composition source requires graph")
    }
    let original = wire_object(graph, "source graph")
    let source_id = wire_string(original, "graph_id")
    guard source_id != graph_id else {
      fail("composition graph_id must differ from every source graph_id")
    }
    let source_items = catalog_json_values(original, "items")
    guard items.length() + source_items.length() <= 256 else {
      fail("composition supports at most 256 total work items")
    }
    // Reuse the complete existing plan validation, including artifact references,
    // integer timeouts, required editable fields and dependency cycles.
    ignore(start_declared_plan_v1(graph, alias, "existing-graph", recorded_at))
    let mappings : Array[Json] = []
    for value in source_items {
      let item = wire_object(value, "composition item")
      let old_id = wire_string(item, "work_item_id")
      let new_id = alias + "." + old_id
      guard composition_safe_id(new_id) && !by_id.contains(new_id) else {
        fail("composed work_item_id must be safe and unique: \{new_id}")
      }
      mappings.push({
        "source_work_item_id": old_id.to_json(),
        "source_declaration_id": item["declaration_id"],
        "work_item_id": new_id.to_json(),
      })
      item["work_item_id"] = new_id.to_json()
      item["declaration_id"] = ("composition:" + identity + ":" + new_id).to_json()
      item["depends_on"] = wire_strings(item, "depends_on", required=false)
        .map(id => alias + "." + id)
        .to_json()
      items.push(value)
      by_id[new_id] = value
      owners[new_id] = alias
    }
    provenance.push({
      "alias": alias.to_json(),
      "source_graph_id": source_id.to_json(),
      "source_book_id": original["book_id"],
      "source_declaration_revision": original["declaration_revision"],
      "source_graph_digest": plan_digest(source["graph"]).to_json(),
      "items": mappings.to_json(),
    })
  }
  let added_links : Array[Json] = []
  let seen_links : Array[String] = []
  for link_value in links {
    let link = wire_object(link_value, "composition link")
    let prerequisite = wire_string(link, "prerequisite")
    let dependent = wire_string(link, "dependent")
    guard by_id.contains(prerequisite) && by_id.contains(dependent) else {
      fail("composition link endpoints must name composed work items")
    }
    guard owners[prerequisite] != owners[dependent] else {
      fail("composition links must connect different sources")
    }
    let key = prerequisite + ">" + dependent
    guard !seen_links.contains(key) else { fail("duplicate composition link") }
    seen_links.push(key)
    let item = wire_object(by_id[dependent], "dependent item")
    let dependencies = wire_strings(item, "depends_on", required=false)
    dependencies.push(prerequisite)
    item["depends_on"] = dependencies.to_json()
    added_links.push({
      "prerequisite": prerequisite.to_json(),
      "dependent": dependent.to_json(),
    })
  }
  let graph : Json = {
    "contract_id": protocol_id().to_json(),
    "graph_id": graph_id.to_json(),
    "book_id": book_id.to_json(),
    "declaration_revision": "composition-v1",
    "source_digest": identity.to_json(),
    "recorded_at": recorded_at.to_json(),
    "items": items.to_json(),
  }
  ignore(start_declared_plan_v1(graph, graph_id, "existing-graph", recorded_at))
  {
    "contract_id": "moonflow.graph-composition-result.v1",
    "composition_digest": identity.to_json(),
    "sources": provenance.to_json(),
    "links": added_links.to_json(),
    "graph": graph,
    "dispatched": false,
  }
}
