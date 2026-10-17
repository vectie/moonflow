///|
fn mermaid_raw_digest(text : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text)))
}

///|
async fn plan_mermaid_command(
  workspace : String,
  source_ref : String,
  bindings_ref : String,
  diagram_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  validate_artifact_ref(workspace, bindings_ref)
  validate_artifact_ref(workspace, diagram_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let source_data = @fs.read_file(root + "/" + source_ref)
  let bindings_data = @fs.read_file(root + "/" + bindings_ref)
  let diagram_data = @fs.read_file(root + "/" + diagram_ref)
  guard source_data.binary().length() +
    bindings_data.binary().length() +
    diagram_data.binary().length() <=
    2097152 else {
    fail("Mermaid CLI input exceeds 2,097,152 aggregate bytes")
  }
  let source_text = source_data.text()
  let bindings_text = bindings_data.text()
  let diagram_text = diagram_data.text()
  let imported = @moonflow.declared_plan_from_mermaid_text_v1(
    source_text, bindings_text, diagram_text, draft_id, recorded_at,
  )
  for edit in imported.draft.edits {
    for artifact in edit.input_artifacts {
      validate_artifact_ref(root, artifact)
    }
  }
  let provenance : Json = {
    "contract_id": "moonflow.mermaid-plan-source.v1",
    "draft_id": draft_id,
    "recorded_at": recorded_at,
    "source_ref": source_ref,
    "source_text": source_text,
    "source_digest": mermaid_raw_digest(source_text),
    "bindings_ref": bindings_ref,
    "bindings_text": bindings_text,
    "bindings_digest": mermaid_raw_digest(bindings_text),
    "diagram_ref": diagram_ref,
    "diagram_text": diagram_text,
    "diagram_digest": imported.diagram_digest,
  }
  let provenance_ref = ".moonsuite/products/moonflow/plan-drafts/" +
    safe_id(draft_id, "draft_id") +
    ".mermaid-import.json"
  if save {
    let directory = plan_draft_directory(root)
    let lock = @flow_host.acquire_named_writer_lock_v1(directory, draft_id)
    defer @flow_host.release_named_writer_lock_v1(lock)
    let exists = @fs.exists(directory + "/" + draft_id + ".json")
    if exists {
      guard plan_load_draft(root, draft_id) == imported.draft else {
        fail(
          "draft identity already exists; reopen it or choose a new draft_id",
        )
      }
      guard @fs.exists(root + "/" + provenance_ref) else {
        fail(
          "existing draft has no Mermaid source receipt; choose a new draft_id",
        )
      }
    }
    if @fs.exists(root + "/" + provenance_ref) {
      validate_artifact_ref(root, provenance_ref)
      guard read_json(root + "/" + provenance_ref) == provenance else {
        fail(
          "Mermaid import source bytes or references changed; choose a new draft_id",
        )
      }
    } else {
      // Retain source bytes first. An interrupted draft write can be retried
      // against this exact receipt without replacing provenance.
      @flow_host.atomic_replace_named_json_v1(
        directory,
        draft_id + ".mermaid-import.json",
        provenance.stringify(indent=2),
      )
    }
    if !exists {
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
        "contract_id": "moonflow.mermaid-plan-receipt.v1",
        "source_ref": source_ref,
        "bindings_ref": bindings_ref,
        "diagram_ref": diagram_ref,
        "diagram_digest": imported.diagram_digest,
        "bindings_digest": imported.bindings_digest,
        "direction": imported.direction,
        "nodes": imported.nodes.to_json(),
        "edges": imported.edges.to_json(),
        "saved": save,
        "source_receipt_ref": if save {
          provenance_ref.to_json()
        } else {
          Json::null()
        },
        "form": @moonflow.declared_plan_form_v1(imported.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-mermaid"
        },
      } : Json).stringify(indent=2),
  )
}
