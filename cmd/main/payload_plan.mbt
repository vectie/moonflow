///|
async fn plan_payloads_command(
  workspace : String,
  source_ref : String,
  mapping_ref : String,
  template_ref : String,
  records_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let imported = @moonflow.declared_plan_from_payloads_v1(
    plan_read_json(root, source_ref),
    plan_read_json(root, mapping_ref),
    plan_read_json(root, template_ref),
    @utf8.decode(plan_read_bytes(root, records_ref)),
    draft_id,
    recorded_at,
  )
  plan_materialize_payloads(root, imported, draft_id, save)
  println(
    (
      {
        "contract_id": "moonflow.payload-plan-receipt.v1",
        "source_ref": source_ref,
        "mapping_ref": mapping_ref,
        "template_ref": template_ref,
        "records_ref": records_ref,
        "mapping_digest": imported.mapping_digest,
        "template_digest": imported.template_digest,
        "records_digest": imported.records_digest,
        "artifacts": imported.artifacts.to_json(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(imported.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-payloads"
        },
      } : Json).stringify(indent=2),
  )
}

///|
async fn plan_materialize_payloads(
  root : String,
  imported : @moonflow.PayloadPlanImportV1,
  draft_id : String,
  save : Bool,
) -> Unit {
  plan_materialize_payload_artifacts(
    root,
    imported.artifacts,
    imported.draft,
    draft_id,
    save,
  )
}

///|
async fn plan_materialize_payload_artifacts(
  root : String,
  artifacts : Array[@moonflow.PayloadPlanArtifactV1],
  draft : @moonflow.DeclaredPlanDraftV1,
  draft_id : String,
  save : Bool,
) -> Unit {
  // Validate all caller-supplied ancillary files before creating any files.
  for edit in draft.edits {
    for index, artifact in edit.input_artifacts {
      if index > 0 {
        ignore(plan_regular_path(root, artifact))
      }
    }
  }
  if save {
    let directory = plan_directory(
      root, ".moonsuite/products/moonflow/plan-drafts",
    )
    let lock = @flow_host.acquire_named_writer_lock_v1(
      directory,
      safe_id(draft_id, "draft_id"),
    )
    defer @flow_host.release_named_writer_lock_v1(lock)
    let exists = @fs.exists(directory + "/" + draft_id + ".json")
    if exists {
      guard plan_load_draft(root, draft_id) == draft else {
        fail(
          "draft identity already exists; reopen it or choose a new draft_id",
        )
      }
    }
    // Preflight all existing addressed objects before writing any new object.
    for artifact in artifacts {
      if @fs.exists(root + "/" + artifact.artifact_ref) {
        guard plan_read_bytes(root, artifact.artifact_ref) ==
          @utf8.encode(artifact.json_text) else {
          fail(
            "generated request object differs from expected bytes: \{artifact.artifact_ref}",
          )
        }
      }
    }
    for artifact in artifacts {
      guard plan_capture_bytes(root, @utf8.encode(artifact.json_text)) ==
        artifact.artifact_ref else {
        fail("generated request path does not match content identity")
      }
    }
    if !exists {
      @flow_host.atomic_replace_named_json_v1(
        directory,
        draft_id + ".json",
        draft.to_json().stringify(indent=2),
      )
    }
  }
}
