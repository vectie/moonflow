///|
pub fn normalize_workspace_path(path : String) -> String {
  let parts : Array[String] = []
  for part in path.split("/") {
    match part {
      "" | "." => ()
      ".." => if !parts.is_empty() { ignore(parts.pop()) }
      _ => parts.push(part.to_owned())
    }
  }
  "/" + parts.join("/")
}

///|
pub fn path_is_within_workspace(workspace_root : String, candidate : String) -> Bool {
  if !workspace_root.has_prefix("/") || !candidate.has_prefix("/") {
    return false
  }
  let root = normalize_workspace_path(workspace_root)
  let path = normalize_workspace_path(candidate)
  path == root || path.has_prefix(root + "/")
}
