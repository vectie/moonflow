///|
struct PlanInputCapture {
  work_item_id : String
  original_ref : String
  captured_ref : String
  sha256 : String
  byte_length : Int
  role : String
  binding_mode : String
} derive(ToJson, FromJson)

///|
fn plan_fields(value : Json, label : String) -> Map[String, Json] raise {
  guard value is Object(fields) else { fail("\{label} must be an object") }
  fields
}

///|
fn plan_string(value : Json, name : String) -> String raise {
  guard plan_fields(value, "plan evidence").get(name) is Some(String(text)) else {
    fail("plan evidence requires \{name}")
  }
  text
}

///|
fn plan_value(value : Json, name : String) -> Json raise {
  guard plan_fields(value, "plan evidence").get(name) is Some(field) else {
    fail("plan evidence requires \{name}")
  }
  field
}

///|
// Check every component, including the final file. Merely resolving inside the
// workspace is insufficient when a mutable symlink changes the selected file.
async fn plan_regular_path(root : String, reference : String) -> String {
  guard @moonflow.artifact_ref_is_workspace_relative(reference) else {
    fail("input_artifacts: unsafe workspace-relative reference \{reference}")
  }
  let mut path = root
  let parts = reference.split("/").to_array()
  for index, part in parts {
    guard part != "" && part != "." && part != ".." else {
      fail("input_artifacts: noncanonical reference \{reference}")
    }
    path += "/" + part.to_owned()
    guard @fs.exists(path) && @fs.realpath(path) == path else {
      fail("input_artifacts: missing or symlinked artifact \{reference}")
    }
    let expected = if index == parts.length() - 1 {
      @fs.Regular
    } else {
      @fs.Directory
    }
    guard @fs.kind(path, follow_symlink=false) == expected else {
      fail("input_artifacts: expected a regular artifact \{reference}")
    }
  }
  path
}

///|
async fn plan_directory(root : String, reference : String) -> String {
  guard @moonflow.artifact_ref_is_workspace_relative(reference) else {
    fail("unsafe preparation directory")
  }
  let mut path = root
  for part in reference.split("/") {
    guard part != "" && part != "." && part != ".." else {
      fail("unsafe preparation directory")
    }
    path += "/" + part.to_owned()
    if !@fs.exists(path) {
      @fs.mkdir(path, permission=0o700)
    }
    guard @fs.realpath(path) == path &&
      @fs.kind(path, follow_symlink=false) == @fs.Directory else {
      fail("preparation directory is not a confined regular directory")
    }
  }
  path
}

///|
async fn plan_read_bytes(root : String, reference : String) -> Bytes {
  let bytes = @fs.read_file(plan_regular_path(root, reference)).binary()
  guard bytes.length() <= 16 * 1024 * 1024 else {
    fail("input_artifacts: \{reference} exceeds the 16 MiB preparation limit")
  }
  bytes
}

///|
async fn plan_read_json(root : String, reference : String) -> Json {
  @json.parse(@utf8.decode(plan_read_bytes(root, reference)))
}

///|
async fn plan_freeze_bytes(
  root : String,
  directory_ref : String,
  name : String,
  bytes : Bytes,
) -> String {
  let directory = plan_directory(root, directory_ref)
  let reference = directory_ref + "/" + name
  if @fs.exists(root + "/" + reference) {
    guard plan_read_bytes(root, reference) == bytes else {
      fail("retained preparation bytes changed: \{reference}")
    }
  } else {
    @flow_host.atomic_replace_named_bytes_v1(directory, name, bytes)
  }
  reference
}

///|
async fn plan_store_json(
  root : String,
  directory_ref : String,
  name : String,
  value : Json,
) -> String {
  plan_freeze_bytes(
    root,
    directory_ref,
    name,
    @utf8.encode(value.stringify(indent=2) + "\n"),
  )
}

///|
async fn plan_capture_bytes(root : String, bytes : Bytes) -> String {
  plan_freeze_bytes(
    root,
    ".moonsuite/products/moonflow/plan-inputs/" + sha256_hex(bytes),
    "artifact",
    bytes,
  )
}

///|
async fn plan_capture_one(
  root : String,
  item : String,
  reference : String,
  role : String,
  binding : String,
) -> PlanInputCapture {
  let bytes = plan_read_bytes(root, reference)
  {
    work_item_id: item,
    original_ref: reference,
    captured_ref: plan_capture_bytes(root, bytes),
    sha256: "sha256:" + sha256_hex(bytes),
    byte_length: bytes.length(),
    role,
    binding_mode: binding,
  }
}

///|
// Mold spatial requests use workspace-relative evidence references. Rebind
// that explicit list while retaining the original request bytes separately.
// Other contracts retain original bindings: their captured top-level bytes
// are inspectable, but no claim is made about unknown nested dependencies.
async fn plan_capture_form(
  root : String,
  form : Json,
) -> (Json, Array[PlanInputCapture], Map[String, String]) {
  let detached = @json.parse(form.stringify())
  let fields = plan_fields(detached, "plan form")
  guard fields.get("edits") is Some(Array(edits)) else {
    fail("edits must be an array")
  }
  let captures : Array[PlanInputCapture] = []
  let input_digests : Map[String, String] = Map([])
  let source = plan_value(form, "source_graph")
  guard plan_value(source, "items") is Array(items) else {
    fail("source items must be an array")
  }
  for edit in edits {
    let id = plan_string(edit, "work_item_id")
    let template_id = match fields.get("added_templates") {
      Some(Object(templates)) =>
        match templates.get(id) {
          Some(String(template)) => template
          _ => id
        }
      _ => id
    }
    let edit_fields = plan_fields(edit, "item edit")
    let refs : Array[String] = @json.from_json(
      plan_value(edit, "input_artifacts"),
    )
    guard !refs.is_empty() && refs.length() <= 64 else {
      fail("\{id}.input_artifacts: require 1..64 artifacts")
    }
    let mut source_item : Json? = None
    for item in items {
      if plan_string(item, "work_item_id") == template_id {
        source_item = Some(item)
      }
    }
    let spatial = match source_item {
      Some(
        {
          "product_id": String("moonmold"),
          "input_contracts": Array(
            [String("moonmold/spatial-operation-request@1.0.0")]
          ),
          ..
        }
      ) => true
      _ => false
    }
    let original_digest = declared_input_digest(root, refs)
    input_digests[id] = original_digest
    let next_refs : Array[String] = []
    for index, reference in refs {
      let capture = plan_capture_one(
        root,
        id,
        reference,
        if index == 0 {
          "primary"
        } else {
          "declared-evidence"
        },
        if spatial {
          "captured-reference"
        } else {
          "original-reference-revalidated"
        },
      )
      captures.push(capture)
      if spatial && index == 0 {
        let payload = plan_read_json(root, capture.captured_ref)
        guard plan_string(payload, "contract_id") ==
          "moonmold.spatial-operation-request.v1" else {
          fail(
            "\{id}.input_artifacts: primary payload does not match the declared Mold spatial contract",
          )
        }
        let payload_fields = plan_fields(payload, "Mold spatial request")
        let dependencies : Array[String] = match
          payload_fields.get("reference_artifacts") {
          Some(value) => @json.from_json(value)
          None => []
        }
        guard dependencies.length() <= 64 else {
          fail("\{id}.reference_artifacts: too many references")
        }
        if dependencies.is_empty() {
          next_refs.push(capture.captured_ref)
        } else {
          let rebound : Array[String] = []
          for dependency in dependencies {
            let child = plan_capture_one(
              root, id, dependency, "spatial-reference-evidence", "captured-reference",
            )
            captures.push(child)
            rebound.push(child.captured_ref)
          }
          payload_fields["reference_artifacts"] = rebound.to_json()
          let bytes = @utf8.encode(payload.stringify(indent=2) + "\n")
          let rebound_ref = plan_capture_bytes(root, bytes)
          captures.push({
            work_item_id: id,
            original_ref: reference,
            captured_ref: rebound_ref,
            sha256: "sha256:" + sha256_hex(bytes),
            byte_length: bytes.length(),
            role: "rebound-primary",
            binding_mode: "captured-reference",
          })
          next_refs.push(rebound_ref)
        }
      } else {
        next_refs.push(if spatial { capture.captured_ref } else { reference })
      }
    }
    edit_fields["input_artifacts"] = next_refs.to_json()
  }
  (detached, captures, input_digests)
}

///|
async fn plan_validate_captures(
  root : String,
  captures : Array[PlanInputCapture],
) -> Unit {
  for capture in captures {
    let bytes = plan_read_bytes(root, capture.captured_ref)
    guard "sha256:" + sha256_hex(bytes) == capture.sha256 &&
      bytes.length() == capture.byte_length else {
      fail(
        "\{capture.work_item_id}.input_artifacts: captured bytes changed: \{capture.captured_ref}",
      )
    }
    if capture.role != "rebound-primary" {
      guard plan_read_bytes(root, capture.original_ref) == bytes else {
        fail(
          "\{capture.work_item_id}.input_artifacts: selected input changed; prepare a new child: \{capture.original_ref}",
        )
      }
    }
  }
}
