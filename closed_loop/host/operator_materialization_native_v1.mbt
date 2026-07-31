///|
/// Atomic same-directory replacement used after a complete temporary write.
/// POSIX rename preserves the prior target if replacement fails.
#borrow(source, destination)
extern "c" fn operator_materialization_native_rename_v1(
  source : Bytes,
  destination : Bytes,
) -> Int = "moonflow_operator_materialization_native_rename_v1"

///|
#borrow(path)
extern "c" fn operator_materialization_native_lock_v1(
  path : Bytes,
) -> Int = "moonflow_operator_materialization_native_lock_v1"

///|
extern "c" fn operator_materialization_native_unlock_v1(
  handle : Int,
) -> Int = "moonflow_operator_materialization_native_unlock_v1"

///|
fn operator_materialization_atomic_replace_v1(
  source : String,
  destination : String,
) -> Unit raise {
  let status = operator_materialization_native_rename_v1(
    @utf8.encode(source),
    @utf8.encode(destination),
  )
  if status != 0 {
    fail(
      "operator materialization atomic replacement failed (status \{status})",
    )
  }
}

///|
/// Persist canonical JSON using a complete same-directory temporary followed
/// by POSIX atomic replacement. The caller still owns semantic expected-head
/// validation; this function owns crash-safe visibility of the resulting file.
pub async fn atomic_replace_named_json_v1(
  directory : String,
  name : String,
  canonical_json : String,
) -> Unit {
  if !directory.has_prefix("/") ||
    name.is_blank() ||
    name.contains("/") ||
    name.contains("\\") ||
    name.contains("..") {
    fail("atomic JSON destination is not canonical")
  }
  if !@fs.exists(directory) {
    @fs.mkdir(directory, permission=0o755, recursive=true)
  }
  let canonical_directory = @fs.realpath(directory)
  if canonical_directory != directory {
    fail("atomic JSON directory must be canonical")
  }
  let bytes = @utf8.encode(canonical_json + "\n")
  let digest = @contracts.sha256_digest(bytes)
  let target = directory + "/" + name
  let temporary = directory + "/." + name + "." + digest.hex() + ".tmp"
  @fs.write_file(
    temporary,
    bytes,
    sync=Full,
    create=0o600,
    truncate=true,
  )
  operator_materialization_atomic_replace_v1(temporary, target)
}

///|
/// Acquire a process-scoped advisory lock. The operating system releases the
/// descriptor if the process exits, so a crashed writer cannot leave a stale
/// lock that permanently blocks the workspace.
pub async fn acquire_named_writer_lock_v1(
  directory : String,
  name : String,
) -> Int {
  if !directory.has_prefix("/") ||
    name.is_blank() ||
    name.contains("/") ||
    name.contains("\\") ||
    name.contains("..") {
    fail("writer lock destination is not canonical")
  }
  if !@fs.exists(directory) {
    @fs.mkdir(directory, permission=0o755, recursive=true)
  }
  let canonical_directory = @fs.realpath(directory)
  if canonical_directory != directory {
    fail("writer lock directory must be canonical")
  }
  let handle = operator_materialization_native_lock_v1(
    @utf8.encode(directory + "/." + name + ".lock"),
  )
  if handle < 0 {
    fail("failed to acquire writer lock (status \{handle})")
  }
  handle
}

///|
pub fn release_named_writer_lock_v1(handle : Int) -> Unit {
  // Closing the descriptor releases the lock even when explicit LOCK_UN reports
  // an error, so cleanup must remain non-raising and safe inside `defer`.
  ignore(operator_materialization_native_unlock_v1(handle))
}

///|
fn require_run_root_v1(value : String) -> Unit raise {
  if !value.has_prefix("/") ||
    value.contains("\\") ||
    value.iter().any(char => char.is_control()) ||
    (value.length() > 1 && value.has_suffix("/")) {
    fail("operator run root must be a canonical absolute path")
  }
}

///|
fn require_run_id_v1(value : String) -> Unit raise {
  if value.trim().is_empty() ||
    value == "." ||
    value == ".." ||
    value.contains("/") ||
    value.contains("\\") ||
    value.contains("..") ||
    value.iter().any(char => char.is_control()) {
    fail("operator run id must be a safe identifier")
  }
}

///|
pub struct OperatorProjectionMaterializationReceiptV1 {
  path : String
  content_digest : @contracts.ContentDigest
  byte_length : Int
  canonical_json : String
  digest : @contracts.ContentDigest
}

///|
pub async fn materialize_operator_projection_v1(
  run_root : String,
  run_id : String,
  materialization : @orchestration.OperatorProjectionMaterializationV1,
) -> OperatorProjectionMaterializationReceiptV1 {
  require_run_root_v1(run_root)
  require_run_id_v1(run_id)
  if materialization.relative_path() != "operator-projection.json" ||
    @contracts.sha256_digest(materialization.bytes()) !=
    materialization.digest() {
    fail("operator materialization bytes do not match their digest")
  }
  let canonical_root = @fs.realpath(run_root)
  if canonical_root != run_root {
    fail("operator run root must already be canonical")
  }
  let run_path = if run_root == "/" {
    "/\{run_id}"
  } else {
    "\{run_root}/\{run_id}"
  }
  if !@fs.exists(run_path) {
    @fs.mkdir(run_path, permission=0o755, recursive=false)
  }
  let canonical_run = @fs.realpath(run_path)
  if canonical_run != run_path ||
    (run_root != "/" && !canonical_run.has_prefix(run_root + "/")) {
    fail("operator run path escapes the supplied root")
  }
  let target = "\{canonical_run}/operator-projection.json"
  let temporary = "\{canonical_run}/.operator-projection.\{materialization.digest().hex()}.tmp"
  @fs.write_file(
    temporary,
    materialization.bytes(),
    create=0o600,
    truncate=true,
  )
  operator_materialization_atomic_replace_v1(temporary, target)
  let json : Json = {
    "contract_id": "moonflow.operator-materialization-receipt.v1",
    "contract_version": "1.0.0",
    "path": target,
    "content_digest": materialization.digest().text(),
    "byte_length": materialization.bytes().length().to_string(),
  }
  let canonical_json = json.stringify()
  {
    path: target,
    content_digest: materialization.digest(),
    byte_length: materialization.bytes().length(),
    canonical_json,
    digest: @contracts.sha256_digest(@utf8.encode(canonical_json)),
  }
}

///|
pub fn OperatorProjectionMaterializationReceiptV1::to_json(
  self : OperatorProjectionMaterializationReceiptV1,
) -> Json {
  {
    "contract_id": "moonflow.operator-materialization-receipt.v1",
    "contract_version": "1.0.0",
    "path": self.path,
    "content_digest": self.content_digest.text(),
    "byte_length": self.byte_length.to_string(),
    "receipt_digest": self.digest.text(),
  }
}
