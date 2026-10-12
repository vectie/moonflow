///|
/// The editable generic portion of a declared work item. Operation, schemas,
/// owner, authority and claim remain owned by the selected source graph.
pub(all) struct PlanItemEditV1 {
  work_item_id : String
  input_artifacts : Array[String]
  depends_on : Array[String]
  acceptance_criteria : Array[String]
  timeout_ms : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A portable draft. The source is retained as serialized bytes so updates do
/// not share mutable JSON objects with the selected graph or an older draft.
pub struct DeclaredPlanDraftV1 {
  contract_id : String
  draft_id : String
  source_kind : String
  source_graph_json : String
  source_graph_digest : String
  recorded_at : String
  edits : Array[PlanItemEditV1]
  added_templates : Map[String, String]?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreparedDeclaredPlanV1 {
  contract_id : String
  preparation_id : String
  draft_id : String
  source_graph_id : String
  source_graph_digest : String
  graph : Json
  proposal : Json
  capability_report : GraphCapabilityReportV1
} derive(Debug, Eq, ToJson)

///|
fn plan_canonical_json(value : Json) -> String {
  match value {
    Object(fields) => {
      let keys = fields.keys().to_array()
      keys.sort()
      "{" +
      keys
      .map(key => {
        key.to_json().stringify() + ":" + plan_canonical_json(fields[key])
      })
      .join(",") +
      "}"
    }
    Array(values) => "[" + values.map(plan_canonical_json).join(",") + "]"
    _ => value.stringify()
  }
}

///|
fn plan_digest(value : Json) -> String {
  "sha256:" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(plan_canonical_json(value))),
  )
}

///|
fn plan_unique_strings(
  values : Array[String],
  label : String,
  nonempty~ : Bool,
) -> Unit raise {
  guard !nonempty || !values.is_empty() else {
    fail("\{label} must not be empty")
  }
  let seen : Array[String] = []
  for value in values {
    guard !value.trim().is_empty() && !seen.contains(value) else {
      fail("\{label} contains a blank or duplicate value: \{value}")
    }
    seen.push(value)
  }
}

///|
fn plan_item_edit(event : RuntimeEvent) -> PlanItemEditV1 {
  {
    work_item_id: event.work_item_id,
    input_artifacts: event.input_artifacts.copy(),
    depends_on: event.depends_on.copy(),
    acceptance_criteria: event.acceptance_criteria.copy(),
    timeout_ms: event.timeout_ms,
  }
}

///|
fn plan_edits_from_graph(graph : Json) -> Array[PlanItemEditV1] raise {
  for item in catalog_json_values(wire_object(graph, "source graph"), "items") {
    plan_require_integer_timeout(item)
  }
  events_from_work_graph(graph)
  .filter(event => event.kind == ItemRegistered)
  .map(plan_item_edit)
}

///|
fn plan_require_integer_timeout(value : Json) -> Unit raise {
  let fields = wire_object(value, "plan item")
  guard fields.get("timeout_ms") is Some(Number(number, ..)) &&
    number >= 1.0 &&
    number <= 86400000.0 &&
    number.to_int().to_double() == number else {
    fail("timeout_ms must be a whole number in 1..86400000")
  }
}

///|
pub fn decode_plan_item_edit_v1(value : Json) -> PlanItemEditV1 raise {
  plan_require_integer_timeout(value)
  @json.from_json(value)
}

///|
fn plan_edited_graph(draft : DeclaredPlanDraftV1) -> Json raise {
  let graph = @json.parse(draft.source_graph_json)
  let fields = wire_object(graph, "selected graph")
  let items = catalog_json_values(fields, "items")
  let expanded = draft.contract_id == "moonflow.declared-plan-draft.v2"
  let templates = draft.added_templates.unwrap_or(Map([]))
  guard expanded || draft.edits.length() == items.length() else {
    fail("draft must retain every declared source item exactly once")
  }
  guard !draft.edits.is_empty() && (!expanded || draft.edits.length() <= 256) else {
    fail("draft must contain 1..256 work items")
  }
  let source_ids = items.map(item => {
    wire_string(wire_object(item, "work item"), "work_item_id")
  })
  for id, template in templates {
    guard expanded &&
      !source_ids.contains(id) &&
      source_ids.contains(template) &&
      draft.edits.any(edit => edit.work_item_id == id) else {
      fail(
        "added template must bind a new edited ID to an original source item: \{id}",
      )
    }
  }
  let seen : Array[String] = []
  let next_items : Array[Json] = []
  for edit in draft.edits {
    guard !templates.contains(edit.work_item_id) ||
      (
        catalog_safe_identifier(edit.work_item_id) &&
        edit.work_item_id != "." &&
        !edit.work_item_id.contains("..")
      ) else {
      fail("work_item_id must be a safe identifier: \{edit.work_item_id}")
    }
    guard !seen.contains(edit.work_item_id) else {
      fail("duplicate edited work item: \{edit.work_item_id}")
    }
    seen.push(edit.work_item_id)
    let mut selected : Json? = None
    let template_id = templates
      .get(edit.work_item_id)
      .unwrap_or(edit.work_item_id)
    for item in items {
      if wire_string(wire_object(item, "work item"), "work_item_id") ==
        template_id {
        selected = Some(@json.parse(item.stringify()))
      }
    }
    guard selected is Some(item) else {
      fail("unknown edited work item: \{edit.work_item_id}")
    }
    plan_unique_strings(
      edit.input_artifacts,
      "input_artifacts for \{edit.work_item_id}",
      nonempty=true,
    )
    for artifact in edit.input_artifacts {
      guard artifact_ref_is_workspace_relative(artifact) else {
        fail("input artifact must be workspace-relative: \{artifact}")
      }
    }
    plan_unique_strings(
      edit.depends_on,
      "depends_on for \{edit.work_item_id}",
      nonempty=false,
    )
    plan_unique_strings(
      edit.acceptance_criteria,
      "acceptance_criteria for \{edit.work_item_id}",
      nonempty=true,
    )
    guard edit.timeout_ms > 0 && edit.timeout_ms <= 86400000 else {
      fail("timeout_ms for \{edit.work_item_id} must be 1..86400000")
    }
    let item_fields = wire_object(item, "work item")
    if templates.contains(edit.work_item_id) {
      // Checkpoint migration matches declaration identity, not item ID.
      // A duplicate therefore gets a fresh lineage even for identical inputs.
      let declaration_id = "added-" +
        plan_digest({
          "source_graph_digest": draft.source_graph_digest,
          "work_item_id": edit.work_item_id,
          "template_item_id": template_id,
        }).substring(start=7)
      guard !items.any(original => {
        wire_string(wire_object(original, "work item"), "declaration_id") ==
        declaration_id
      }) else {
        fail("new declaration identity conflicts with source history")
      }
      item_fields["work_item_id"] = edit.work_item_id.to_json()
      item_fields["declaration_id"] = declaration_id.to_json()
    }
    item_fields["input_artifacts"] = edit.input_artifacts.to_json()
    item_fields["depends_on"] = edit.depends_on.to_json()
    item_fields["acceptance_criteria"] = edit.acceptance_criteria.to_json()
    item_fields["timeout_ms"] = edit.timeout_ms.to_json()
    next_items.push(item)
  }
  fields["items"] = (if expanded {
    next_items
  } else {
    source_ids.map(id => {
      next_items
      .filter(item => {
        wire_string(wire_object(item, "work item"), "work_item_id") == id
      })
      .get(0)
      .unwrap()
    })
  }).to_json()
  ignore(events_from_work_graph(graph))
  graph
}

///|
fn plan_validate_draft(draft : DeclaredPlanDraftV1) -> Unit raise {
  guard draft.contract_id == "moonflow.declared-plan-draft.v1" ||
    draft.contract_id == "moonflow.declared-plan-draft.v2" else {
    fail("unsupported declared plan draft contract")
  }
  guard draft.contract_id != "moonflow.declared-plan-draft.v1" ||
    draft.added_templates is None else {
    fail("v1 draft cannot add source templates")
  }
  guard draft.contract_id != "moonflow.declared-plan-draft.v2" ||
    draft.added_templates is Some(_) else {
    fail("v2 draft requires explicit added_templates")
  }
  guard catalog_safe_identifier(draft.draft_id) else {
    fail("draft_id must be a safe identifier")
  }
  guard draft.source_kind == "existing-graph" ||
    draft.source_kind == "product-preset" else {
    fail("source_kind must be existing-graph or product-preset")
  }
  guard catalog_timestamp_is_canonical(draft.recorded_at) else {
    fail("draft recorded_at must be canonical UTC")
  }
  let source = @json.parse(draft.source_graph_json)
  guard plan_digest(source) == draft.source_graph_digest else {
    fail("draft source graph digest mismatch")
  }
  ignore(plan_edits_from_graph(source))
  ignore(plan_edited_graph(draft))
}

///|
/// Start from an existing graph or an owning product's exact graph preset.
/// This function does not create a run, approve work, or invoke an adapter.
pub fn start_declared_plan_v1(
  source_graph : Json,
  draft_id : String,
  source_kind : String,
  recorded_at : String,
) -> DeclaredPlanDraftV1 raise {
  let draft = DeclaredPlanDraftV1::{
    contract_id: "moonflow.declared-plan-draft.v1",
    draft_id,
    source_kind,
    source_graph_json: plan_canonical_json(source_graph),
    source_graph_digest: plan_digest(source_graph),
    recorded_at,
    edits: plan_edits_from_graph(source_graph),
    added_templates: None,
  }
  plan_validate_draft(draft)
  draft
}

///|
pub fn decode_declared_plan_draft_v1(value : Json) -> DeclaredPlanDraftV1 raise {
  for edit in catalog_json_values(wire_object(value, "plan draft"), "edits") {
    plan_require_integer_timeout(edit)
  }
  let draft : DeclaredPlanDraftV1 = @json.from_json(value)
  plan_validate_draft(draft)
  draft
}

///|
/// Apply one form edit without changing the retained source or the old draft.
pub fn edit_declared_plan_item_v1(
  draft : DeclaredPlanDraftV1,
  edit : PlanItemEditV1,
) -> DeclaredPlanDraftV1 raise {
  plan_validate_draft(draft)
  guard draft.edits.any(existing => existing.work_item_id == edit.work_item_id) else {
    fail("unknown edited work item: \{edit.work_item_id}")
  }
  // Encode/decode detaches all caller-owned arrays, including the replacement.
  let edits = draft.edits.map(existing => {
    if existing.work_item_id == edit.work_item_id {
      edit
    } else {
      existing
    }
  })
  let next = { ..draft, edits, }
  decode_declared_plan_draft_v1(next.to_json())
}

///|
/// Consume the portable form exported by a host. Incomplete text drafts belong
/// to the host; this typed boundary validates the whole edit set in one pass.
pub fn declared_plan_from_form_v1(
  value : Json,
  draft_id : String,
  recorded_at : String,
) -> DeclaredPlanDraftV1 raise {
  let fields = wire_object(value, "declared plan form input")
  let contract = wire_string(fields, "contract_id")
  guard contract == "moonflow.declared-plan-form-input.v1" ||
    contract == "moonflow.declared-plan-form-input.v2" else {
    fail("unsupported declared plan form input contract")
  }
  guard fields.get("source_graph") is Some(source) else {
    fail("plan form requires source_graph")
  }
  let original = start_declared_plan_v1(
    source,
    draft_id,
    wire_string(fields, "source_kind"),
    recorded_at,
  )
  let edits = catalog_json_values(fields, "edits").map(decode_plan_item_edit_v1)
  let templates : Map[String, String]? = if contract ==
    "moonflow.declared-plan-form-input.v2" {
    guard fields.get("added_templates") is Some(value) else {
      fail("v2 form requires added_templates")
    }
    Some(@json.from_json(value))
  } else {
    guard fields.get("added_templates") is None else {
      fail("v1 form cannot add templates")
    }
    None
  }
  let next = {
    ..original,
    edits,
    added_templates: templates,
    contract_id: if templates is Some(_) {
      "moonflow.declared-plan-draft.v2"
    } else {
      original.contract_id
    },
  }
  decode_declared_plan_draft_v1(next.to_json())
}

///|
/// A read-only form model. Frozen product semantics are supplied alongside the
/// editable generic fields, and each call returns detached JSON.
pub fn declared_plan_form_v1(draft : DeclaredPlanDraftV1) -> Json raise {
  plan_validate_draft(draft)
  let graph = plan_edited_graph(draft)
  let source = wire_object(@json.parse(draft.source_graph_json), "source graph")
  {
    "contract_id": if draft.added_templates is Some(_) {
      "moonflow.declared-plan-form.v2"
    } else {
      "moonflow.declared-plan-form.v1"
    },
    "draft_id": draft.draft_id,
    "source_kind": draft.source_kind,
    "source_graph_id": wire_string(source, "graph_id"),
    "source_graph_digest": draft.source_graph_digest,
    "source_revision": wire_string(source, "declaration_revision"),
    "items": catalog_json_values(wire_object(graph, "draft graph"), "items"),
    "preparation_dispatches": false,
  }
}

///|
/// Prepare a content-addressed child graph for the existing conformant import
/// or revise-run path. A fresh capability/health check is required on every
/// call, even when the declaration bytes were previously prepared.
pub fn prepare_declared_plan_v1(
  draft : DeclaredPlanDraftV1,
  catalog : CapabilityCatalogV1,
  evaluated_at : String,
  input_capture_digest? : String,
) -> PreparedDeclaredPlanV1 raise {
  plan_validate_draft(draft)
  let graph = plan_edited_graph(draft)
  let fields = wire_object(graph, "draft graph")
  let source_graph_id = wire_string(fields, "graph_id")
  let source_revision = wire_string(fields, "declaration_revision")
  let identity_fields : Map[String, Json] = {
    "contract_id": "moonflow.declared-plan-identity.v1",
    "draft_id": draft.draft_id,
    "source_kind": draft.source_kind,
    "source_graph_digest": draft.source_graph_digest,
    "items": catalog_json_values(fields, "items"),
  }
  if input_capture_digest is Some(capture) {
    guard capture.has_prefix("sha256:") && capture.length() == 71 else {
      fail("input capture identity must be a SHA-256 digest")
    }
    identity_fields["input_capture_digest"] = capture.to_json()
    fields["input_capture_digest"] = capture.to_json()
  }
  let digest = plan_digest(Json::object(identity_fields))
  let identity = "plan-" + digest.substring(start=7)
  fields["graph_id"] = identity.to_json()
  fields["declaration_revision"] = identity.to_json()
  fields["source_digest"] = digest.to_json()
  fields["recorded_at"] = draft.recorded_at.to_json()
  let checked_catalog = decode_capability_catalog_v1(catalog.to_json())
  let report = compile_work_graph_capabilities_at_v1(
    graph, checked_catalog, evaluated_at,
  )
  guard report.accepted else {
    fail(
      "plan cannot be prepared: " +
      report.issues
      .map(issue => "\{issue.subject}: \{issue.code}: \{issue.detail}")
      .join("; "),
    )
  }
  {
    contract_id: "moonflow.prepared-declared-plan.v1",
    preparation_id: identity,
    draft_id: draft.draft_id,
    source_graph_id,
    source_graph_digest: draft.source_graph_digest,
    graph,
    proposal: {
      "contract_id": "moonflow.declared-plan-proposal.v1",
      "draft_id": draft.draft_id,
      "source_kind": draft.source_kind,
      "parent_graph_id": source_graph_id,
      "parent_revision": source_revision,
      "parent_graph_digest": draft.source_graph_digest,
      "child_graph_id": identity,
      "child_revision": identity,
      "child_source_digest": digest,
      "edited_items": draft.edits.to_json(),
      "recorded_at": draft.recorded_at,
      "dispatch_requested": false,
    },
    capability_report: report,
  }
}

///|
pub fn preview_declared_plan_revision_v1(
  draft : DeclaredPlanDraftV1,
  prepared : PreparedDeclaredPlanV1,
  parent : RunProjection,
  proposal_ref : String,
  recorded_at : String,
  input_digests? : Map[String, String] = Map([]),
) -> RunRevisionResult raise {
  plan_validate_draft(draft)
  let source = wire_object(@json.parse(draft.source_graph_json), "source graph")
  guard parent.run_id == wire_string(source, "graph_id") &&
    parent.source_digest == wire_string(source, "source_digest") &&
    parent.declaration_revision == wire_string(source, "declaration_revision") &&
    prepared.source_graph_digest == draft.source_graph_digest else {
    fail("revision preview parent must match the exact selected source graph")
  }
  revise_run(
    parent,
    prepared.graph,
    prepared.preparation_id,
    proposal_ref,
    recorded_at,
    input_digests~,
  )
}
