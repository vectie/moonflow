///|
async fn plan_export_worksheet_command(
  workspace : String,
  source_ref : String,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  // No input files or catalog are required to export declared fields.
  @stdio.stdout.write(
    @moonflow.declared_plan_worksheet_csv_v1(read_json(root + "/" + source_ref)),
  )
}

///|
async fn plan_worksheet_command(
  workspace : String,
  source_ref : String,
  csv_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  validate_artifact_ref(workspace, csv_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let imported = @moonflow.declared_plan_from_worksheet_v1(
    read_json(root + "/" + source_ref),
    @fs.read_file(root + "/" + csv_ref).text(),
    draft_id,
    recorded_at,
  )
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
        "contract_id": "moonflow.plan-worksheet-receipt.v1",
        "source_ref": source_ref,
        "csv_ref": csv_ref,
        "csv_digest": imported.csv_digest,
        "row_count": imported.row_count,
        "changed_item_ids": imported.changed_item_ids,
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(imported.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-worksheet"
        },
      } : Json).stringify(indent=2),
  )
}
