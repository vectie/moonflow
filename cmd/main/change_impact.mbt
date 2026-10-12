///|
async fn plan_change_impact_command(
  workspace : String,
  source_ref : String,
  changed_ids : Array[String],
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  println(
    @moonflow.declared_change_impact_v1(
      read_json(root + "/" + source_ref),
      changed_ids,
    )
    .to_json()
    .stringify(indent=2),
  )
}
