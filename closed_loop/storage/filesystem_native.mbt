///|
priv struct NativeBatchEntry {
  name : String
  batch : StoredBatch
}

///|
priv struct NativeRegistryEntry {
  name : String
  binding : GuardedWorkflowBinding
}

///|
priv struct NativeState {
  batches : Array[StoredBatch]
  checkpoints : Array[CheckpointRecord]
  registry_declarations : Array[NativeRegistryEntry]
  registry_markers : Array[NativeRegistryEntry]
}

///|
fn require_workspace_root(value : String) -> Unit raise StorageError {
  if !value.has_prefix("/") ||
    value.contains("\\") ||
    value.iter().any(char => char.is_control()) ||
    (value.length() > 1 && value.has_suffix("/")) {
    raise UnsafePath(path=value)
  }
}

///|
fn require_relative_storage_root(value : String) -> Unit raise StorageError {
  if value.is_empty() ||
    value.has_prefix("/") ||
    value.has_suffix("/") ||
    value.contains("\\") ||
    value.iter().any(char => char.is_control()) {
    raise UnsafePath(path=value)
  }
  for segment in value.split("/") {
    if segment.is_empty() || segment == "." || segment == ".." {
      raise UnsafePath(path=value)
    }
  }
}

///|
fn workflow_storage_key(workflow : @contracts.RecordRef) -> String {
  @contracts.sha256_digest(encode_record_ref(workflow, false)).hex()
}

///|
fn fixed_int64_hex(value : Int64) -> String {
  let text = value.reinterpret_as_uint64().to_string(radix=16)
  let builder = StringBuilder()
  for _ in text.length()..<16 {
    builder.write_string("0")
  }
  builder.write_string(text)
  builder.to_string()
}

///|
fn batch_file_name(batch : StoredBatch) -> String {
  let workflow_key = workflow_storage_key(batch.request.workflow)
  let sequence = fixed_int64_hex(batch.result.first_sequence)
  let digest = batch.result.batch_digest.hex()
  "batch-\{workflow_key}-\{sequence}-\{digest}.mfb"
}

///|
fn checkpoint_file_name(checkpoint : CheckpointRecord) -> String {
  let workflow_key = workflow_storage_key(checkpoint.workflow)
  let sequence = fixed_int64_hex(checkpoint.event_sequence)
  let digest = checkpoint.checkpoint_ref.digest().hex()
  "checkpoint-\{workflow_key}-\{sequence}-\{digest}.mfc"
}

///|
fn decode_committed_batch(
  name : String,
  bytes : Bytes,
) -> StoredBatch raise StorageError {
  decode_batch(bytes) catch {
    UnsupportedVersion(record_kind~, version~) =>
      raise UnsupportedVersion(record_kind~, version~)
    DigestMismatch(record_kind~, record_id~, expected~, actual~) =>
      raise DigestMismatch(record_kind~, record_id~, expected~, actual~)
    _ => raise CorruptCommittedData(name~)
  }
}

///|
fn load_native_state(
  session : NativeStorageSession,
) -> NativeState raise StorageError {
  let batch_entries : Array[NativeBatchEntry] = []
  let checkpoints : Array[CheckpointRecord] = []
  let registry_declarations : Array[NativeRegistryEntry] = []
  let registry_markers : Array[NativeRegistryEntry] = []
  for name in native_names(session) {
    if name == ".flow4a.lock" || name.has_prefix(".flow4a-tmp-") {
      continue
    }
    if name.has_prefix("batch-") && name.has_suffix(".mfb") {
      let batch = decode_committed_batch(name, native_read_named(session, name))
      if batch_file_name(batch) != name {
        raise CorruptCommittedData(name~)
      }
      batch_entries.push({ name, batch })
    } else if name.has_prefix("checkpoint-") && name.has_suffix(".mfc") {
      let bytes = native_read_named(session, name)
      try decode_checkpoint(bytes) catch {
        _ => ()
      } noraise {
        checkpoint =>
          if checkpoint_file_name(checkpoint) == name {
            checkpoints.push(checkpoint)
          }
      }
    } else if is_guarded_registry_declaration_name(name) {
      let binding = decode_guarded_registry_declaration(
        native_read_named(session, name),
      ) catch {
        _ => raise GuardedRegistryCorrupt(name~)
      }
      if !guarded_registry_name_matches(name, binding) {
        raise GuardedRegistryCorrupt(name~)
      }
      registry_declarations.push({ name, binding })
    } else if is_guarded_binding_marker_name(name) {
      let binding = decode_guarded_workflow_binding(
        native_read_named(session, name),
      ) catch {
        _ => raise GuardedRegistryCorrupt(name~)
      }
      if guarded_binding_marker_name(binding) != name {
        raise GuardedRegistryCorrupt(name~)
      }
      registry_markers.push({ name, binding })
    } else {
      raise CorruptCommittedData(name~)
    }
  }
  for index, entry in batch_entries {
    for prior_index in 0..<index {
      let prior = batch_entries[prior_index]
      if exact_record_equal(
          prior.batch.request.workflow,
          entry.batch.request.workflow,
        ) &&
        prior.batch.result.first_sequence == entry.batch.result.first_sequence {
        raise CorruptCommittedData(name=entry.name)
      }
    }
  }
  let batches = batch_entries.map(entry => entry.batch)
  validate_batches(batches)
  for declaration in registry_declarations {
    ignore(
      latest_guarded_binding(
        registry_declarations.map(value => value.binding),
        declaration.binding.mutation_workflow,
      ) catch {
        _ => raise GuardedRegistryCorrupt(name=declaration.name)
      },
    )
  }
  for marker in registry_markers {
    if !registry_declarations.any(declaration => {
        declaration.binding.registry_digest == marker.binding.registry_digest &&
        declaration.binding.canonical == marker.binding.canonical
      }) {
      raise GuardedRegistryCorrupt(name=marker.name)
    }
  }
  { batches, checkpoints, registry_declarations, registry_markers }
}

///|
fn NativeState::require_binding_marker(
  self : NativeState,
  binding : GuardedWorkflowBinding,
) -> Unit raise StorageError {
  let expected = guarded_binding_marker_name(binding)
  for marker in self.registry_markers {
    if marker.binding.registry_digest == binding.registry_digest {
      if marker.name != expected ||
        marker.binding.canonical != binding.canonical {
        raise GuardedRegistryCorrupt(name=marker.name)
      }
      return
    }
  }
  raise GuardedRegistryMissing(name=expected)
}

///|
fn NativeState::registered_binding(
  self : NativeState,
  store : FileSystemStore,
  workflow : @contracts.RecordRef,
) -> GuardedWorkflowBinding? raise StorageError {
  // A declaring root with any missing marker is fail-closed for raw mutation
  // and official guarded capability use.
  for declaration in self.registry_declarations {
    self.require_binding_marker(declaration.binding)
  }
  let bindings = self.registry_declarations.map(value => value.binding)
  guard latest_guarded_binding(bindings, workflow) is Some(binding) else {
    return None
  }
  if binding.store_domain != "filesystem" ||
    binding.workspace_identity != store.workspace_root ||
    binding.mutation_root_locator != store.storage_root ||
    binding.mutation_root_identity != store.root_identity {
    raise GuardedBindingConflict(
      workflow_id=workflow.id(),
      field="filesystem_root_identity",
    )
  }
  Some(binding)
}

///|
/// Native crash-safe reference implementation. The caller supplies an exact
/// canonical absolute workspace root and a generic relative storage root.
pub struct FileSystemStore {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  workspace_root : String
  storage_root : String
  root_identity : String
}

///|
pub fn FileSystemStore::open(
  workspace_root : String,
  storage_root : String,
) -> FileSystemStore raise StorageError {
  require_workspace_root(workspace_root)
  require_relative_storage_root(storage_root)
  let session = acquire_native_session(workspace_root, storage_root, false)
  let root_identity = native_session_root_identity(session)
  native_close(session)
  {
    record_version: storage_version("1.0.0", "filesystem_store"),
    schema_version: storage_version("1.0.0", "filesystem_store_schema"),
    workspace_root,
    storage_root,
    root_identity,
  }
}

///|
pub fn FileSystemStore::record_version(
  self : FileSystemStore,
) -> @contracts.Version {
  self.record_version
}

///|
pub fn FileSystemStore::schema_version(
  self : FileSystemStore,
) -> @contracts.Version {
  self.schema_version
}

///|
pub fn FileSystemStore::workspace_root(self : FileSystemStore) -> String {
  self.workspace_root
}

///|
pub fn FileSystemStore::storage_root(self : FileSystemStore) -> String {
  self.storage_root
}

///|
/// Returns an opaque activation receipt only when the durable registry already
/// contains a current binding for this exact store and workflow. Native hosts
/// use this to reopen registry-bound profiles without reconstructing registry
/// authority from configuration bytes.
pub fn FileSystemStore::current_guarded_activation_receipt(
  self : FileSystemStore,
  workflow : @contracts.RecordRef,
) -> GuardedWorkflowActivationReceipt? raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    true,
  )
  try {
    let state = load_native_state(session)
    let result = match state.registered_binding(self, workflow) {
      Some(binding) => Some(make_guarded_activation_receipt(binding))
      None => None
    }
    native_close(session)
    result
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub fn FileSystemStore::commit(
  self : FileSystemStore,
  request : CommitRequest,
) -> CommitResult raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    true,
  )
  try {
    let state = load_native_state(session)
    match state.registered_binding(self, request.workflow) {
      Some(binding) =>
        raise GuardedCommitRequired(
          workflow_id=request.workflow.id(),
          key=request.command_idempotency_key,
          binding_digest=binding.registry_digest.text(),
        )
      None => ()
    }
    match prepare_commit(state.batches, request) {
      (Some(existing), None) => {
        native_close(session)
        existing.result
      }
      (None, Some(batch)) => {
        native_atomic_store_named(
          session,
          batch_file_name(batch),
          encode_batch(batch),
        )
        native_close(session)
        batch.result
      }
      _ => {
        native_close(session)
        raise ValidationFailure(field="commit_classification")
      }
    }
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
/// Guarded transaction for the case where mutation and all guarded workflows
/// share this one storage root. The workspace-global exclusive lock covers
/// guard replay, ordinary work CAS, and publication.
pub fn FileSystemStore::guarded_commit(
  self : FileSystemStore,
  request : GuardedCommitRequest,
) -> GuardedCommitOutcome raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    true,
  )
  try {
    let state = load_native_state(session)
    match state.registered_binding(self, request.mutation.workflow) {
      Some(binding) => {
        guard guarded_request_matching_profile(request, binding)
          is Some(profile) else {
          raise GuardedBindingConflict(
            workflow_id=request.mutation.workflow.id(),
            field="guard_set",
          )
        }
        if profile.guard_root_identities.any(root => root != self.root_identity) {
          raise GuardedBindingConflict(
            workflow_id=request.mutation.workflow.id(),
            field="guard_set",
          )
        }
        require_binding_activation_prefix(
          binding,
          replay_from_state(
            state.batches,
            state.checkpoints,
            request.mutation.workflow,
          ),
        )
      }
      None => ()
    }
    let guard_replays = [
      for head_guard in request.guards => {
        replay_from_state(state.batches, state.checkpoints, head_guard.workflow)
      }
    ]
    let outcome = match
      prepare_guarded_commit(state.batches, guard_replays, request) {
      (Some(existing), None, None) => GuardedCommitSucceeded(existing.result)
      (None, Some(batch), None) => {
        native_atomic_store_named(
          session,
          batch_file_name(batch),
          encode_batch(batch),
        )
        GuardedCommitSucceeded(batch.result)
      }
      (None, None, Some(receipt)) => GuardedCommitRejected(receipt)
      _ => raise ValidationFailure(field="guarded_commit_classification")
    }
    native_close(session)
    outcome
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub fn FileSystemStore::replay(
  self : FileSystemStore,
  workflow : @contracts.RecordRef,
) -> ReplayResult raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    false,
  )
  try {
    let state = load_native_state(session)
    let result = replay_from_state(state.batches, state.checkpoints, workflow)
    native_close(session)
    result
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub fn FileSystemStore::write_checkpoint(
  self : FileSystemStore,
  checkpoint : CheckpointRecord,
) -> Unit raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    true,
  )
  try {
    let state = load_native_state(session)
    let events = events_from_batches(state.batches, checkpoint.workflow)
    if !checkpoint_is_valid(checkpoint, checkpoint.workflow, events) {
      raise ValidationFailure(field="checkpoint_boundary")
    }
    for existing in state.checkpoints {
      if record_identity_equal(
          existing.checkpoint_ref,
          checkpoint.checkpoint_ref,
        ) {
        if existing == checkpoint {
          native_close(session)
          return
        }
        raise IdentityConflict(
          kind=checkpoint.checkpoint_ref.kind(),
          id=checkpoint.checkpoint_ref.id(),
          version=checkpoint.checkpoint_ref.version().text(),
        )
      }
    }
    native_atomic_store_named(
      session,
      checkpoint_file_name(checkpoint),
      checkpoint.canonical_bytes(),
    )
    native_close(session)
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub fn FileSystemStore::read_checkpoint(
  self : FileSystemStore,
  workflow : @contracts.RecordRef,
) -> CheckpointRecord? raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    false,
  )
  try {
    let state = load_native_state(session)
    let result = latest_valid_checkpoint(
      state.checkpoints,
      workflow,
      events_from_batches(state.batches, workflow),
    )
    native_close(session)
    result
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub fn FileSystemStore::head(
  self : FileSystemStore,
  workflow : @contracts.RecordRef,
) -> WorkflowHead raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    false,
  )
  try {
    let state = load_native_state(session)
    let result = head_from_batches(state.batches, workflow)
    native_close(session)
    result
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub fn FileSystemStore::events(
  self : FileSystemStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[WorkflowEvent] raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    false,
  )
  try {
    let state = load_native_state(session)
    let result = ReadOnlyArray::from_array(
      events_from_batches(state.batches, workflow),
    )
    native_close(session)
    result
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub fn FileSystemStore::intents(
  self : FileSystemStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[OutboxIntent] raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    false,
  )
  try {
    let state = load_native_state(session)
    let result = ReadOnlyArray::from_array(
      intents_from_batches(state.batches, workflow),
    )
    native_close(session)
    result
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub impl StoragePort for FileSystemStore with fn commit(self, request) {
  self.commit(request)
}

///|
pub impl StoragePort for FileSystemStore with fn replay(self, workflow) {
  self.replay(workflow)
}

///|
pub impl StoragePort for FileSystemStore with fn write_checkpoint(
  self,
  checkpoint,
) {
  self.write_checkpoint(checkpoint)
}

///|
pub impl StoragePort for FileSystemStore with fn read_checkpoint(self, workflow) {
  self.read_checkpoint(workflow)
}

///|
pub impl StoragePort for FileSystemStore with fn head(self, workflow) {
  self.head(workflow)
}

///|
pub impl StoragePort for FileSystemStore with fn events(self, workflow) {
  self.events(workflow)
}

///|
pub impl StoragePort for FileSystemStore with fn intents(self, workflow) {
  self.intents(workflow)
}

///|
pub impl GuardedStoragePort for FileSystemStore with fn guarded_commit(
  self,
  request,
) {
  self.guarded_commit(request)
}

///|
/// Trusted host bootstrap/migration operation. The first activation trusts the
/// caller and OS permissions to select the authoritative roots. Absolute
/// canonical identities are then immutable; relocation or copied roots require
/// a future explicit trusted restore/rebind workflow and are never accepted
/// silently.
pub fn FileSystemStore::activate_guarded_workflow(
  self : FileSystemStore,
  mutation_workflow : @contracts.RecordRef,
  guard_stores : Array[FileSystemStore],
  guard_workflows : Array[@contracts.RecordRef],
) -> GuardedWorkflowActivationReceipt raise StorageError {
  let config = GuardProfileConfig::new(
    default_guard_profile_id(),
    default_guard_profile_name(),
    guard_workflows,
  )
  self.activate_guarded_workflow_profiles_internal(
    mutation_workflow,
    [config],
    [guard_stores],
    false,
  )
}

///|
/// Registers several operation-specific profiles in one initial durable
/// registry generation. Each nested store list is ordered exactly like the
/// corresponding profile's workflow list.
pub fn FileSystemStore::activate_guarded_workflow_profiles(
  self : FileSystemStore,
  mutation_workflow : @contracts.RecordRef,
  configs : Array[GuardProfileConfig],
  guard_store_profiles : Array[Array[FileSystemStore]],
) -> GuardedWorkflowActivationReceipt raise StorageError {
  self.activate_guarded_workflow_profiles_internal(
    mutation_workflow, configs, guard_store_profiles, true,
  )
}

///|
fn FileSystemStore::activate_guarded_workflow_profiles_internal(
  self : FileSystemStore,
  mutation_workflow : @contracts.RecordRef,
  configs : Array[GuardProfileConfig],
  guard_store_profiles : Array[Array[FileSystemStore]],
  require_exact_registry : Bool,
) -> GuardedWorkflowActivationReceipt raise StorageError {
  if configs.is_empty() || configs.length() != guard_store_profiles.length() {
    raise ValidationFailure(field="filesystem_guard_profiles")
  }
  let profile_locators : Array[Array[String]] = []
  let profile_identities : Array[Array[String]] = []
  for profile_index, config in configs {
    let guard_stores = guard_store_profiles[profile_index]
    if guard_stores.length() != config.guard_workflows.length() {
      raise ValidationFailure(field="filesystem_guard_profile_roots")
    }
    let locators : Array[String] = []
    let identities : Array[String] = []
    for guard_store in guard_stores {
      if guard_store.workspace_root != self.workspace_root {
        raise GuardedBindingConflict(
          workflow_id=mutation_workflow.id(),
          field="workspace_identity",
        )
      }
      if guard_store.storage_root == self.storage_root {
        raise GuardedBindingConflict(
          workflow_id=mutation_workflow.id(),
          field="guard_root_independence",
        )
      }
      locators.push(guard_store.storage_root)
      identities.push(guard_store.root_identity)
    }
    profile_locators.push(locators)
    profile_identities.push(identities)
  }
  let primary = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    true,
  )
  let related : Array[NativeStorageSession] = []
  try {
    let state = load_native_state(primary)
    for profile_index, config in configs {
      for workflow_index, workflow in config.guard_workflows {
        let session = open_related_native_session(
          primary,
          profile_locators[profile_index][workflow_index],
        )
        related.push(session)
        if native_session_root_identity(session) !=
          profile_identities[profile_index][workflow_index] {
          raise GuardedBindingConflict(
            workflow_id=mutation_workflow.id(),
            field="guard_root_identity",
          )
        }
        let guard_state = load_native_state(session)
        ignore(
          replay_from_state(
            guard_state.batches,
            guard_state.checkpoints,
            workflow,
          ),
        )
      }
    }
    let declared = state.registry_declarations.map(value => value.binding)
    match latest_guarded_binding(declared, mutation_workflow) {
      Some(binding) => {
        let configuration_matches = if require_exact_registry {
          profiles_configuration_matches(
            binding, configs, profile_locators, profile_identities,
          )
        } else {
          match find_guard_profile(binding, default_guard_profile_id()) {
            Some(profile) =>
              profile_configuration_matches(
                profile,
                configs[0],
                profile_locators[0],
                profile_identities[0],
              )
            None => false
          }
        }
        if binding.store_domain != "filesystem" ||
          binding.workspace_identity != self.workspace_root ||
          binding.mutation_root_locator != self.storage_root ||
          binding.mutation_root_identity != self.root_identity ||
          !configuration_matches {
          raise GuardedBindingConflict(
            workflow_id=mutation_workflow.id(),
            field="binding_configuration",
          )
        }
        require_binding_activation_prefix(
          binding,
          replay_from_state(state.batches, state.checkpoints, mutation_workflow),
        )
        state.require_binding_marker(binding) catch {
          GuardedRegistryMissing(_) =>
            native_atomic_store_named(
              primary,
              guarded_binding_marker_name(binding),
              binding.canonical,
            )
          error => raise error
        }
        for session in related {
          native_close(session)
        }
        native_close(primary)
        return make_guarded_activation_receipt(binding)
      }
      None => ()
    }
    let replay = replay_from_state(
      state.batches,
      state.checkpoints,
      mutation_workflow,
    )
    let profiles : Array[GuardProfile] = []
    for index, config in configs {
      profiles.push(
        new_guard_profile(
          config,
          mutation_workflow,
          profile_locators[index],
          profile_identities[index],
        ),
      )
    }
    let binding = new_guarded_workflow_binding_profiles(
      "filesystem",
      self.workspace_root,
      self.storage_root,
      self.root_identity,
      mutation_workflow,
      profiles,
      replay,
    )
    // Declaration-first publication is the fail-closed activation boundary.
    // If marker publication is interrupted, all raw mutation and official
    // guarded use reject until this trusted operation completes the same exact
    // binding under the workspace lock.
    native_atomic_store_named(
      primary,
      guarded_registry_binding_name(binding),
      guarded_registry_declaration_bytes(binding),
    )
    native_atomic_store_named(
      primary,
      guarded_binding_marker_name(binding),
      binding.canonical,
    )
    for session in related {
      native_close(session)
    }
    native_close(primary)
    make_guarded_activation_receipt(binding)
  } catch {
    error => {
      for session in related {
        native_close(session)
      }
      native_close(primary)
      raise error
    }
  }
}

///|
/// Appends one exact profile to the current durable binding. The prior receipt
/// is a compare-and-swap token over registry generation and digest.
pub fn FileSystemStore::add_guard_profile(
  self : FileSystemStore,
  mutation_workflow : @contracts.RecordRef,
  prior_receipt : GuardedWorkflowActivationReceipt,
  config : GuardProfileConfig,
  guard_stores : Array[FileSystemStore],
) -> GuardedWorkflowEvolutionReceipt raise StorageError {
  if guard_stores.length() != config.guard_workflows.length() {
    raise ValidationFailure(field="filesystem_guard_profile_roots")
  }
  let locators : Array[String] = []
  let identities : Array[String] = []
  for guard_store in guard_stores {
    if guard_store.workspace_root != self.workspace_root ||
      guard_store.storage_root == self.storage_root {
      raise GuardedBindingConflict(
        workflow_id=mutation_workflow.id(),
        field="guard_root_independence",
      )
    }
    locators.push(guard_store.storage_root)
    identities.push(guard_store.root_identity)
  }
  let primary = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    true,
  )
  let related : Array[NativeStorageSession] = []
  try {
    let state = load_native_state(primary)
    let declared = state.registry_declarations.map(value => value.binding)
    guard latest_guarded_binding(declared, mutation_workflow) is Some(prior) else {
      raise GuardedRegistryMissing(
        name=guarded_registry_declaration_name(mutation_workflow),
      )
    }
    if prior_receipt.binding.registry_digest != prior.registry_digest ||
      prior_receipt.binding.canonical != prior.canonical {
      raise GuardedBindingConflict(
        workflow_id=mutation_workflow.id(),
        field="evolution_prior_binding",
      )
    }
    require_binding_activation_prefix(
      prior,
      replay_from_state(state.batches, state.checkpoints, mutation_workflow),
    )
    for index, workflow in config.guard_workflows {
      let session = open_related_native_session(primary, locators[index])
      related.push(session)
      if native_session_root_identity(session) != identities[index] {
        raise GuardedBindingConflict(
          workflow_id=mutation_workflow.id(),
          field="guard_root_identity",
        )
      }
      let guard_state = load_native_state(session)
      ignore(
        replay_from_state(
          guard_state.batches,
          guard_state.checkpoints,
          workflow,
        ),
      )
    }
    let added = new_guard_profile(
      config, mutation_workflow, locators, identities,
    )
    let current = evolve_guarded_workflow_binding(prior, added)
    native_atomic_store_named(
      primary,
      guarded_registry_binding_name(current),
      guarded_registry_declaration_bytes(current),
    )
    native_atomic_store_named(
      primary,
      guarded_binding_marker_name(current),
      current.canonical,
    )
    for session in related {
      native_close(session)
    }
    native_close(primary)
    make_guarded_evolution_receipt(prior, current, added)
  } catch {
    error => {
      for session in related {
        native_close(session)
      }
      native_close(primary)
      raise error
    }
  }
}

///|
pub fn FileSystemStore::registered_guard_profiles(
  self : FileSystemStore,
  mutation_workflow : @contracts.RecordRef,
) -> ReadOnlyArray[GuardProfile] raise StorageError {
  let session = acquire_native_session(
    self.workspace_root,
    self.storage_root,
    true,
  )
  try {
    let state = load_native_state(session)
    guard state.registered_binding(self, mutation_workflow) is Some(binding) else {
      raise GuardedRegistryMissing(
        name=guarded_registry_declaration_name(mutation_workflow),
      )
    }
    native_close(session)
    binding.profiles
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
/// Cross-root guarded storage capability. Production work and governance roots
/// must share this exact canonical workspace so one process-safe global lock
/// can cover guard verification and mutation publication.
pub struct FileSystemGuardedStore {
  mutation : FileSystemStore
  guard_roots : ReadOnlyArray[String]
  guard_root_identities : ReadOnlyArray[String]
  expected_binding : GuardedWorkflowBinding?
  selected_profile_id : String?
}

///|
pub fn FileSystemGuardedStore::new(
  mutation : FileSystemStore,
  guard_stores : Array[FileSystemStore],
) -> FileSystemGuardedStore raise StorageError {
  if guard_stores.is_empty() {
    raise ValidationFailure(field="filesystem_guard_stores")
  }
  let roots : Array[String] = []
  let identities : Array[String] = []
  for index, value in guard_stores {
    if value.workspace_root != mutation.workspace_root {
      raise ValidationFailure(field="filesystem_guard_workspace")
    }
    if value.storage_root == mutation.storage_root {
      raise ValidationFailure(field="filesystem_guard_distinct_root")
    }
    for prior in 0..<index {
      if roots[prior] == value.storage_root {
        raise ValidationFailure(field="filesystem_guard_duplicate_root")
      }
    }
    roots.push(value.storage_root)
    identities.push(value.root_identity)
  }
  {
    mutation,
    guard_roots: ReadOnlyArray::from_array(roots),
    guard_root_identities: ReadOnlyArray::from_array(identities),
    expected_binding: None,
    selected_profile_id: None,
  }
}

///|
fn FileSystemGuardedStore::resolve_registered_profile(
  self : FileSystemGuardedStore,
  state : NativeState,
  binding : GuardedWorkflowBinding,
  request : GuardedCommitRequest,
) -> GuardProfile raise StorageError {
  let profile = match self.selected_profile_id {
    Some(profile_id) =>
      match find_guard_profile(binding, profile_id) {
        Some(profile) => profile
        None =>
          raise GuardedBindingConflict(
            workflow_id=request.mutation.workflow.id(),
            field="selected_guard_profile",
          )
      }
    None =>
      match guarded_request_matching_profile(request, binding) {
        Some(profile) => profile
        None =>
          raise GuardedBindingConflict(
            workflow_id=request.mutation.workflow.id(),
            field="guard_set",
          )
      }
  }
  if !guarded_request_matches_profile(request, binding, profile) ||
    profile.guard_root_locators != self.guard_roots ||
    profile.guard_root_identities != self.guard_root_identities {
    raise GuardedBindingConflict(
      workflow_id=request.mutation.workflow.id(),
      field="guard_set",
    )
  }
  match self.expected_binding {
    Some(expected) => {
      let bindings = state.registry_declarations.map(value => value.binding)
      if !binding_descends_from(bindings, expected, binding) {
        raise GuardedBindingConflict(
          workflow_id=request.mutation.workflow.id(),
          field="activation_receipt_binding",
        )
      }
    }
    None => ()
  }
  profile
}

///|
pub fn FileSystemGuardedStore::mutation_store(
  self : FileSystemGuardedStore,
) -> FileSystemStore {
  self.mutation
}

///|
pub fn FileSystemGuardedStore::commit(
  self : FileSystemGuardedStore,
  request : CommitRequest,
) -> CommitResult raise StorageError {
  self.mutation.commit(request)
}

///|
pub fn FileSystemGuardedStore::replay(
  self : FileSystemGuardedStore,
  workflow : @contracts.RecordRef,
) -> ReplayResult raise StorageError {
  self.mutation.replay(workflow)
}

///|
pub fn FileSystemGuardedStore::write_checkpoint(
  self : FileSystemGuardedStore,
  checkpoint : CheckpointRecord,
) -> Unit raise StorageError {
  self.mutation.write_checkpoint(checkpoint)
}

///|
pub fn FileSystemGuardedStore::read_checkpoint(
  self : FileSystemGuardedStore,
  workflow : @contracts.RecordRef,
) -> CheckpointRecord? raise StorageError {
  self.mutation.read_checkpoint(workflow)
}

///|
pub fn FileSystemGuardedStore::head(
  self : FileSystemGuardedStore,
  workflow : @contracts.RecordRef,
) -> WorkflowHead raise StorageError {
  self.mutation.head(workflow)
}

///|
pub fn FileSystemGuardedStore::events(
  self : FileSystemGuardedStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[WorkflowEvent] raise StorageError {
  self.mutation.events(workflow)
}

///|
pub fn FileSystemGuardedStore::intents(
  self : FileSystemGuardedStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[OutboxIntent] raise StorageError {
  self.mutation.intents(workflow)
}

///|
pub fn FileSystemGuardedStore::guarded_commit(
  self : FileSystemGuardedStore,
  request : GuardedCommitRequest,
) -> GuardedCommitOutcome raise StorageError {
  if request.guards.length() != self.guard_roots.length() {
    raise ValidationFailure(field="guarded_commit_guard_store_count")
  }
  let primary = acquire_native_session(
    self.mutation.workspace_root,
    self.mutation.storage_root,
    true,
  )
  let related : Array[NativeStorageSession] = []
  try {
    let mutation_state = load_native_state(primary)
    let registered = mutation_state.registered_binding(
      self.mutation,
      request.mutation.workflow,
    )
    let selected_roots = match registered {
      Some(binding) => {
        let profile = self.resolve_registered_profile(
          mutation_state, binding, request,
        )
        require_binding_activation_prefix(
          binding,
          replay_from_state(
            mutation_state.batches,
            mutation_state.checkpoints,
            request.mutation.workflow,
          ),
        )
        profile.guard_root_locators
      }
      None => {
        if self.expected_binding is Some(_) {
          raise GuardedRegistryMissing(
            name=guarded_registry_declaration_name(request.mutation.workflow),
          )
        }
        self.guard_roots
      }
    }
    let guard_replays : Array[ReplayResult] = []
    for index, head_guard in request.guards {
      let session = open_related_native_session(primary, selected_roots[index])
      related.push(session)
      match registered {
        Some(_) =>
          if native_session_root_identity(session) !=
            self.guard_root_identities[index] {
            raise GuardedBindingConflict(
              workflow_id=request.mutation.workflow.id(),
              field="guard_root_identity",
            )
          }
        None => ()
      }
      let state = load_native_state(session)
      guard_replays.push(
        replay_from_state(state.batches, state.checkpoints, head_guard.workflow),
      )
    }
    let outcome = match
      prepare_guarded_commit(mutation_state.batches, guard_replays, request) {
      (Some(existing), None, None) => GuardedCommitSucceeded(existing.result)
      (None, Some(batch), None) => {
        native_atomic_store_named(
          primary,
          batch_file_name(batch),
          encode_batch(batch),
        )
        GuardedCommitSucceeded(batch.result)
      }
      (None, None, Some(receipt)) => GuardedCommitRejected(receipt)
      _ => raise ValidationFailure(field="guarded_commit_classification")
    }
    for session in related {
      native_close(session)
    }
    native_close(primary)
    outcome
  } catch {
    error => {
      for session in related {
        native_close(session)
      }
      native_close(primary)
      raise error
    }
  }
}

///|
/// Recovery-aware variant of the same workspace-global guarded transaction.
/// It preserves the existing method and only exposes publication freshness.
fn FileSystemGuardedStore::classified_guarded_commit(
  self : FileSystemGuardedStore,
  request : GuardedCommitRequest,
) -> ClassifiedGuardedCommitOutcome raise StorageError {
  if request.guards.length() != self.guard_roots.length() {
    raise ValidationFailure(field="guarded_commit_guard_store_count")
  }
  let primary = acquire_native_session(
    self.mutation.workspace_root,
    self.mutation.storage_root,
    true,
  )
  let related : Array[NativeStorageSession] = []
  try {
    let mutation_state = load_native_state(primary)
    let registered = mutation_state.registered_binding(
      self.mutation,
      request.mutation.workflow,
    )
    let selected_roots = match registered {
      Some(binding) => {
        let profile = self.resolve_registered_profile(
          mutation_state, binding, request,
        )
        require_binding_activation_prefix(
          binding,
          replay_from_state(
            mutation_state.batches,
            mutation_state.checkpoints,
            request.mutation.workflow,
          ),
        )
        profile.guard_root_locators
      }
      None => {
        if self.expected_binding is Some(_) {
          raise GuardedRegistryMissing(
            name=guarded_registry_declaration_name(request.mutation.workflow),
          )
        }
        self.guard_roots
      }
    }
    let guard_replays : Array[ReplayResult] = []
    for index, head_guard in request.guards {
      let session = open_related_native_session(primary, selected_roots[index])
      related.push(session)
      match registered {
        Some(_) =>
          if native_session_root_identity(session) !=
            self.guard_root_identities[index] {
            raise GuardedBindingConflict(
              workflow_id=request.mutation.workflow.id(),
              field="guard_root_identity",
            )
          }
        None => ()
      }
      let state = load_native_state(session)
      guard_replays.push(
        replay_from_state(state.batches, state.checkpoints, head_guard.workflow),
      )
    }
    let outcome = match
      prepare_guarded_commit(mutation_state.batches, guard_replays, request) {
      (Some(existing), None, None) => AlreadyCommitted(existing.result)
      (None, Some(batch), None) => {
        native_atomic_store_named(
          primary,
          batch_file_name(batch),
          encode_batch(batch),
        )
        FreshlyApplied(batch.result)
      }
      (None, None, Some(receipt)) => GuardRejected(receipt)
      _ => raise ValidationFailure(field="classified_guarded_commit")
    }
    for session in related {
      native_close(session)
    }
    native_close(primary)
    outcome
  } catch {
    error => {
      for session in related {
        native_close(session)
      }
      native_close(primary)
      raise error
    }
  }
}

///|
pub impl StoragePort for FileSystemGuardedStore with fn commit(self, request) {
  self.commit(request)
}

///|
pub impl StoragePort for FileSystemGuardedStore with fn replay(self, workflow) {
  self.replay(workflow)
}

///|
pub impl StoragePort for FileSystemGuardedStore with fn write_checkpoint(
  self,
  checkpoint,
) {
  self.write_checkpoint(checkpoint)
}

///|
pub impl StoragePort for FileSystemGuardedStore with fn read_checkpoint(
  self,
  workflow,
) {
  self.read_checkpoint(workflow)
}

///|
pub impl StoragePort for FileSystemGuardedStore with fn head(self, workflow) {
  self.head(workflow)
}

///|
pub impl StoragePort for FileSystemGuardedStore with fn events(self, workflow) {
  self.events(workflow)
}

///|
pub impl StoragePort for FileSystemGuardedStore with fn intents(self, workflow) {
  self.intents(workflow)
}

///|
pub impl GuardedStoragePort for FileSystemGuardedStore with fn guarded_commit(
  self,
  request,
) {
  self.guarded_commit(request)
}

///|
/// Official filesystem capability constructed only from an opaque current
/// activation receipt. Caller-selected guard roots never enter this type.
pub struct RegistryBoundFileSystemStore {
  guarded : FileSystemGuardedStore
}

///|
fn require_filesystem_activation_receipt(
  mutation : FileSystemStore,
  receipt : GuardedWorkflowActivationReceipt,
) -> GuardedWorkflowBinding raise StorageError {
  let expected = receipt.binding
  if expected.store_domain != "filesystem" ||
    expected.workspace_identity != mutation.workspace_root ||
    expected.mutation_root_locator != mutation.storage_root ||
    expected.mutation_root_identity != mutation.root_identity {
    raise GuardedBindingConflict(
      workflow_id=expected.mutation_workflow.id(),
      field="activation_receipt_store",
    )
  }
  let session = acquire_native_session(
    mutation.workspace_root,
    mutation.storage_root,
    true,
  )
  try {
    let state = load_native_state(session)
    guard state.registered_binding(mutation, expected.mutation_workflow)
      is Some(current) else {
      raise GuardedRegistryMissing(
        name=guarded_registry_declaration_name(expected.mutation_workflow),
      )
    }
    let bindings = state.registry_declarations.map(value => value.binding)
    if !binding_descends_from(bindings, expected, current) {
      raise GuardedBindingConflict(
        workflow_id=expected.mutation_workflow.id(),
        field="activation_receipt_binding",
      )
    }
    require_binding_activation_prefix(
      current,
      replay_from_state(
        state.batches,
        state.checkpoints,
        current.mutation_workflow,
      ),
    )
    native_close(session)
    current
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub fn RegistryBoundFileSystemStore::new(
  mutation : FileSystemStore,
  receipt : GuardedWorkflowActivationReceipt,
) -> RegistryBoundFileSystemStore raise StorageError {
  RegistryBoundFileSystemStore::new_for_profile(
    mutation,
    receipt,
    default_guard_profile_id(),
  )
}

///|
/// Selects one exact operation profile. Callers supply only the stable profile
/// id; registered workflow order and roots come exclusively from durable state.
pub fn RegistryBoundFileSystemStore::new_for_profile(
  mutation : FileSystemStore,
  receipt : GuardedWorkflowActivationReceipt,
  profile_id : String,
) -> RegistryBoundFileSystemStore raise StorageError {
  require_storage_text(profile_id, "selected_guard_profile")
  let binding = require_filesystem_activation_receipt(mutation, receipt)
  guard find_guard_profile(receipt.binding, profile_id) is Some(receipt_profile) else {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="selected_guard_profile",
    )
  }
  guard find_guard_profile(binding, profile_id) is Some(profile) else {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="selected_guard_profile",
    )
  }
  if receipt_profile.canonical != profile.canonical {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="selected_guard_profile",
    )
  }
  {
    guarded: {
      mutation,
      guard_roots: profile.guard_root_locators,
      guard_root_identities: profile.guard_root_identities,
      expected_binding: Some(binding),
      selected_profile_id: Some(profile_id),
    },
  }
}

///|
fn RegistryBoundFileSystemStore::current_binding(
  self : RegistryBoundFileSystemStore,
) -> GuardedWorkflowBinding raise StorageError {
  guard self.guarded.expected_binding is Some(expected) else {
    raise GuardedBindingConflict(
      workflow_id="unknown",
      field="activation_receipt_binding",
    )
  }
  let mutation = self.guarded.mutation
  let session = acquire_native_session(
    mutation.workspace_root,
    mutation.storage_root,
    true,
  )
  try {
    let state = load_native_state(session)
    guard state.registered_binding(mutation, expected.mutation_workflow)
      is Some(current) else {
      raise GuardedRegistryMissing(
        name=guarded_registry_declaration_name(expected.mutation_workflow),
      )
    }
    let bindings = state.registry_declarations.map(value => value.binding)
    if !binding_descends_from(bindings, expected, current) {
      raise GuardedBindingConflict(
        workflow_id=expected.mutation_workflow.id(),
        field="activation_receipt_binding",
      )
    }
    native_close(session)
    current
  } catch {
    error => {
      native_close(session)
      raise error
    }
  }
}

///|
pub fn RegistryBoundFileSystemStore::mutation_store(
  self : RegistryBoundFileSystemStore,
) -> FileSystemStore {
  self.guarded.mutation
}

///|
pub fn RegistryBoundFileSystemStore::commit(
  self : RegistryBoundFileSystemStore,
  request : CommitRequest,
) -> CommitResult raise StorageError {
  self.guarded.commit(request)
}

///|
pub fn RegistryBoundFileSystemStore::guarded_commit(
  self : RegistryBoundFileSystemStore,
  request : GuardedCommitRequest,
) -> GuardedCommitOutcome raise StorageError {
  self.guarded.guarded_commit(request)
}

///|
pub fn RegistryBoundFileSystemStore::classified_guarded_commit(
  self : RegistryBoundFileSystemStore,
  request : GuardedCommitRequest,
) -> ClassifiedGuardedCommitOutcome raise StorageError {
  self.guarded.classified_guarded_commit(request)
}

///|
pub fn RegistryBoundFileSystemStore::replay_registered_guard(
  self : RegistryBoundFileSystemStore,
  workflow : @contracts.RecordRef,
) -> ReplayResult raise StorageError {
  let binding = self.current_binding()
  guard self.guarded.selected_profile_id is Some(profile_id) else {
    raise GuardedBindingConflict(
      workflow_id=workflow.id(),
      field="activation_receipt_binding",
    )
  }
  guard find_guard_profile(binding, profile_id) is Some(profile) else {
    raise GuardedBindingConflict(
      workflow_id=workflow.id(),
      field="selected_guard_profile",
    )
  }
  guard profile.guard_workflows.search_by(value => {
      exact_record_equal(value, workflow)
    })
    is Some(index) else {
    raise GuardedBindingConflict(
      workflow_id=workflow.id(),
      field="unregistered_guard_replay",
    )
  }
  let store = FileSystemStore::open(
    self.guarded.mutation.workspace_root,
    profile.guard_root_locators[index],
  )
  if store.root_identity != profile.guard_root_identities[index] {
    raise GuardedBindingConflict(
      workflow_id=workflow.id(),
      field="guard_root_identity",
    )
  }
  store.replay(workflow)
}

///|
pub fn RegistryBoundFileSystemStore::selected_guard_profile(
  self : RegistryBoundFileSystemStore,
) -> GuardProfile raise StorageError {
  let binding = self.current_binding()
  guard self.guarded.selected_profile_id is Some(profile_id) else {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="selected_guard_profile",
    )
  }
  guard find_guard_profile(binding, profile_id) is Some(profile) else {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="selected_guard_profile",
    )
  }
  profile
}

///|
pub fn RegistryBoundFileSystemStore::registered_guard_profiles(
  self : RegistryBoundFileSystemStore,
) -> ReadOnlyArray[GuardProfile] raise StorageError {
  self.current_binding().profiles
}

///|
pub fn RegistryBoundFileSystemStore::replay(
  self : RegistryBoundFileSystemStore,
  workflow : @contracts.RecordRef,
) -> ReplayResult raise StorageError {
  self.guarded.replay(workflow)
}

///|
pub fn RegistryBoundFileSystemStore::write_checkpoint(
  self : RegistryBoundFileSystemStore,
  checkpoint : CheckpointRecord,
) -> Unit raise StorageError {
  self.guarded.write_checkpoint(checkpoint)
}

///|
pub fn RegistryBoundFileSystemStore::read_checkpoint(
  self : RegistryBoundFileSystemStore,
  workflow : @contracts.RecordRef,
) -> CheckpointRecord? raise StorageError {
  self.guarded.read_checkpoint(workflow)
}

///|
pub fn RegistryBoundFileSystemStore::head(
  self : RegistryBoundFileSystemStore,
  workflow : @contracts.RecordRef,
) -> WorkflowHead raise StorageError {
  self.guarded.head(workflow)
}

///|
pub fn RegistryBoundFileSystemStore::events(
  self : RegistryBoundFileSystemStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[WorkflowEvent] raise StorageError {
  self.guarded.events(workflow)
}

///|
pub fn RegistryBoundFileSystemStore::intents(
  self : RegistryBoundFileSystemStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[OutboxIntent] raise StorageError {
  self.guarded.intents(workflow)
}

///|
pub impl StoragePort for RegistryBoundFileSystemStore with fn commit(
  self,
  request,
) {
  self.commit(request)
}

///|
pub impl StoragePort for RegistryBoundFileSystemStore with fn replay(
  self,
  workflow,
) {
  self.replay(workflow)
}

///|
pub impl StoragePort for RegistryBoundFileSystemStore with fn write_checkpoint(
  self,
  checkpoint,
) {
  self.write_checkpoint(checkpoint)
}

///|
pub impl StoragePort for RegistryBoundFileSystemStore with fn read_checkpoint(
  self,
  workflow,
) {
  self.read_checkpoint(workflow)
}

///|
pub impl StoragePort for RegistryBoundFileSystemStore with fn head(
  self,
  workflow,
) {
  self.head(workflow)
}

///|
pub impl StoragePort for RegistryBoundFileSystemStore with fn events(
  self,
  workflow,
) {
  self.events(workflow)
}

///|
pub impl StoragePort for RegistryBoundFileSystemStore with fn intents(
  self,
  workflow,
) {
  self.intents(workflow)
}

///|
pub impl GuardedStoragePort for RegistryBoundFileSystemStore with fn guarded_commit(
  self,
  request,
) {
  self.guarded_commit(request)
}

///|
pub impl RegistryBoundGuardedStoragePort for RegistryBoundFileSystemStore with fn replay_registered_guard(
  self,
  workflow,
) {
  self.replay_registered_guard(workflow)
}

///|
pub impl RegistryBoundGuardedStoragePort for RegistryBoundFileSystemStore with fn selected_guard_profile(
  self,
) {
  self.selected_guard_profile()
}

///|
pub impl RegistryBoundGuardedStoragePort for RegistryBoundFileSystemStore with fn registered_guard_profiles(
  self,
) {
  self.registered_guard_profiles()
}

///|
pub impl ClassifiedRegistryBoundGuardedStoragePort for RegistryBoundFileSystemStore with fn classified_guarded_commit(
  self,
  request,
) {
  self.classified_guarded_commit(request)
}
