///|
async fn show_graph_timing(
  workspace : String,
  source_ref : String,
  estimates_ref : String,
  format : String,
) -> Unit {
  guard format == "--json" || format == "--csv" else {
    fail("Use --json or --csv")
  }
  validate_artifact_ref(workspace, source_ref)
  validate_artifact_ref(workspace, estimates_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let report = @moonflow.declared_graph_timing_v1(
    read_json(root + "/" + source_ref),
    read_json(root + "/" + estimates_ref),
  )
  println(
    if format == "--csv" {
      @moonflow.graph_timing_csv_v1(report)
    } else {
      report.to_json().stringify(indent=2)
    },
  )
}
