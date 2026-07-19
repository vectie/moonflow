///|
/// Portable in-memory implementation of `StoragePort`.
pub struct MemoryStore {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  store_identity : String
  batches : Array[Bytes]
  checkpoints : Array[Bytes]
  registry_declarations : Array[Bytes]
  registry_markers : Array[Bytes]
}

///|
let memory_store_identity_counter : Ref[Int64] = Ref(0L)

///|
fn next_memory_store_identity() -> String {
  memory_store_identity_counter.val += 1L
  "memory-store:\{memory_store_identity_counter.val}"
}

///|
pub fn MemoryStore::new() -> MemoryStore {
  {
    record_version: try! storage_version("1.0.0", "memory_store"),
    schema_version: try! storage_version("1.0.0", "memory_store_schema"),
    store_identity: next_memory_store_identity(),
    batches: [],
    checkpoints: [],
    registry_declarations: [],
    registry_markers: [],
  }
}

///|
fn MemoryStore::registry_bindings(
  self : MemoryStore,
) -> Array[GuardedWorkflowBinding] raise StorageError {
  let values : Array[GuardedWorkflowBinding] = []
  for index, bytes in self.registry_declarations {
    let binding = decode_guarded_registry_declaration(bytes) catch {
      _ =>
        raise GuardedRegistryCorrupt(
          name="memory-registry-declaration-\{index}",
        )
    }
    values.push(binding)
  }
  values
}

///|
fn MemoryStore::require_binding_marker(
  self : MemoryStore,
  binding : GuardedWorkflowBinding,
) -> Unit raise StorageError {
  let expected = guarded_binding_marker_name(binding)
  for index, bytes in self.registry_markers {
    let marker = decode_guarded_workflow_binding(bytes) catch {
      _ => raise GuardedRegistryCorrupt(name="memory-registry-marker-\{index}")
    }
    if marker.registry_digest == binding.registry_digest {
      if marker.canonical != binding.canonical {
        raise GuardedRegistryCorrupt(name=expected)
      }
      return
    }
  }
  raise GuardedRegistryMissing(name=expected)
}

///|
fn MemoryStore::registered_binding(
  self : MemoryStore,
  workflow : @contracts.RecordRef,
) -> GuardedWorkflowBinding? raise StorageError {
  let bindings = self.registry_bindings()
  for binding in bindings {
    self.require_binding_marker(binding)
  }
  guard latest_guarded_binding(bindings, workflow) is Some(binding) else {
    return None
  }
  if binding.store_domain != "memory" ||
    binding.workspace_identity != self.store_identity ||
    binding.mutation_root_locator != self.store_identity ||
    binding.mutation_root_identity != self.store_identity {
    raise GuardedBindingConflict(
      workflow_id=workflow.id(),
      field="memory_store_identity",
    )
  }
  Some(binding)
}

///|
fn memory_profile_roots(
  store_identity : String,
  configs : ArrayView[GuardProfileConfig],
) -> Array[Array[String]] {
  [
    for config in configs => {
      [
        for _ in config.guard_workflows => store_identity
      ]
    }
  ]
}

///|
/// Registers multiple exact operation profiles in one initial registry
/// generation. Later additions must use `add_guard_profile`.
pub fn MemoryStore::activate_guarded_workflow_profiles(
  self : MemoryStore,
  mutation_workflow : @contracts.RecordRef,
  configs : Array[GuardProfileConfig],
) -> GuardedWorkflowActivationReceipt raise StorageError {
  if configs.is_empty() {
    raise ValidationFailure(field="memory_guard_profiles")
  }
  let roots = memory_profile_roots(self.store_identity, configs)
  let existing = self.registry_bindings()
  match latest_guarded_binding(existing, mutation_workflow) {
    Some(binding) => {
      if binding.store_domain != "memory" ||
        binding.workspace_identity != self.store_identity ||
        binding.mutation_root_locator != self.store_identity ||
        binding.mutation_root_identity != self.store_identity ||
        !profiles_configuration_matches(binding, configs, roots, roots) {
        raise GuardedBindingConflict(
          workflow_id=mutation_workflow.id(),
          field="binding_configuration",
        )
      }
      let replay = self.replay(mutation_workflow)
      require_binding_activation_prefix(binding, replay)
      self.require_binding_marker(binding) catch {
        GuardedRegistryMissing(_) =>
          self.registry_markers.push(binding.canonical)
        error => raise error
      }
      make_guarded_activation_receipt(binding)
    }
    None => {
      let profiles : Array[GuardProfile] = []
      for index, config in configs {
        profiles.push(
          new_guard_profile(
            config,
            mutation_workflow,
            roots[index],
            roots[index],
          ),
        )
      }
      let replay = self.replay(mutation_workflow)
      let binding = new_guarded_workflow_binding_profiles(
        "memory",
        self.store_identity,
        self.store_identity,
        self.store_identity,
        mutation_workflow,
        profiles,
        replay,
      )
      self.registry_declarations.push(
        guarded_registry_declaration_bytes(binding),
      )
      self.registry_markers.push(binding.canonical)
      make_guarded_activation_receipt(binding)
    }
  }
}

///|
/// Trusted in-memory activation. Copies of this `MemoryStore` share the same
/// backing arrays and immutable registry identity.
pub fn MemoryStore::activate_guarded_workflow(
  self : MemoryStore,
  mutation_workflow : @contracts.RecordRef,
  guard_workflows : Array[@contracts.RecordRef],
) -> GuardedWorkflowActivationReceipt raise StorageError {
  let config = GuardProfileConfig::new(
    default_guard_profile_id(),
    default_guard_profile_name(),
    guard_workflows,
  )
  let roots = [ for _ in config.guard_workflows => self.store_identity ]
  let bindings = self.registry_bindings()
  match latest_guarded_binding(bindings, mutation_workflow) {
    Some(binding) => {
      guard find_guard_profile(binding, default_guard_profile_id())
        is Some(profile) else {
        raise GuardedBindingConflict(
          workflow_id=mutation_workflow.id(),
          field="default_guard_profile",
        )
      }
      if binding.store_domain != "memory" ||
        binding.workspace_identity != self.store_identity ||
        !profile_configuration_matches(profile, config, roots, roots) {
        raise GuardedBindingConflict(
          workflow_id=mutation_workflow.id(),
          field="binding_configuration",
        )
      }
      require_binding_activation_prefix(binding, self.replay(mutation_workflow))
      self.require_binding_marker(binding) catch {
        GuardedRegistryMissing(_) =>
          self.registry_markers.push(binding.canonical)
        error => raise error
      }
      make_guarded_activation_receipt(binding)
    }
    None => self.activate_guarded_workflow_profiles(mutation_workflow, [config])
  }
}

///|
/// Monotonically appends one exact profile. The supplied receipt must name the
/// current binding; stale concurrent evolutions cannot fork the registry.
pub fn MemoryStore::add_guard_profile(
  self : MemoryStore,
  mutation_workflow : @contracts.RecordRef,
  prior_receipt : GuardedWorkflowActivationReceipt,
  config : GuardProfileConfig,
) -> GuardedWorkflowEvolutionReceipt raise StorageError {
  let bindings = self.registry_bindings()
  guard latest_guarded_binding(bindings, mutation_workflow) is Some(prior) else {
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
  require_binding_activation_prefix(prior, self.replay(mutation_workflow))
  let roots = [ for _ in config.guard_workflows => self.store_identity ]
  let added = new_guard_profile(config, mutation_workflow, roots, roots)
  let current = evolve_guarded_workflow_binding(prior, added)
  self.registry_declarations.push(guarded_registry_declaration_bytes(current))
  self.registry_markers.push(current.canonical)
  make_guarded_evolution_receipt(prior, current, added)
}

///|
pub fn MemoryStore::registered_guard_profiles(
  self : MemoryStore,
  mutation_workflow : @contracts.RecordRef,
) -> ReadOnlyArray[GuardProfile] raise StorageError {
  guard self.registered_binding(mutation_workflow) is Some(binding) else {
    raise GuardedRegistryMissing(
      name=guarded_registry_declaration_name(mutation_workflow),
    )
  }
  binding.profiles
}

///|
pub fn MemoryStore::record_version(self : MemoryStore) -> @contracts.Version {
  self.record_version
}

///|
pub fn MemoryStore::schema_version(self : MemoryStore) -> @contracts.Version {
  self.schema_version
}

///|
pub fn MemoryStore::commit(
  self : MemoryStore,
  request : CommitRequest,
) -> CommitResult raise StorageError {
  match self.registered_binding(request.workflow) {
    Some(binding) =>
      raise GuardedCommitRequired(
        workflow_id=request.workflow.id(),
        key=request.command_idempotency_key,
        binding_digest=binding.registry_digest.text(),
      )
    None => ()
  }
  let batches = self.batches.map(bytes => decode_batch(bytes))
  match prepare_commit(batches, request) {
    (Some(existing), None) => existing.result
    (None, Some(batch)) => {
      self.batches.push(encode_batch(batch))
      batch.result
    }
    _ => raise ValidationFailure(field="commit_classification")
  }
}

///|
/// Atomic guarded commit over workflows held by this same MemoryStore. Passing
/// replays from a second store is impossible: every guard is re-derived from
/// this store's single backing batch array inside this call.
pub fn MemoryStore::guarded_commit(
  self : MemoryStore,
  request : GuardedCommitRequest,
) -> GuardedCommitOutcome raise StorageError {
  match self.registered_binding(request.mutation.workflow) {
    Some(binding) => {
      if !guarded_request_matches_binding(request, binding) {
        raise GuardedBindingConflict(
          workflow_id=request.mutation.workflow.id(),
          field="guard_set",
        )
      }
      require_binding_activation_prefix(
        binding,
        self.replay(request.mutation.workflow),
      )
    }
    None => ()
  }
  let batches = self.batches.map(bytes => decode_batch(bytes))
  let guard_replays = [
    for head_guard in request.guards => {
      replay_from_state(
        batches,
        self.checkpoints.map(bytes => decode_checkpoint(bytes)),
        head_guard.workflow,
      )
    }
  ]
  match prepare_guarded_commit(batches, guard_replays, request) {
    (Some(existing), None, None) => GuardedCommitSucceeded(existing.result)
    (None, Some(batch), None) => {
      self.batches.push(encode_batch(batch))
      GuardedCommitSucceeded(batch.result)
    }
    (None, None, Some(receipt)) => GuardedCommitRejected(receipt)
    _ => raise ValidationFailure(field="guarded_commit_classification")
  }
}

///|
pub fn MemoryStore::replay(
  self : MemoryStore,
  workflow : @contracts.RecordRef,
) -> ReplayResult raise StorageError {
  replay_from_state(
    self.batches.map(bytes => decode_batch(bytes)),
    self.checkpoints.map(bytes => decode_checkpoint(bytes)),
    workflow,
  )
}

///|
pub fn MemoryStore::write_checkpoint(
  self : MemoryStore,
  checkpoint : CheckpointRecord,
) -> Unit raise StorageError {
  let batches = self.batches.map(bytes => decode_batch(bytes))
  let checkpoints = self.checkpoints.map(bytes => decode_checkpoint(bytes))
  let events = events_from_batches(batches, checkpoint.workflow)
  if !checkpoint_is_valid(checkpoint, checkpoint.workflow, events) {
    raise ValidationFailure(field="checkpoint_boundary")
  }
  for existing in checkpoints {
    if record_identity_equal(existing.checkpoint_ref, checkpoint.checkpoint_ref) {
      if existing == checkpoint {
        return
      }
      raise IdentityConflict(
        kind=checkpoint.checkpoint_ref.kind(),
        id=checkpoint.checkpoint_ref.id(),
        version=checkpoint.checkpoint_ref.version().text(),
      )
    }
  }
  self.checkpoints.push(checkpoint.canonical_bytes())
}

///|
pub fn MemoryStore::read_checkpoint(
  self : MemoryStore,
  workflow : @contracts.RecordRef,
) -> CheckpointRecord? raise StorageError {
  latest_valid_checkpoint(
    self.checkpoints.map(bytes => decode_checkpoint(bytes)),
    workflow,
    events_from_batches(
      self.batches.map(bytes => decode_batch(bytes)),
      workflow,
    ),
  )
}

///|
pub fn MemoryStore::head(
  self : MemoryStore,
  workflow : @contracts.RecordRef,
) -> WorkflowHead raise StorageError {
  head_from_batches(self.batches.map(bytes => decode_batch(bytes)), workflow)
}

///|
pub fn MemoryStore::events(
  self : MemoryStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[WorkflowEvent] raise StorageError {
  ReadOnlyArray::from_array(
    events_from_batches(
      self.batches.map(bytes => decode_batch(bytes)),
      workflow,
    ),
  )
}

///|
pub fn MemoryStore::intents(
  self : MemoryStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[OutboxIntent] raise StorageError {
  ReadOnlyArray::from_array(
    intents_from_batches(
      self.batches.map(bytes => decode_batch(bytes)),
      workflow,
    ),
  )
}

///|
pub impl StoragePort for MemoryStore with fn commit(self, request) {
  self.commit(request)
}

///|
pub impl StoragePort for MemoryStore with fn replay(self, workflow) {
  self.replay(workflow)
}

///|
pub impl StoragePort for MemoryStore with fn write_checkpoint(self, checkpoint) {
  self.write_checkpoint(checkpoint)
}

///|
pub impl StoragePort for MemoryStore with fn read_checkpoint(self, workflow) {
  self.read_checkpoint(workflow)
}

///|
pub impl StoragePort for MemoryStore with fn head(self, workflow) {
  self.head(workflow)
}

///|
pub impl StoragePort for MemoryStore with fn events(self, workflow) {
  self.events(workflow)
}

///|
pub impl StoragePort for MemoryStore with fn intents(self, workflow) {
  self.intents(workflow)
}

///|
pub impl GuardedStoragePort for MemoryStore with fn guarded_commit(
  self,
  request,
) {
  self.guarded_commit(request)
}

///|
/// Official registry-bound in-memory capability. It can only be constructed
/// from a current opaque activation receipt for this exact shared backing.
pub struct GuardedMemoryStore {
  store : MemoryStore
  receipt : GuardedWorkflowActivationReceipt
  selected_profile_id : String
}

///|
fn require_memory_activation_receipt(
  store : MemoryStore,
  receipt : GuardedWorkflowActivationReceipt,
) -> GuardedWorkflowBinding raise StorageError {
  let binding = receipt.binding
  if binding.store_domain != "memory" ||
    binding.workspace_identity != store.store_identity ||
    binding.mutation_root_identity != store.store_identity {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="activation_receipt_store",
    )
  }
  guard store.registered_binding(binding.mutation_workflow) is Some(current) else {
    raise GuardedRegistryMissing(name=guarded_binding_marker_name(binding))
  }
  let bindings = store.registry_bindings()
  if !binding_descends_from(bindings, binding, current) {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="activation_receipt_binding",
    )
  }
  require_binding_activation_prefix(
    current,
    store.replay(current.mutation_workflow),
  )
  current
}

///|
pub fn GuardedMemoryStore::new(
  store : MemoryStore,
  receipt : GuardedWorkflowActivationReceipt,
) -> GuardedMemoryStore raise StorageError {
  GuardedMemoryStore::new_for_profile(
    store,
    receipt,
    default_guard_profile_id(),
  )
}

///|
/// Constructs an operation-specific capability bound to one exact registered
/// profile. The profile identity is re-resolved against the latest append-only
/// registry generation on every mutation.
pub fn GuardedMemoryStore::new_for_profile(
  store : MemoryStore,
  receipt : GuardedWorkflowActivationReceipt,
  profile_id : String,
) -> GuardedMemoryStore raise StorageError {
  require_storage_text(profile_id, "selected_guard_profile")
  let binding = require_memory_activation_receipt(store, receipt)
  guard find_guard_profile(receipt.binding, profile_id) is Some(receipt_profile) else {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="selected_guard_profile",
    )
  }
  guard find_guard_profile(binding, profile_id) is Some(current_profile) else {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="selected_guard_profile",
    )
  }
  if receipt_profile.canonical != current_profile.canonical {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="selected_guard_profile",
    )
  }
  { store, receipt, selected_profile_id: profile_id }
}

///|
fn GuardedMemoryStore::selected_profile(
  self : GuardedMemoryStore,
) -> GuardProfile raise StorageError {
  let binding = require_memory_activation_receipt(self.store, self.receipt)
  guard find_guard_profile(binding, self.selected_profile_id) is Some(profile) else {
    raise GuardedBindingConflict(
      workflow_id=binding.mutation_workflow.id(),
      field="selected_guard_profile",
    )
  }
  profile
}

///|
pub fn GuardedMemoryStore::mutation_store(
  self : GuardedMemoryStore,
) -> MemoryStore {
  self.store
}

///|
pub fn GuardedMemoryStore::commit(
  self : GuardedMemoryStore,
  request : CommitRequest,
) -> CommitResult raise StorageError {
  self.store.commit(request)
}

///|
pub fn GuardedMemoryStore::guarded_commit(
  self : GuardedMemoryStore,
  request : GuardedCommitRequest,
) -> GuardedCommitOutcome raise StorageError {
  let binding = require_memory_activation_receipt(self.store, self.receipt)
  let profile = self.selected_profile()
  if !guarded_request_matches_profile(request, binding, profile) {
    raise GuardedBindingConflict(
      workflow_id=request.mutation.workflow.id(),
      field="guard_set",
    )
  }
  self.store.guarded_commit(request)
}

///|
pub fn GuardedMemoryStore::classified_guarded_commit(
  self : GuardedMemoryStore,
  request : GuardedCommitRequest,
) -> ClassifiedGuardedCommitOutcome raise StorageError {
  let binding = require_memory_activation_receipt(self.store, self.receipt)
  let profile = self.selected_profile()
  if !guarded_request_matches_profile(request, binding, profile) {
    raise GuardedBindingConflict(
      workflow_id=request.mutation.workflow.id(),
      field="guard_set",
    )
  }
  require_binding_activation_prefix(
    binding,
    self.store.replay(request.mutation.workflow),
  )
  let batches = self.store.batches.map(bytes => decode_batch(bytes))
  let guard_replays = [
    for head_guard in request.guards => {
      replay_from_state(
        batches,
        self.store.checkpoints.map(bytes => decode_checkpoint(bytes)),
        head_guard.workflow,
      )
    }
  ]
  match prepare_guarded_commit(batches, guard_replays, request) {
    (Some(existing), None, None) => AlreadyCommitted(existing.result)
    (None, Some(batch), None) => {
      self.store.batches.push(encode_batch(batch))
      FreshlyApplied(batch.result)
    }
    (None, None, Some(receipt)) => GuardRejected(receipt)
    _ => raise ValidationFailure(field="classified_guarded_commit")
  }
}

///|
pub fn GuardedMemoryStore::replay_registered_guard(
  self : GuardedMemoryStore,
  workflow : @contracts.RecordRef,
) -> ReplayResult raise StorageError {
  let profile = self.selected_profile()
  if !profile.guard_workflows.any(value => exact_record_equal(value, workflow)) {
    raise GuardedBindingConflict(
      workflow_id=workflow.id(),
      field="unregistered_guard_replay",
    )
  }
  self.store.replay(workflow)
}

///|
pub fn GuardedMemoryStore::selected_guard_profile(
  self : GuardedMemoryStore,
) -> GuardProfile raise StorageError {
  self.selected_profile()
}

///|
pub fn GuardedMemoryStore::registered_guard_profiles(
  self : GuardedMemoryStore,
) -> ReadOnlyArray[GuardProfile] raise StorageError {
  require_memory_activation_receipt(self.store, self.receipt).profiles
}

///|
pub fn GuardedMemoryStore::replay(
  self : GuardedMemoryStore,
  workflow : @contracts.RecordRef,
) -> ReplayResult raise StorageError {
  self.store.replay(workflow)
}

///|
pub fn GuardedMemoryStore::write_checkpoint(
  self : GuardedMemoryStore,
  checkpoint : CheckpointRecord,
) -> Unit raise StorageError {
  self.store.write_checkpoint(checkpoint)
}

///|
pub fn GuardedMemoryStore::read_checkpoint(
  self : GuardedMemoryStore,
  workflow : @contracts.RecordRef,
) -> CheckpointRecord? raise StorageError {
  self.store.read_checkpoint(workflow)
}

///|
pub fn GuardedMemoryStore::head(
  self : GuardedMemoryStore,
  workflow : @contracts.RecordRef,
) -> WorkflowHead raise StorageError {
  self.store.head(workflow)
}

///|
pub fn GuardedMemoryStore::events(
  self : GuardedMemoryStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[WorkflowEvent] raise StorageError {
  self.store.events(workflow)
}

///|
pub fn GuardedMemoryStore::intents(
  self : GuardedMemoryStore,
  workflow : @contracts.RecordRef,
) -> ReadOnlyArray[OutboxIntent] raise StorageError {
  self.store.intents(workflow)
}

///|
pub impl StoragePort for GuardedMemoryStore with fn commit(self, request) {
  self.commit(request)
}

///|
pub impl StoragePort for GuardedMemoryStore with fn replay(self, workflow) {
  self.replay(workflow)
}

///|
pub impl StoragePort for GuardedMemoryStore with fn write_checkpoint(
  self,
  checkpoint,
) {
  self.write_checkpoint(checkpoint)
}

///|
pub impl StoragePort for GuardedMemoryStore with fn read_checkpoint(
  self,
  workflow,
) {
  self.read_checkpoint(workflow)
}

///|
pub impl StoragePort for GuardedMemoryStore with fn head(self, workflow) {
  self.head(workflow)
}

///|
pub impl StoragePort for GuardedMemoryStore with fn events(self, workflow) {
  self.events(workflow)
}

///|
pub impl StoragePort for GuardedMemoryStore with fn intents(self, workflow) {
  self.intents(workflow)
}

///|
pub impl GuardedStoragePort for GuardedMemoryStore with fn guarded_commit(
  self,
  request,
) {
  self.guarded_commit(request)
}

///|
pub impl RegistryBoundGuardedStoragePort for GuardedMemoryStore with fn replay_registered_guard(
  self,
  workflow,
) {
  self.replay_registered_guard(workflow)
}

///|
pub impl RegistryBoundGuardedStoragePort for GuardedMemoryStore with fn selected_guard_profile(
  self,
) {
  self.selected_guard_profile()
}

///|
pub impl RegistryBoundGuardedStoragePort for GuardedMemoryStore with fn registered_guard_profiles(
  self,
) {
  self.registered_guard_profiles()
}

///|
pub impl ClassifiedRegistryBoundGuardedStoragePort for GuardedMemoryStore with fn classified_guarded_commit(
  self,
  request,
) {
  self.classified_guarded_commit(request)
}
