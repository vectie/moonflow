///|
/// Explicit filesystem selection. Suffix matching is case-sensitive; recursive
/// traversal never follows symlinks and excludes hidden files/directories.
pub(all) struct DirectoryPlanSelectionV1 {
  contract_id : String
  directory_ref : String
  template_work_item_id : String
  suffixes : Array[String]
  recursive : Bool
  id_prefix : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DirectoryPlanEntryV1 {
  work_item_id : String
  artifact_ref : String
} derive(Debug, Eq, ToJson)

///|
/// A sorted path inventory and an ordinary editable draft. The inventory digest
/// covers references, not file content; this workflow does not freeze inputs.
pub(all) struct DirectoryPlanImportV1 {
  contract_id : String
  selection_digest : String
  inventory_digest : String
  entries : Array[DirectoryPlanEntryV1]
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
fn directory_plan_reference(reference : String) -> Unit raise {
  guard artifact_ref_is_workspace_relative(reference) &&
    reference.length() <= 4096 &&
    !reference.contains("\\") &&
    !reference.contains("\u{0000}") &&
    reference.split("/").all(part => !part.is_empty() && !part.has_prefix(".")) else {
    fail(
      "directory intake requires a canonical non-hidden workspace-relative path: \{reference}",
    )
  }
}

///|
pub fn decode_directory_plan_selection_v1(
  value : Json,
) -> DirectoryPlanSelectionV1 raise {
  let fields = wire_object(value, "directory plan selection")
  let known = [
    "contract_id", "directory_ref", "template_work_item_id", "suffixes", "recursive",
    "id_prefix",
  ]
  for key, _ in fields {
    guard known.contains(key) else {
      fail("unknown directory plan selection field: \{key}")
    }
  }
  let selection : DirectoryPlanSelectionV1 = @json.from_json(value)
  guard selection.contract_id == "moonflow.directory-plan-selection.v1" else {
    fail("unsupported directory plan selection contract")
  }
  directory_plan_reference(selection.directory_ref)
  guard catalog_safe_identifier(selection.id_prefix) &&
    selection.id_prefix.length() <= 63 &&
    selection.id_prefix != "." &&
    !selection.id_prefix.contains("..") else {
    fail("directory id_prefix must be a safe identifier of 1..63 characters")
  }
  guard !selection.suffixes.is_empty() && selection.suffixes.length() <= 16 else {
    fail("directory selection requires 1..16 suffixes")
  }
  let seen : Array[String] = []
  for suffix in selection.suffixes {
    guard suffix.has_prefix(".") &&
      suffix.length() >= 2 &&
      suffix.length() <= 64 &&
      suffix
      .to_array()
      .all(c => {
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '.' ||
        c == '-' ||
        c == '_'
      }) &&
      !seen.contains(suffix) else {
      fail(
        "directory suffix must be a distinct literal extension, for example .json: \{suffix}",
      )
    }
    seen.push(suffix)
  }
  selection
}

///|
/// Turn the host's selected regular-file inventory into one independent work
/// item per file. Paths are sorted, and IDs hash the full workspace-relative
/// reference, so adding an earlier filename never renumbers existing work.
/// The native host performs traversal/existence checks; this API is pure.
pub fn declared_plan_from_directory_v1(
  source_graph : Json,
  selection_value : Json,
  artifact_refs : Array[String],
  draft_id : String,
  recorded_at : String,
) -> DirectoryPlanImportV1 raise {
  let selection = decode_directory_plan_selection_v1(selection_value)
  guard !artifact_refs.is_empty() && artifact_refs.length() <= 256 else {
    fail("directory intake requires 1..256 matching regular files")
  }
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  guard original.edits
    .filter(edit => edit.work_item_id == selection.template_work_item_id)
    .get(0)
    is Some(template) else {
    fail(
      "directory template is not an original source item: \{selection.template_work_item_id}",
    )
  }
  let paths = artifact_refs.copy()
  paths.sort_by((left, right) => left.lexical_compare(right))
  let entries : Array[DirectoryPlanEntryV1] = []
  let edits : Array[PlanItemEditV1] = []
  let templates : Map[String, String] = {}
  for index, reference in paths {
    directory_plan_reference(reference)
    let prefix = selection.directory_ref + "/"
    guard reference.has_prefix(prefix) && reference.length() > prefix.length() else {
      fail("selected file is outside the declared directory: \{reference}")
    }
    let within = reference.substring(start=prefix.length())
    guard within.split("/").to_array().length() <= 17 else {
      fail("selected file exceeds 16 nested directory levels: \{reference}")
    }
    guard (selection.recursive || !within.contains("/")) &&
      selection.suffixes.any(suffix => within.has_suffix(suffix)) else {
      fail(
        "selected file does not match the declared depth or suffix: \{reference}",
      )
    }
    guard index == 0 || paths[index - 1] != reference else {
      fail("duplicate selected file: \{reference}")
    }
    let id = selection.id_prefix +
      "-" +
      @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(reference)))
    guard !original.edits.any(edit => edit.work_item_id == id) else {
      fail("generated file ID conflicts with a source item: \{id}")
    }
    entries.push({ work_item_id: id, artifact_ref: reference, })
    edits.push({
      work_item_id: id,
      input_artifacts: [reference],
      depends_on: [],
      acceptance_criteria: template.acceptance_criteria.copy(),
      timeout_ms: template.timeout_ms,
    })
    templates[id] = selection.template_work_item_id
  }
  let draft = declared_plan_from_form_v1(
    {
      "contract_id": "moonflow.declared-plan-form-input.v2",
      "source_kind": "existing-graph",
      "source_graph": source_graph,
      "edits": edits.to_json(),
      "added_templates": templates.to_json(),
    },
    draft_id,
    recorded_at,
  )
  {
    contract_id: "moonflow.directory-plan-import.v1",
    selection_digest: plan_digest(selection_value),
    inventory_digest: plan_digest(paths.to_json()),
    entries,
    draft,
  }
}
