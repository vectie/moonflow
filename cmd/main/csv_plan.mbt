///|
async fn plan_csv_command(
  workspace : String,
  source_ref : String,
  template_id : String,
  csv_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  validate_artifact_ref(workspace, csv_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let imported = @moonflow.declared_plan_from_csv_v1(
    read_json(root + "/" + source_ref),
    template_id,
    @fs.read_file(root + "/" + csv_ref).text(),
    draft_id,
    recorded_at,
  )
  // Validate the complete batch before saving a draft. Preparation continues to
  // recheck current input existence and the exact capability catalog as usual.
  for edit in imported.draft.edits {
    for artifact in edit.input_artifacts {
      validate_artifact_ref(root, artifact)
    }
  }
  if save {
    let directory = plan_draft_directory(root)
    let lock = @flow_host.acquire_named_writer_lock_v1(
      directory,
      safe_id(draft_id, "draft_id"),
    )
    defer @flow_host.release_named_writer_lock_v1(lock)
    let path = directory + "/" + draft_id + ".json"
    if @fs.exists(path) {
      guard plan_load_draft(root, draft_id) == imported.draft else {
        fail(
          "draft identity already exists; reopen it or choose a new draft_id",
        )
      }
    } else {
      @flow_host.atomic_replace_named_json_v1(
        directory,
        draft_id + ".json",
        imported.draft.to_json().stringify(indent=2),
      )
    }
  }
  println(
    (
      {
        "contract_id": "moonflow.csv-plan-receipt.v1",
        "source_ref": source_ref,
        "csv_ref": csv_ref,
        "csv_digest": imported.csv_digest,
        "template_work_item_id": imported.template_work_item_id,
        "row_count": imported.row_count,
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(imported.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-csv"
        },
      } : Json).stringify(indent=2),
  )
}
