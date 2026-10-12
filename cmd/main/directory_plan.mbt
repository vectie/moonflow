///|
// Read-only counterpart to plan_directory: intake never creates missing paths.
async fn plan_existing_directory(root : String, reference : String) -> String {
  guard @moonflow.artifact_ref_is_workspace_relative(reference) else {
    fail("unsafe input directory")
  }
  let mut path = root
  for part in reference.split("/") {
    guard !part.is_empty() && !part.has_prefix(".") else {
      fail("input directory must be canonical and non-hidden")
    }
    path += "/" + part.to_owned()
    guard @fs.kind(path, follow_symlink=false) == @fs.Directory &&
      @fs.realpath(path) == path else {
      fail(
        "input directory is missing, symlinked or not a directory: \{reference}",
      )
    }
  }
  path
}

///|
struct DirectoryPlanScan {
  paths : Array[String]
  scanned_entries : Int
  skipped_symlink_refs : Array[String]
} derive(ToJson)

///|
async fn plan_scan_directory(
  root : String,
  selection : @moonflow.DirectoryPlanSelectionV1,
) -> DirectoryPlanScan {
  let pending : Array[(String, Int)] = [(selection.directory_ref, 0)]
  let paths : Array[String] = []
  let skipped_symlink_refs : Array[String] = []
  let mut scanned_entries = 0
  for cursor = 0; cursor < pending.length(); cursor = cursor + 1 {
    let (reference, depth) = pending[cursor]
    let directory = @fs.opendir(plan_existing_directory(root, reference))
    defer directory.close()
    while directory.next(include_hidden=true) is Some(entry) {
      scanned_entries += 1
      guard scanned_entries <= 8192 else {
        fail(
          "directory intake exceeds 8192 visited entries; select a smaller folder",
        )
      }
      if entry.name.has_prefix(".") {
        continue
      }
      let child = reference + "/" + entry.name
      let kind = @fs.kind(root + "/" + child, follow_symlink=false)
      let matches = selection.suffixes.any(suffix => {
        entry.name.has_suffix(suffix)
      })
      match kind {
        @fs.Directory =>
          if selection.recursive {
            guard depth < 16 else {
              fail(
                "directory intake exceeds 16 nested levels; select a narrower folder",
              )
            }
            pending.push((child, depth + 1))
          }
        @fs.Regular =>
          if matches {
            ignore(plan_regular_path(root, child))
            paths.push(child)
            guard paths.length() <= 256 else {
              fail(
                "directory intake exceeds 256 matching files; select a smaller folder",
              )
            }
          }
        @fs.SymLink => {
          guard !matches else {
            fail("matching input is a symlink, not a regular file: \{child}")
          }
          skipped_symlink_refs.push(child)
        }
        _ => {
          guard !matches else {
            fail("matching input is not a regular file: \{child}")
          }
        }
      }
    }
  }
  skipped_symlink_refs.sort_by((left, right) => left.lexical_compare(right))
  { paths, scanned_entries, skipped_symlink_refs, }
}

///|
async fn plan_directory_command(
  workspace : String,
  source_ref : String,
  selection_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  ignore(safe_id(draft_id, "draft_id"))
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let source = plan_read_json(root, source_ref)
  let selection_value = plan_read_json(root, selection_ref)
  let selection = @moonflow.decode_directory_plan_selection_v1(selection_value)
  let scan = plan_scan_directory(root, selection)
  let imported = @moonflow.declared_plan_from_directory_v1(
    source,
    selection_value,
    scan.paths,
    draft_id,
    recorded_at,
  )
  if save {
    let directory = plan_directory(
      root, ".moonsuite/products/moonflow/plan-drafts",
    )
    let lock = @flow_host.acquire_named_writer_lock_v1(
      directory,
      safe_id(draft_id, "draft_id"),
    )
    defer @flow_host.release_named_writer_lock_v1(lock)
    let path = directory + "/" + draft_id + ".json"
    if @fs.exists(path) {
      guard plan_load_draft(root, draft_id) == imported.draft else {
        fail(
          "draft identity already exists; reopen it or choose a new draft_id",
        )
      }
    } else {
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
        "contract_id": "moonflow.directory-plan-receipt.v1",
        "source_ref": source_ref,
        "selection_ref": selection_ref,
        "selection": selection.to_json(),
        "selection_digest": imported.selection_digest,
        "inventory_digest": imported.inventory_digest,
        "entries": imported.entries.to_json(),
        "scanned_entry_count": scan.scanned_entries,
        "skipped_symlink_refs": scan.skipped_symlink_refs.to_json(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(imported.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-directory"
        },
      } : Json).stringify(indent=2),
  )
}
