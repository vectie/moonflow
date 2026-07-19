///|
fn artifact_ref_is_workspace_relative(path : String) -> Bool {
  !path.has_prefix("/")
}
