///|
async fn show_graph_map(
  workspace : String,
  source_ref : String,
  format : String,
) -> Unit {
  if format != "--json" && format != "--dot" {
    fail("Use --json or --dot")
  }
  validate_artifact_ref(workspace, source_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let graph = read_json(root + "/" + source_ref)
  println(
    if format == "--dot" {
      @moonflow.declared_graph_dot_v1(graph)
    } else {
      @moonflow.declared_graph_map_v1(graph).to_json().stringify(indent=2)
    },
  )
}
