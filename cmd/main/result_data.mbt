///|
async fn read_result_data_bytes(
  root : String,
  artifact_ref : String,
  max_bytes : Int,
) -> Bytes {
  validate_artifact_ref(root, artifact_ref)
  guard @fs.kind(root + "/" + artifact_ref, follow_symlink=true) == @fs.Regular else {
    fail("result data requires a regular file: \{artifact_ref}")
  }
  let file = @fs.open(root + "/" + artifact_ref, mode=ReadOnly)
  defer file.close()
  guard file.kind() == @fs.Regular else {
    fail("result data requires a regular file: \{artifact_ref}")
  }
  let size = file.size()
  guard size >= 0 && size <= max_bytes.to_int64() else {
    fail("result data file exceeds \{max_bytes} bytes: \{artifact_ref}")
  }
  file.read_exactly_at(size.to_int(), position=0)
}

///|
async fn show_result_data(
  workspace : String,
  mapping_ref : String,
  format : String,
  run_ids : Array[String],
) -> Unit {
  guard format == "--json" || format == "--csv" else {
    fail("Use --csv or --json")
  }
  guard run_ids.length() > 0 && run_ids.length() <= 64 else {
    fail("Select 1..64 runs")
  }
  let seen : Array[String] = []
  for id in run_ids {
    ignore(safe_id(id, "run_id"))
    guard !seen.contains(id) else { fail("Duplicate results run: " + id) }
    seen.push(id)
  }
  validate_artifact_ref(workspace, mapping_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let mapping_bytes = read_result_data_bytes(root, mapping_ref, 65536)
  let mapping = @json.parse(@utf8.decode(mapping_bytes), max_nesting_depth=64)
  let runs : Array[@moonflow.RunProjection] = []
  for id in run_ids {
    runs.push(@moonflow.replay(id, load_events(root, id)))
  }
  let artifacts : Map[String, Bytes] = {}
  let mut total_bytes = 0
  for artifact_ref in @moonflow.result_data_sources_v1(runs, mapping) {
    let bytes = read_result_data_bytes(root, artifact_ref, 1048576)
    total_bytes += bytes.length()
    guard total_bytes <= 67108864 else {
      fail("selected result outputs exceed 64 MiB")
    }
    artifacts[artifact_ref] = bytes
  }
  let table = @moonflow.result_data_table_v1(runs, mapping, artifacts)
  println(
    if format == "--csv" {
      @moonflow.result_data_csv_v1(table)
    } else {
      table.to_json().stringify(indent=2)
    },
  )
}
