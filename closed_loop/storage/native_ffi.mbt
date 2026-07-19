///|
priv type NativeStorageSession

///|
#borrow(workspace, relative, status)
extern "c" fn native_acquire(
  workspace : Bytes,
  relative : Bytes,
  exclusive : Bool,
  status : Ref[Int],
) -> NativeStorageSession = "moonflow_storage_native_acquire"

///|
#borrow(session)
extern "c" fn native_close(session : NativeStorageSession) -> Unit = "moonflow_storage_native_close"

///|
#borrow(parent, relative, status)
extern "c" fn native_open_related(
  parent : NativeStorageSession,
  relative : Bytes,
  status : Ref[Int],
) -> NativeStorageSession = "moonflow_storage_native_open_related"

///|
#borrow(session, status)
extern "c" fn native_root_identity(
  session : NativeStorageSession,
  status : Ref[Int],
) -> Bytes = "moonflow_storage_native_root_identity"

///|
#borrow(session, status)
extern "c" fn native_list(
  session : NativeStorageSession,
  status : Ref[Int],
) -> Bytes = "moonflow_storage_native_list"

///|
#borrow(session, name, status)
extern "c" fn native_read(
  session : NativeStorageSession,
  name : Bytes,
  status : Ref[Int],
) -> Bytes = "moonflow_storage_native_read"

///|
#borrow(session, committed_name, contents)
extern "c" fn native_atomic_store(
  session : NativeStorageSession,
  committed_name : Bytes,
  contents : Bytes,
  fault_point : Int,
) -> Int = "moonflow_storage_native_atomic_store"

///|
let native_fault_point : Ref[Int] = Ref(0)

///|
fn native_status_error(
  operation : String,
  path : String,
  status : Int,
) -> StorageError {
  if status == 100001 {
    UnsafePath(path~)
  } else if status == 100002 {
    SymlinkRejected(path~)
  } else if 200001 <= status && status <= 200008 {
    IoFailure(operation="fault_injection", status=status - 200000)
  } else {
    IoFailure(operation~, status~)
  }
}

///|
fn acquire_native_session(
  workspace_root : String,
  storage_root : String,
  exclusive : Bool,
) -> NativeStorageSession raise StorageError {
  let status = Ref(0)
  let session = native_acquire(
    @utf8.encode(workspace_root),
    @utf8.encode(storage_root),
    exclusive,
    status,
  )
  if status.val != 0 {
    native_close(session)
    raise native_status_error("open_storage", storage_root, status.val)
  }
  session
}

///|
/// Open another storage root while retaining the caller's already-held
/// workspace-global exclusive lock. This is the only non-reentrant path used
/// by cross-root guarded transactions.
fn open_related_native_session(
  parent : NativeStorageSession,
  storage_root : String,
) -> NativeStorageSession raise StorageError {
  let status = Ref(0)
  let session = native_open_related(parent, @utf8.encode(storage_root), status)
  if status.val != 0 {
    native_close(session)
    raise native_status_error("open_related_storage", storage_root, status.val)
  }
  session
}

///|
fn native_session_root_identity(
  session : NativeStorageSession,
) -> String raise StorageError {
  let status = Ref(0)
  let bytes = native_root_identity(session, status)
  if status.val != 0 {
    raise native_status_error("root_identity", "storage_root", status.val)
  }
  @utf8.decode(bytes) catch {
    _ => raise ValidationFailure(field="native_root_identity_utf8")
  }
}

///|
fn native_names(
  session : NativeStorageSession,
) -> Array[String] raise StorageError {
  let status = Ref(0)
  let bytes = native_list(session, status)
  if status.val != 0 {
    raise native_status_error("list_storage", "storage_root", status.val)
  }
  let reader = StorageReader::new(bytes)
  let names : Array[String] = []
  while reader.remaining() > 0 {
    names.push(reader.read_string())
  }
  names.sort()
  names
}

///|
fn native_read_named(
  session : NativeStorageSession,
  name : String,
) -> Bytes raise StorageError {
  let status = Ref(0)
  let bytes = native_read(session, @utf8.encode(name), status)
  if status.val != 0 {
    raise native_status_error("read_storage", name, status.val)
  }
  bytes
}

///|
fn native_atomic_store_named(
  session : NativeStorageSession,
  name : String,
  contents : Bytes,
) -> Unit raise StorageError {
  let status = native_atomic_store(
    session,
    @utf8.encode(name),
    contents,
    native_fault_point.val,
  )
  native_fault_point.val = 0
  if status != 0 {
    raise native_status_error("atomic_store", name, status)
  }
}
