///|
async fn plan_matrix_command(
  workspace : String,
  source_ref : String,
  matrix_ref : String,
  template_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let imported = @moonflow.declared_plan_from_matrix_v1(
    plan_read_json(root, source_ref),
    plan_read_json(root, matrix_ref),
    plan_read_json(root, template_ref),
    draft_id,
    recorded_at,
  )
  plan_materialize_payloads(root, imported.payloads, draft_id, save)
  println(
    (
      {
        "contract_id": "moonflow.matrix-plan-receipt.v1",
        "source_ref": source_ref,
        "matrix_ref": matrix_ref,
        "template_ref": template_ref,
        "matrix_digest": imported.matrix_digest,
        "template_digest": imported.payloads.template_digest,
        "combinations": imported.combinations.to_json(),
        "artifacts": imported.payloads.artifacts.to_json(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(imported.payloads.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-matrix"
        },
      } : Json).stringify(indent=2),
  )
}
