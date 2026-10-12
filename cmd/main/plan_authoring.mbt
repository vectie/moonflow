///|
async fn plan_draft_directory(workspace : String) -> String {
  @fs.realpath(@moonflow.normalize_workspace_path(workspace)) +
  "/.moonsuite/products/moonflow/plan-drafts"
}

///|
async fn plan_load_draft(
  workspace : String,
  draft_id : String,
) -> @moonflow.DeclaredPlanDraftV1 {
  let id = safe_id(draft_id, "draft_id")
  let path = plan_draft_directory(workspace) + "/" + id + ".json"
  validate_artifact_ref(
    workspace,
    ".moonsuite/products/moonflow/plan-drafts/" + id + ".json",
  )
  @moonflow.decode_declared_plan_draft_v1(read_json(path))
}

///|
async fn plan_start_command(
  workspace : String,
  source_ref : String,
  draft_id : String,
  source_kind : String,
  recorded_at : String,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let draft = @moonflow.start_declared_plan_v1(
    read_json(root + "/" + source_ref),
    draft_id,
    source_kind,
    recorded_at,
  )
  let directory = plan_draft_directory(workspace)
  let lock = @flow_host.acquire_named_writer_lock_v1(
    directory,
    safe_id(draft_id, "draft_id"),
  )
  defer @flow_host.release_named_writer_lock_v1(lock)
  let path = directory + "/" + draft_id + ".json"
  if @fs.exists(path) {
    let existing = plan_load_draft(workspace, draft_id)
    guard existing == draft else {
      fail("draft identity already exists; reopen it or choose a new draft_id")
    }
  } else {
    @flow_host.atomic_replace_named_json_v1(
      directory,
      draft_id + ".json",
      draft.to_json().stringify(indent=2),
    )
  }
  println(@moonflow.declared_plan_form_v1(draft).stringify(indent=2))
}

///|
async fn plan_inspect_command(workspace : String, draft_id : String) -> Unit {
  println(
    @moonflow.declared_plan_form_v1(plan_load_draft(workspace, draft_id)).stringify(
      indent=2,
    ),
  )
}

///|
async fn plan_from_form_command(
  workspace : String,
  form_ref : String,
  draft_id : String,
  recorded_at : String,
) -> Unit {
  validate_artifact_ref(workspace, form_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let draft = @moonflow.declared_plan_from_form_v1(
    read_json(root + "/" + form_ref),
    draft_id,
    recorded_at,
  )
  let directory = plan_draft_directory(workspace)
  let lock = @flow_host.acquire_named_writer_lock_v1(
    directory,
    safe_id(draft_id, "draft_id"),
  )
  defer @flow_host.release_named_writer_lock_v1(lock)
  if @fs.exists(directory + "/" + draft_id + ".json") {
    guard plan_load_draft(workspace, draft_id) == draft else {
      fail("draft identity already exists; choose a new draft_id for this form")
    }
  } else {
    @flow_host.atomic_replace_named_json_v1(
      directory,
      draft_id + ".json",
      draft.to_json().stringify(indent=2),
    )
  }
  println(@moonflow.declared_plan_form_v1(draft).stringify(indent=2))
}

///|
/// The expected saved draft digest is supplied by form clients to prevent a
/// stale editor from overwriting another save. CLI users can obtain it with
/// plan export; the edit document contains the expected_draft plus item_edit.
async fn plan_edit_command(
  workspace : String,
  draft_id : String,
  edit_ref : String,
) -> Unit {
  validate_artifact_ref(workspace, edit_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let payload = read_json(root + "/" + edit_ref)
  guard payload is Object(fields) else { fail("plan edit must be an object") }
  guard fields.get("expected_draft") is Some(expected_value) else {
    fail("plan edit requires expected_draft")
  }
  guard fields.get("item_edit") is Some(edit_value) else {
    fail("plan edit requires item_edit")
  }
  let expected = @moonflow.decode_declared_plan_draft_v1(expected_value)
  let edit = @moonflow.decode_plan_item_edit_v1(edit_value)
  let directory = plan_draft_directory(workspace)
  let lock = @flow_host.acquire_named_writer_lock_v1(
    directory,
    safe_id(draft_id, "draft_id"),
  )
  defer @flow_host.release_named_writer_lock_v1(lock)
  let current = plan_load_draft(workspace, draft_id)
  let next = @moonflow.edit_declared_plan_item_v1(expected, edit)
  // Repeating an identical save is harmless, but a different stale edit fails.
  guard current == expected || current == next else {
    fail("plan draft changed since this form was opened; reopen before saving")
  }
  if current != next {
    @flow_host.atomic_replace_named_json_v1(
      directory,
      draft_id + ".json",
      next.to_json().stringify(indent=2),
    )
  }
  println(@moonflow.declared_plan_form_v1(next).stringify(indent=2))
}

///|
async fn plan_export_command(workspace : String, draft_id : String) -> Unit {
  let draft = plan_load_draft(workspace, draft_id)
  println(draft.to_json().stringify(indent=2))
}

///|
async fn plan_freeze_json(
  directory : String,
  name : String,
  value : Json,
) -> Unit {
  let path = directory + "/" + name
  if @fs.exists(path) {
    guard read_json(path) == value else {
      fail("prepared artifact already exists with different content: \{name}")
    }
  } else {
    @flow_host.atomic_replace_named_json_v1(
      directory,
      name,
      value.stringify(indent=2),
    )
  }
}

///|
async fn plan_prepare_command(
  workspace : String,
  draft_id : String,
  catalog_ref : String,
  evaluated_at : String,
) -> Unit {
  validate_artifact_ref(workspace, catalog_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let draft = plan_load_draft(workspace, draft_id)
  let catalog = @moonflow.decode_capability_catalog_v1(
    read_json(root + "/" + catalog_ref),
  )
  let prepared = @moonflow.prepare_declared_plan_v1(
    draft, catalog, evaluated_at,
  )
  // Verify every edited binding before writing any prepared output. This is a
  // local existence/containment check, never product-payload execution.
  let events = @moonflow.events_from_work_graph(prepared.graph)
  for event in events {
    if event.kind == @moonflow.ItemRegistered {
      for artifact in event.input_artifacts {
        validate_artifact_ref(root, artifact)
      }
    }
  }
  let prepared_ref = ".moonsuite/products/moonflow/prepared-plans/" +
    prepared.preparation_id
  let directory = root + "/" + prepared_ref
  let lock = @flow_host.acquire_named_writer_lock_v1(directory, "prepare")
  defer @flow_host.release_named_writer_lock_v1(lock)
  let graph_ref = prepared_ref + "/graph.json"
  let proposal_ref = prepared_ref + "/proposal.json"
  let parent_events_ref = ".moonsuite/products/moonflow/runs/" +
    safe_id(prepared.source_graph_id, "parent graph_id") +
    "/events.json"
  let migration = if @fs.exists(root + "/" + parent_events_ref) {
    validate_artifact_ref(root, parent_events_ref)
    let parent = @moonflow.replay(
      prepared.source_graph_id,
      @moonflow.decode_event_array(read_json(root + "/" + parent_events_ref)),
    )
    Some(
      @moonflow.preview_declared_plan_revision_v1(
        draft, prepared, parent, proposal_ref, evaluated_at,
      ).receipt,
    )
  } else {
    None
  }
  plan_freeze_json(directory, "graph.json", prepared.graph)
  plan_freeze_json(directory, "proposal.json", prepared.proposal)
  println(
    (
      {
        "contract_id": "moonflow.declared-plan-preparation-receipt.v1",
        "prepared": prepared.to_json(),
        "graph_ref": graph_ref,
        "proposal_ref": proposal_ref,
        "catalog_ref": catalog_ref,
        "evaluated_at": evaluated_at,
        "migration_preview": migration.to_json(),
        "dispatched": false,
        "next_action": if migration is Some(_) {
          "revise-run"
        } else {
          "import-conformant-graph"
        },
      } : Json).stringify(indent=2),
  )
}
