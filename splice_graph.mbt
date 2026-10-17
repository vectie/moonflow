///|
/// Replace one declared step with a complete reusable graph. All module roots
/// inherit the removed step's prerequisites; each dependent waits for every
/// module terminal. This only authors declarations, never execution or review.
pub fn splice_declared_graph_v1(request : Json) -> Json raise {
  let fields = wire_object(request, "graph splice")
  guard wire_string(fields, "contract_id") == "moonflow.graph-splice-input.v1" else {
    fail("unsupported graph splice contract")
  }
  let graph_id = wire_string(fields, "graph_id")
  let module_alias = wire_string(fields, "alias")
  let target = wire_string(fields, "replace_item_id")
  let recorded_at = wire_string(fields, "recorded_at")
  guard composition_safe_id(graph_id) && composition_safe_id(module_alias) else {
    fail("splice graph_id and alias must be safe identifiers")
  }
  guard catalog_timestamp_is_canonical(recorded_at) else {
    fail("splice recorded_at must be canonical UTC")
  }
  let source = match fields.get("graph") {
    Some(graph) => @json.parse(graph.stringify())
    None => fail("splice requires graph")
  }
  let module_graph = match fields.get("module") {
    Some(graph) => @json.parse(graph.stringify())
    None => fail("splice requires module")
  }
  let source_fields = wire_object(source, "source graph")
  let module_fields = wire_object(module_graph, "module graph")
  let source_id = wire_string(source_fields, "graph_id")
  let module_id = wire_string(module_fields, "graph_id")
  guard graph_id != source_id && graph_id != module_id else {
    fail("splice graph_id must differ from both source graph IDs")
  }
  let source_items = catalog_json_values(source_fields, "items")
  let module_items = catalog_json_values(module_fields, "items")
  guard source_items.length() <= 256 &&
    module_items.length() <= 256 &&
    source_items.length() + module_items.length() - 1 <= 256 else {
    fail("splice supports at most 256 items per input and result")
  }
  ignore(
    start_declared_plan_v1(
      source, "splice-source", "existing-graph", recorded_at,
    ),
  )
  ignore(
    start_declared_plan_v1(
      module_graph, "splice-module", "existing-graph", recorded_at,
    ),
  )
  let replaced = source_items.filter(value => {
    value is { "work_item_id": String(id), .. } && id == target
  })
  guard replaced.length() == 1 else {
    fail("splice replace_item_id must name one source item")
  }
  let prerequisites = wire_strings(
    wire_object(replaced[0], "replaced item"),
    "depends_on",
    required=false,
  )
  let identity = plan_digest(request)
  let occupied : Array[String] = []
  let declarations : Array[String] = []
  for value in source_items {
    let item = wire_object(value, "source item")
    // Include the removed identity: replacing with an apparently identical ID
    // would hide new work and make downstream references ambiguous.
    occupied.push(wire_string(item, "work_item_id"))
    declarations.push(wire_string(item, "declaration_id"))
  }
  let nonterminals : Array[String] = []
  for value in module_items {
    for
      dependency in wire_strings(
        wire_object(value, "module item"),
        "depends_on",
        required=false,
      ) {
      nonterminals.push(dependency)
    }
  }
  let roots : Array[String] = []
  let terminals : Array[String] = []
  let inserted : Array[Json] = []
  let mappings : Array[Json] = []
  for value in module_items {
    let item = wire_object(value, "module item")
    let old_id = wire_string(item, "work_item_id")
    let new_id = module_alias + "." + old_id
    guard composition_safe_id(new_id) && !occupied.contains(new_id) else {
      fail("spliced work_item_id must be safe and unique: \{new_id}")
    }
    occupied.push(new_id)
    let declaration = "splice:" + identity + ":" + new_id
    guard !declarations.contains(declaration) else {
      fail("spliced declaration_id collides with source")
    }
    declarations.push(declaration)
    let dependencies = wire_strings(item, "depends_on", required=false)
    if dependencies.is_empty() {
      roots.push(new_id)
    }
    if !nonterminals.contains(old_id) {
      terminals.push(new_id)
    }
    mappings.push({
      "source_work_item_id": old_id.to_json(),
      "source_declaration_id": item["declaration_id"],
      "work_item_id": new_id.to_json(),
      "declaration_id": declaration.to_json(),
    })
    item["work_item_id"] = new_id.to_json()
    item["declaration_id"] = declaration.to_json()
    item["depends_on"] = (if dependencies.is_empty() {
      prerequisites.copy()
    } else {
      dependencies.map(id => module_alias + "." + id)
    }).to_json()
    inserted.push(value)
  }
  let items : Array[Json] = []
  let rewired : Array[Json] = []
  for value in source_items {
    let item = wire_object(value, "source item")
    let id = wire_string(item, "work_item_id")
    if id == target {
      for addition in inserted {
        items.push(addition)
      }
    } else {
      let dependencies = wire_strings(item, "depends_on", required=false)
      if dependencies.contains(target) {
        let after : Array[String] = []
        for dependency in dependencies {
          if dependency == target {
            for terminal in terminals {
              after.push(terminal)
            }
          } else {
            after.push(dependency)
          }
        }
        item["depends_on"] = after.to_json()
        rewired.push({
          "work_item_id": id.to_json(),
          "before": dependencies.to_json(),
          "after": after.to_json(),
        })
      }
      items.push(value)
    }
  }
  let graph : Json = {
    "contract_id": protocol_id().to_json(),
    "graph_id": graph_id.to_json(),
    "book_id": source_fields["book_id"],
    "declaration_revision": "splice-v1",
    "source_digest": identity.to_json(),
    "recorded_at": recorded_at.to_json(),
    "items": items.to_json(),
  }
  ignore(start_declared_plan_v1(graph, graph_id, "existing-graph", recorded_at))
  {
    "contract_id": "moonflow.graph-splice-result.v1",
    "splice_digest": identity.to_json(),
    "source_graph_id": source_id.to_json(),
    "source_graph_digest": plan_digest(fields["graph"]).to_json(),
    "module_graph_id": module_id.to_json(),
    "module_graph_digest": plan_digest(fields["module"]).to_json(),
    "replaced_item": replaced[0],
    "inherited_prerequisite_ids": prerequisites.to_json(),
    "inserted_root_ids": roots.to_json(),
    "inserted_terminal_ids": terminals.to_json(),
    "inserted_items": mappings.to_json(),
    "rewired_dependents": rewired.to_json(),
    "graph": graph,
    "dispatched": false,
  }
}
