///|
async fn show_graph_capacity(
  workspace : String,
  source_ref : String,
  scenario_ref : String,
  format : String,
) -> Unit {
  guard format == "--json" || format == "--csv" else {
    fail("Use --json or --csv")
  }
  validate_artifact_ref(workspace, source_ref)
  validate_artifact_ref(workspace, scenario_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let report = @moonflow.declared_graph_capacity_v1(
    read_json(root + "/" + source_ref),
    read_json(root + "/" + scenario_ref),
  )
  println(
    if format == "--csv" {
      @moonflow.graph_capacity_csv_v1(report)
    } else {
      report.to_json().stringify(indent=2)
    },
  )
}
