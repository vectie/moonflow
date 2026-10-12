///|
async fn read_comparison_graph(
  workspace : String,
  artifact_ref : String,
) -> (Json, Json) {
  validate_artifact_ref(workspace, artifact_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let data = @fs.read_file(root + "/" + artifact_ref)
  guard data.binary().length() <= 2097152 else {
    fail("Graph comparison file exceeds 2,097,152 bytes")
  }
  let digest = "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(data.binary()))
  (
    @json.parse(data.text(), max_nesting_depth=64),
    {
      "artifact_ref": artifact_ref,
      "sha256": digest,
      "bytes": data.binary().length(),
    },
  )
}

///|
async fn show_graph_comparison(
  workspace : String,
  before_ref : String,
  after_ref : String,
  format : String,
) -> Unit {
  guard format == "--json" || format == "--text" else {
    fail("Use --json or --text")
  }
  let (before, before_file) = read_comparison_graph(workspace, before_ref)
  let (after, after_file) = read_comparison_graph(workspace, after_ref)
  let report = @moonflow.compare_declared_graphs_v1(before, after)
  if format == "--text" {
    println("Before file: " + before_file.stringify())
    println("After file: " + after_file.stringify())
    println(@moonflow.declared_graph_comparison_text_v1(report))
  } else {
    guard report.to_json() is Object(fields) else {
      fail("Invalid comparison report")
    }
    fields["input_files"] = { "before": before_file, "after": after_file }
    println(fields.to_json().stringify(indent=2))
  }
}
