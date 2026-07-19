///|
let guarded_workflow_binding_v1_magic : Bytes = b"MF4AGWB1"

///|
let guarded_workflow_binding_magic : Bytes = b"MF4AGWB2"

///|
let guarded_guard_profile_config_magic : Bytes = b"MF4AGPC1"

///|
let guarded_guard_profile_magic : Bytes = b"MF4AGGP1"

///|
let guarded_registry_declaration_v1_magic : Bytes = b"MF4AGRD2"

///|
let guarded_registry_declaration_magic : Bytes = b"MF4AGRD3"

///|
let guarded_activation_receipt_magic : Bytes = b"MF4AGAR2"

///|
let guarded_evolution_receipt_magic : Bytes = b"MF4AGER1"

///|
let guarded_registry_version_text : String = "1.0.0"

///|
let guarded_default_profile_id_text : String = "default"

///|
let guarded_default_profile_name_text : String = "default"

///|
let guarded_registry_declaration_prefix : String = "guarded-registry-"

///|
let guarded_registry_declaration_suffix : String = ".mfgr"

///|
let guarded_binding_marker_prefix : String = "guarded-binding-"

///|
let guarded_binding_marker_suffix : String = ".mfgb"

///|
pub fn default_guard_profile_id() -> String {
  guarded_default_profile_id_text
}

///|
pub fn default_guard_profile_name() -> String {
  guarded_default_profile_name_text
}

///|
/// Opaque, authority-free host configuration for one exact guard profile.
/// Guard order is part of the profile identity and duplicate workflows are
/// rejected before any registry mutation is attempted.
pub struct GuardProfileConfig {
  profile_id : String
  profile_name : String
  guard_workflows : ReadOnlyArray[@contracts.RecordRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn GuardProfileConfig::new(
  profile_id : String,
  profile_name : String,
  guard_workflows : Array[@contracts.RecordRef],
) -> GuardProfileConfig raise StorageError {
  require_storage_text(profile_id, "guard_profile_id")
  require_storage_text(profile_name, "guard_profile_name")
  if guard_workflows.is_empty() {
    raise ValidationFailure(field="guard_profile_workflows")
  }
  for index, workflow in guard_workflows {
    for prior in 0..<index {
      if exact_record_equal(guard_workflows[prior], workflow) {
        raise ValidationFailure(field="guard_profile_duplicate_workflow")
      }
    }
  }
  let writer = StorageWriter::new()
  writer.write_bytes(guarded_guard_profile_config_magic)
  writer.write_string(guarded_registry_version_text)
  writer.write_string(profile_id)
  writer.write_string(profile_name)
  writer.write_count(guard_workflows.length())
  for workflow in guard_workflows {
    writer.write_bytes(encode_record_ref(workflow, false))
  }
  let canonical = writer.finish()
  {
    profile_id,
    profile_name,
    guard_workflows: ReadOnlyArray::from_array(guard_workflows.copy()),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn GuardProfileConfig::profile_id(self : GuardProfileConfig) -> String {
  self.profile_id
}

///|
pub fn GuardProfileConfig::profile_name(self : GuardProfileConfig) -> String {
  self.profile_name
}

///|
pub fn GuardProfileConfig::guard_workflows(
  self : GuardProfileConfig,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.guard_workflows
}

///|
pub fn GuardProfileConfig::canonical_bytes(self : GuardProfileConfig) -> Bytes {
  self.canonical
}

///|
pub fn GuardProfileConfig::digest(
  self : GuardProfileConfig,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Opaque registered profile. It binds a stable operation/profile identity to
/// one ordered set of workflows and their exact storage roots.
pub struct GuardProfile {
  profile_id : String
  profile_name : String
  guard_root_locators : ReadOnlyArray[String]
  guard_root_identities : ReadOnlyArray[String]
  guard_workflows : ReadOnlyArray[@contracts.RecordRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn guard_profile_signing_bytes(
  profile_id : String,
  profile_name : String,
  guard_root_locators : Array[String],
  guard_root_identities : Array[String],
  guard_workflows : Array[@contracts.RecordRef],
) -> Bytes raise StorageError {
  let writer = StorageWriter::new()
  writer.write_bytes(guarded_guard_profile_magic)
  writer.write_string(guarded_registry_version_text)
  writer.write_string(profile_id)
  writer.write_string(profile_name)
  writer.write_count(guard_workflows.length())
  for index, workflow in guard_workflows {
    writer.write_string(guard_root_locators[index])
    writer.write_string(guard_root_identities[index])
    writer.write_bytes(encode_record_ref(workflow, false))
  }
  writer.finish()
}

///|
fn new_guard_profile(
  config : GuardProfileConfig,
  mutation_workflow : @contracts.RecordRef,
  guard_root_locators : Array[String],
  guard_root_identities : Array[String],
) -> GuardProfile raise StorageError {
  if guard_root_locators.length() != config.guard_workflows.length() ||
    guard_root_identities.length() != config.guard_workflows.length() {
    raise ValidationFailure(field="guard_profile_roots")
  }
  let guard_workflows = [ for workflow in config.guard_workflows => workflow ]
  for index, workflow in guard_workflows {
    require_storage_text(guard_root_locators[index], "guard_profile_locator")
    require_storage_text(guard_root_identities[index], "guard_profile_root")
    if exact_record_equal(workflow, mutation_workflow) {
      raise ValidationFailure(field="guard_profile_independent_workflow")
    }
  }
  let canonical = guard_profile_signing_bytes(
    config.profile_id,
    config.profile_name,
    guard_root_locators,
    guard_root_identities,
    guard_workflows,
  )
  {
    profile_id: config.profile_id,
    profile_name: config.profile_name,
    guard_root_locators: ReadOnlyArray::from_array(guard_root_locators.copy()),
    guard_root_identities: ReadOnlyArray::from_array(
      guard_root_identities.copy(),
    ),
    guard_workflows: ReadOnlyArray::from_array(guard_workflows),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
fn decode_guard_profile(bytes : Bytes) -> GuardProfile raise StorageError {
  let reader = StorageReader::new(bytes)
  if reader.read_bytes() != guarded_guard_profile_magic {
    raise ValidationFailure(field="guard_profile_magic")
  }
  ignore(storage_version(reader.read_string(), "guard_profile"))
  let profile_id = reader.read_string()
  let profile_name = reader.read_string()
  require_storage_text(profile_id, "guard_profile_id")
  require_storage_text(profile_name, "guard_profile_name")
  let guard_root_locators : Array[String] = []
  let guard_root_identities : Array[String] = []
  let guard_workflows : Array[@contracts.RecordRef] = []
  let count = reader.read_count()
  if count == 0 {
    raise ValidationFailure(field="guard_profile_workflows")
  }
  for _ in 0..<count {
    guard_root_locators.push(reader.read_string())
    guard_root_identities.push(reader.read_string())
    guard_workflows.push(decode_record_ref(reader.read_bytes()))
  }
  reader.require_end()
  for index, workflow in guard_workflows {
    require_storage_text(guard_root_locators[index], "guard_profile_locator")
    require_storage_text(guard_root_identities[index], "guard_profile_root")
    for prior in 0..<index {
      if exact_record_equal(guard_workflows[prior], workflow) {
        raise ValidationFailure(field="guard_profile_duplicate_workflow")
      }
    }
  }
  let canonical = guard_profile_signing_bytes(
    profile_id, profile_name, guard_root_locators, guard_root_identities, guard_workflows,
  )
  if canonical != bytes {
    raise ValidationFailure(field="noncanonical_guard_profile")
  }
  {
    profile_id,
    profile_name,
    guard_root_locators: ReadOnlyArray::from_array(guard_root_locators),
    guard_root_identities: ReadOnlyArray::from_array(guard_root_identities),
    guard_workflows: ReadOnlyArray::from_array(guard_workflows),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn GuardProfile::profile_id(self : GuardProfile) -> String {
  self.profile_id
}

///|
pub fn GuardProfile::profile_name(self : GuardProfile) -> String {
  self.profile_name
}

///|
pub fn GuardProfile::guard_workflows(
  self : GuardProfile,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.guard_workflows
}

///|
pub fn GuardProfile::guard_root_locators(
  self : GuardProfile,
) -> ReadOnlyArray[String] {
  self.guard_root_locators
}

///|
pub fn GuardProfile::guard_root_identities(
  self : GuardProfile,
) -> ReadOnlyArray[String] {
  self.guard_root_identities
}

///|
pub fn GuardProfile::canonical_bytes(self : GuardProfile) -> Bytes {
  self.canonical
}

///|
pub fn GuardProfile::digest(self : GuardProfile) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Immutable generic storage binding. Profile order and every profile body are
/// append-only registry state; a generation names one exact registry revision.
pub struct GuardedWorkflowBinding {
  registry_version : @contracts.Version
  registry_generation : Int64
  prior_registry_digest : @contracts.ContentDigest?
  store_domain : String
  workspace_identity : String
  mutation_root_locator : String
  mutation_root_identity : String
  mutation_workflow : @contracts.RecordRef
  profiles : ReadOnlyArray[GuardProfile]
  // Compatibility aliases for the first/default profile.
  guard_root_locators : ReadOnlyArray[String]
  guard_root_identities : ReadOnlyArray[String]
  guard_workflows : ReadOnlyArray[@contracts.RecordRef]
  activation_revision : Int64
  activation_head_digest : @contracts.ContentDigest?
  activation_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  registry_digest : @contracts.ContentDigest
}

///|
fn guarded_binding_signing_bytes(
  registry_generation : Int64,
  prior_registry_digest : @contracts.ContentDigest?,
  store_domain : String,
  workspace_identity : String,
  mutation_root_locator : String,
  mutation_root_identity : String,
  mutation_workflow : @contracts.RecordRef,
  profiles : Array[GuardProfile],
  activation_revision : Int64,
  activation_head_digest : @contracts.ContentDigest?,
  activation_replay_digest : @contracts.ContentDigest,
) -> Bytes raise StorageError {
  let writer = StorageWriter::new()
  writer.write_bytes(guarded_workflow_binding_magic)
  writer.write_string(guarded_registry_version_text)
  writer.write_int64(registry_generation)
  write_optional_digest(writer, prior_registry_digest)
  writer.write_string(store_domain)
  writer.write_string(workspace_identity)
  writer.write_string(mutation_root_locator)
  writer.write_string(mutation_root_identity)
  writer.write_bytes(encode_record_ref(mutation_workflow, false))
  writer.write_count(profiles.length())
  for profile in profiles {
    writer.write_bytes(profile.canonical)
  }
  writer.write_int64(activation_revision)
  write_optional_digest(writer, activation_head_digest)
  writer.write_string(activation_replay_digest.text())
  writer.finish()
}

///|
fn validate_guard_profiles(
  mutation_workflow : @contracts.RecordRef,
  profiles : ArrayView[GuardProfile],
) -> Unit raise StorageError {
  if profiles.is_empty() {
    raise ValidationFailure(field="guarded_binding_profiles")
  }
  for index, profile in profiles {
    for workflow in profile.guard_workflows {
      if exact_record_equal(workflow, mutation_workflow) {
        raise ValidationFailure(field="guard_profile_independent_workflow")
      }
    }
    for prior in 0..<index {
      if profiles[prior].profile_id == profile.profile_id {
        raise ValidationFailure(field="guarded_binding_duplicate_profile_id")
      }
    }
  }
}

///|
fn make_guarded_workflow_binding(
  registry_generation : Int64,
  prior_registry_digest : @contracts.ContentDigest?,
  store_domain : String,
  workspace_identity : String,
  mutation_root_locator : String,
  mutation_root_identity : String,
  mutation_workflow : @contracts.RecordRef,
  profiles : Array[GuardProfile],
  activation_revision : Int64,
  activation_head_digest : @contracts.ContentDigest?,
  activation_replay_digest : @contracts.ContentDigest,
) -> GuardedWorkflowBinding raise StorageError {
  require_storage_text(store_domain, "guarded_binding_store_domain")
  require_storage_text(workspace_identity, "guarded_binding_workspace")
  require_storage_text(
    mutation_root_locator, "guarded_binding_mutation_locator",
  )
  require_storage_text(mutation_root_identity, "guarded_binding_mutation_root")
  if registry_generation < 1L ||
    (registry_generation == 1L) != (prior_registry_digest is None) ||
    activation_revision < 0L ||
    (activation_revision == 0L) != (activation_head_digest is None) {
    raise ValidationFailure(field="guarded_binding_generation")
  }
  validate_guard_profiles(mutation_workflow, profiles)
  let canonical = guarded_binding_signing_bytes(
    registry_generation, prior_registry_digest, store_domain, workspace_identity,
    mutation_root_locator, mutation_root_identity, mutation_workflow, profiles, activation_revision,
    activation_head_digest, activation_replay_digest,
  )
  let default_profile = profiles[0]
  {
    registry_version: storage_version(
      guarded_registry_version_text, "guarded_workflow_registry",
    ),
    registry_generation,
    prior_registry_digest,
    store_domain,
    workspace_identity,
    mutation_root_locator,
    mutation_root_identity,
    mutation_workflow,
    profiles: ReadOnlyArray::from_array(profiles.copy()),
    guard_root_locators: default_profile.guard_root_locators,
    guard_root_identities: default_profile.guard_root_identities,
    guard_workflows: default_profile.guard_workflows,
    activation_revision,
    activation_head_digest,
    activation_replay_digest,
    canonical,
    registry_digest: @contracts.sha256_digest(canonical),
  }
}

///|
fn new_guarded_workflow_binding_profiles(
  store_domain : String,
  workspace_identity : String,
  mutation_root_locator : String,
  mutation_root_identity : String,
  mutation_workflow : @contracts.RecordRef,
  profiles : Array[GuardProfile],
  activation : ReplayResult,
) -> GuardedWorkflowBinding raise StorageError {
  if !exact_record_equal(activation.workflow(), mutation_workflow) ||
    !exact_record_equal(activation.head().workflow(), mutation_workflow) {
    raise ValidationFailure(field="guarded_binding_activation_workflow")
  }
  let head = activation.head()
  make_guarded_workflow_binding(
    1L,
    None,
    store_domain,
    workspace_identity,
    mutation_root_locator,
    mutation_root_identity,
    mutation_workflow,
    profiles,
    head.revision(),
    head.last_event_digest(),
    activation.replay_digest(),
  )
}

///|
fn new_guarded_workflow_binding(
  store_domain : String,
  workspace_identity : String,
  mutation_root_locator : String,
  mutation_root_identity : String,
  mutation_workflow : @contracts.RecordRef,
  guard_root_locators : Array[String],
  guard_root_identities : Array[String],
  guard_workflows : Array[@contracts.RecordRef],
  activation : ReplayResult,
) -> GuardedWorkflowBinding raise StorageError {
  let config = GuardProfileConfig::new(
    guarded_default_profile_id_text, guarded_default_profile_name_text, guard_workflows,
  )
  let profile = new_guard_profile(
    config, mutation_workflow, guard_root_locators, guard_root_identities,
  )
  new_guarded_workflow_binding_profiles(
    store_domain,
    workspace_identity,
    mutation_root_locator,
    mutation_root_identity,
    mutation_workflow,
    [profile],
    activation,
  )
}

///|
fn evolve_guarded_workflow_binding(
  prior : GuardedWorkflowBinding,
  added : GuardProfile,
) -> GuardedWorkflowBinding raise StorageError {
  if prior.profiles.any(profile => profile.profile_id == added.profile_id) {
    raise GuardedBindingConflict(
      workflow_id=prior.mutation_workflow.id(),
      field="guard_profile_id",
    )
  }
  let profiles = [ for profile in prior.profiles => profile ]
  profiles.push(added)
  make_guarded_workflow_binding(
    prior.registry_generation + 1L,
    Some(prior.registry_digest),
    prior.store_domain,
    prior.workspace_identity,
    prior.mutation_root_locator,
    prior.mutation_root_identity,
    prior.mutation_workflow,
    profiles,
    prior.activation_revision,
    prior.activation_head_digest,
    prior.activation_replay_digest,
  )
}

///|
fn decode_guarded_workflow_binding_v1(
  bytes : Bytes,
) -> GuardedWorkflowBinding raise StorageError {
  let reader = StorageReader::new(bytes)
  if reader.read_bytes() != guarded_workflow_binding_v1_magic {
    raise ValidationFailure(field="guarded_workflow_binding_magic")
  }
  ignore(storage_version(reader.read_string(), "guarded_workflow_registry"))
  let store_domain = reader.read_string()
  let workspace_identity = reader.read_string()
  let mutation_root_locator = reader.read_string()
  let mutation_root_identity = reader.read_string()
  let mutation_workflow = decode_record_ref(reader.read_bytes())
  let guard_root_locators : Array[String] = []
  let guard_root_identities : Array[String] = []
  let guard_workflows : Array[@contracts.RecordRef] = []
  let guard_count = reader.read_count()
  for _ in 0..<guard_count {
    guard_root_locators.push(reader.read_string())
    guard_root_identities.push(reader.read_string())
    guard_workflows.push(decode_record_ref(reader.read_bytes()))
  }
  let activation_revision = reader.read_int64()
  let activation_head_digest = read_optional_digest(reader)
  let activation_replay_digest = parse_content_digest(
    reader.read_string(),
    "guarded_binding_activation_replay",
  )
  reader.require_end()
  let config = GuardProfileConfig::new(
    guarded_default_profile_id_text, guarded_default_profile_name_text, guard_workflows,
  )
  let profile = new_guard_profile(
    config, mutation_workflow, guard_root_locators, guard_root_identities,
  )
  let upgraded = make_guarded_workflow_binding(
    1L,
    None,
    store_domain,
    workspace_identity,
    mutation_root_locator,
    mutation_root_identity,
    mutation_workflow,
    [profile],
    activation_revision,
    activation_head_digest,
    activation_replay_digest,
  )
  // Retain the old bytes/digest so old declaration markers remain valid and
  // can be the exact prior link of a new append-only generation.
  {
    ..upgraded,
    canonical: bytes,
    registry_digest: @contracts.sha256_digest(bytes),
  }
}

///|
fn decode_guarded_workflow_binding(
  bytes : Bytes,
) -> GuardedWorkflowBinding raise StorageError {
  let probe = StorageReader::new(bytes)
  let magic = probe.read_bytes()
  if magic == guarded_workflow_binding_v1_magic {
    return decode_guarded_workflow_binding_v1(bytes)
  }
  if magic != guarded_workflow_binding_magic {
    raise ValidationFailure(field="guarded_workflow_binding_magic")
  }
  let reader = StorageReader::new(bytes)
  ignore(reader.read_bytes())
  ignore(storage_version(reader.read_string(), "guarded_workflow_registry"))
  let registry_generation = reader.read_int64()
  let prior_registry_digest = read_optional_digest(reader)
  let store_domain = reader.read_string()
  let workspace_identity = reader.read_string()
  let mutation_root_locator = reader.read_string()
  let mutation_root_identity = reader.read_string()
  let mutation_workflow = decode_record_ref(reader.read_bytes())
  let profiles : Array[GuardProfile] = []
  let profile_count = reader.read_count()
  for _ in 0..<profile_count {
    profiles.push(decode_guard_profile(reader.read_bytes()))
  }
  let activation_revision = reader.read_int64()
  let activation_head_digest = read_optional_digest(reader)
  let activation_replay_digest = parse_content_digest(
    reader.read_string(),
    "guarded_binding_activation_replay",
  )
  reader.require_end()
  let value = make_guarded_workflow_binding(
    registry_generation, prior_registry_digest, store_domain, workspace_identity,
    mutation_root_locator, mutation_root_identity, mutation_workflow, profiles, activation_revision,
    activation_head_digest, activation_replay_digest,
  )
  if value.canonical != bytes {
    raise ValidationFailure(field="noncanonical_guarded_workflow_binding")
  }
  value
}

///|
fn guarded_registry_declaration_bytes(
  binding : GuardedWorkflowBinding,
) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(guarded_registry_declaration_magic)
  try! writer.write_string(guarded_registry_version_text)
  try! writer.write_string(binding.registry_digest.text())
  try! writer.write_bytes(binding.canonical)
  writer.finish()
}

///|
fn decode_guarded_registry_declaration(
  bytes : Bytes,
) -> GuardedWorkflowBinding raise StorageError {
  let reader = StorageReader::new(bytes)
  let magic = reader.read_bytes()
  if magic != guarded_registry_declaration_magic &&
    magic != guarded_registry_declaration_v1_magic {
    raise ValidationFailure(field="guarded_registry_declaration_magic")
  }
  ignore(storage_version(reader.read_string(), "guarded_registry_declaration"))
  let declared_digest = parse_content_digest(
    reader.read_string(),
    "guarded_registry_declaration_digest",
  )
  let binding = decode_guarded_workflow_binding(reader.read_bytes())
  reader.require_end()
  if declared_digest != binding.registry_digest {
    raise ValidationFailure(field="guarded_registry_declaration_binding")
  }
  let canonical_writer = StorageWriter::new()
  canonical_writer.write_bytes(magic)
  canonical_writer.write_string(guarded_registry_version_text)
  canonical_writer.write_string(binding.registry_digest.text())
  canonical_writer.write_bytes(binding.canonical)
  if canonical_writer.finish() != bytes {
    raise ValidationFailure(field="guarded_registry_declaration_binding")
  }
  binding
}

///|
fn guarded_registry_workflow_key(workflow : @contracts.RecordRef) -> String {
  @contracts.sha256_digest(encode_record_ref(workflow, false)).hex()
}

///|
fn guarded_registry_declaration_name(workflow : @contracts.RecordRef) -> String {
  guarded_registry_declaration_prefix +
  guarded_registry_workflow_key(workflow) +
  guarded_registry_declaration_suffix
}

///|
fn guarded_registry_generation_hex(value : Int64) -> String {
  let encoded = value.to_string(radix=16)
  let builder = StringBuilder()
  for _ in encoded.length()..<16 {
    builder.write_string("0")
  }
  builder.write_string(encoded)
  builder.to_string()
}

///|
fn guarded_registry_binding_name(binding : GuardedWorkflowBinding) -> String {
  guarded_registry_declaration_prefix +
  guarded_registry_workflow_key(binding.mutation_workflow) +
  "-" +
  guarded_registry_generation_hex(binding.registry_generation) +
  "-" +
  binding.registry_digest.hex() +
  guarded_registry_declaration_suffix
}

///|
fn guarded_registry_name_matches(
  name : String,
  binding : GuardedWorkflowBinding,
) -> Bool {
  name == guarded_registry_binding_name(binding) ||
  (
    binding.registry_generation == 1L &&
    name == guarded_registry_declaration_name(binding.mutation_workflow)
  )
}

///|
fn guarded_binding_marker_name(binding : GuardedWorkflowBinding) -> String {
  guarded_binding_marker_prefix +
  binding.registry_digest.hex() +
  guarded_binding_marker_suffix
}

///|
fn is_guarded_registry_declaration_name(name : String) -> Bool {
  name.has_prefix(guarded_registry_declaration_prefix) &&
  name.has_suffix(guarded_registry_declaration_suffix)
}

///|
fn is_guarded_binding_marker_name(name : String) -> Bool {
  name.has_prefix(guarded_binding_marker_prefix) &&
  name.has_suffix(guarded_binding_marker_suffix)
}

///|
fn find_guard_profile(
  binding : GuardedWorkflowBinding,
  profile_id : String,
) -> GuardProfile? {
  binding.profiles
  .search_by(profile => profile.profile_id == profile_id)
  .map(index => binding.profiles[index])
}

///|
fn profile_configuration_matches(
  profile : GuardProfile,
  config : GuardProfileConfig,
  guard_root_locators : ArrayView[String],
  guard_root_identities : ArrayView[String],
) -> Bool {
  if profile.profile_id != config.profile_id ||
    profile.profile_name != config.profile_name ||
    profile.guard_workflows.length() != config.guard_workflows.length() ||
    profile.guard_root_locators.length() != guard_root_locators.length() ||
    profile.guard_root_identities.length() != guard_root_identities.length() {
    return false
  }
  for index, workflow in config.guard_workflows {
    if profile.guard_root_locators[index] != guard_root_locators[index] ||
      profile.guard_root_identities[index] != guard_root_identities[index] ||
      !exact_record_equal(profile.guard_workflows[index], workflow) {
      return false
    }
  }
  true
}

///|
fn profiles_configuration_matches(
  binding : GuardedWorkflowBinding,
  configs : ArrayView[GuardProfileConfig],
  guard_root_locators : ArrayView[Array[String]],
  guard_root_identities : ArrayView[Array[String]],
) -> Bool {
  if binding.profiles.length() != configs.length() ||
    configs.length() != guard_root_locators.length() ||
    configs.length() != guard_root_identities.length() {
    return false
  }
  for index, config in configs {
    if !profile_configuration_matches(
        binding.profiles[index],
        config,
        guard_root_locators[index],
        guard_root_identities[index],
      ) {
      return false
    }
  }
  true
}

///|
fn binding_configuration_matches(
  binding : GuardedWorkflowBinding,
  store_domain : String,
  workspace_identity : String,
  mutation_root_locator : String,
  mutation_root_identity : String,
  mutation_workflow : @contracts.RecordRef,
  guard_root_locators : ArrayView[String],
  guard_root_identities : ArrayView[String],
  guard_workflows : ArrayView[@contracts.RecordRef],
) -> Bool {
  if binding.store_domain != store_domain ||
    binding.workspace_identity != workspace_identity ||
    binding.mutation_root_locator != mutation_root_locator ||
    binding.mutation_root_identity != mutation_root_identity ||
    !exact_record_equal(binding.mutation_workflow, mutation_workflow) {
    return false
  }
  guard find_guard_profile(binding, guarded_default_profile_id_text)
    is Some(profile) else {
    return false
  }
  let config = GuardProfileConfig::new(
    guarded_default_profile_id_text,
    guarded_default_profile_name_text,
    [
      for workflow in guard_workflows => workflow
    ],
  ) catch {
    _ => return false
  }
  profile_configuration_matches(
    profile, config, guard_root_locators, guard_root_identities,
  )
}

///|
fn binding_extends_exactly(
  prior : GuardedWorkflowBinding,
  current : GuardedWorkflowBinding,
) -> Bool {
  if current.registry_generation != prior.registry_generation + 1L ||
    current.prior_registry_digest != Some(prior.registry_digest) ||
    prior.store_domain != current.store_domain ||
    prior.workspace_identity != current.workspace_identity ||
    prior.mutation_root_locator != current.mutation_root_locator ||
    prior.mutation_root_identity != current.mutation_root_identity ||
    !exact_record_equal(prior.mutation_workflow, current.mutation_workflow) ||
    prior.activation_revision != current.activation_revision ||
    prior.activation_head_digest != current.activation_head_digest ||
    prior.activation_replay_digest != current.activation_replay_digest ||
    current.profiles.length() != prior.profiles.length() + 1 {
    return false
  }
  for index, profile in prior.profiles {
    if current.profiles[index].canonical != profile.canonical ||
      current.profiles[index].digest != profile.digest {
      return false
    }
  }
  true
}

///|
fn binding_descends_from(
  bindings : ArrayView[GuardedWorkflowBinding],
  ancestor : GuardedWorkflowBinding,
  current : GuardedWorkflowBinding,
) -> Bool {
  if ancestor.registry_digest == current.registry_digest {
    return ancestor.canonical == current.canonical
  }
  let mut cursor = current
  for _ in ancestor.registry_generation..<current.registry_generation {
    guard cursor.prior_registry_digest is Some(prior_digest) else {
      return false
    }
    guard bindings.search_by(value => value.registry_digest == prior_digest)
      is Some(index) else {
      return false
    }
    let prior = bindings[index]
    if !binding_extends_exactly(prior, cursor) {
      return false
    }
    cursor = prior
  }
  cursor.registry_digest == ancestor.registry_digest &&
  cursor.canonical == ancestor.canonical
}

///|
fn latest_guarded_binding(
  bindings : ArrayView[GuardedWorkflowBinding],
  workflow : @contracts.RecordRef,
) -> GuardedWorkflowBinding? raise StorageError {
  let matching = [
    for binding in bindings if record_identity_equal(
      binding.mutation_workflow,
      workflow,
    ) => binding
  ]
  if matching.is_empty() {
    return None
  }
  for binding in matching {
    if !exact_record_equal(binding.mutation_workflow, workflow) {
      raise GuardedBindingFork(workflow_id=workflow.id())
    }
  }
  guard matching.search_by(binding => binding.registry_generation == 1L)
    is Some(root_index) else {
    raise GuardedBindingFork(workflow_id=workflow.id())
  }
  let mut current = matching[root_index]
  for _ in 1..<matching.length() {
    let candidates = [
      for binding in matching if binding.prior_registry_digest ==
      Some(current.registry_digest) => binding
    ]
    if candidates.length() != 1 ||
      !binding_extends_exactly(current, candidates[0]) {
      raise GuardedBindingFork(workflow_id=workflow.id())
    }
    current = candidates[0]
  }
  Some(current)
}

///|
fn require_binding_activation_prefix(
  binding : GuardedWorkflowBinding,
  replay : ReplayResult,
) -> Unit raise StorageError {
  if !exact_record_equal(binding.mutation_workflow, replay.workflow()) ||
    replay.head().revision() < binding.activation_revision {
    raise GuardedBindingFork(workflow_id=binding.mutation_workflow.id())
  }
  let prefix = replay.verified_prefix(binding.activation_revision) catch {
    _ => raise GuardedBindingFork(workflow_id=binding.mutation_workflow.id())
  }
  if prefix.head().last_event_digest() != binding.activation_head_digest ||
    prefix.replay_digest() != binding.activation_replay_digest {
    raise GuardedBindingFork(workflow_id=binding.mutation_workflow.id())
  }
}

///|
fn guarded_request_matches_profile(
  request : GuardedCommitRequest,
  binding : GuardedWorkflowBinding,
  profile : GuardProfile,
) -> Bool {
  if !exact_record_equal(request.mutation.workflow, binding.mutation_workflow) ||
    request.guards.length() != profile.guard_workflows.length() {
    return false
  }
  for index, head_guard in request.guards {
    if !exact_record_equal(head_guard.workflow, profile.guard_workflows[index]) {
      return false
    }
  }
  true
}

///|
fn guarded_request_matching_profile(
  request : GuardedCommitRequest,
  binding : GuardedWorkflowBinding,
) -> GuardProfile? {
  for profile in binding.profiles {
    if guarded_request_matches_profile(request, binding, profile) {
      return Some(profile)
    }
  }
  None
}

///|
fn guarded_request_matches_binding(
  request : GuardedCommitRequest,
  binding : GuardedWorkflowBinding,
) -> Bool {
  guarded_request_matching_profile(request, binding) is Some(_)
}

///|
/// Opaque proof of one exact initial registry activation. It grants no mutation
/// authority except through storage-owned wrapper construction.
pub struct GuardedWorkflowActivationReceipt {
  registry_version : @contracts.Version
  binding : GuardedWorkflowBinding
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_guarded_activation_receipt(
  binding : GuardedWorkflowBinding,
) -> GuardedWorkflowActivationReceipt {
  let writer = StorageWriter::new()
  try! writer.write_bytes(guarded_activation_receipt_magic)
  try! writer.write_string(guarded_registry_version_text)
  try! writer.write_string(binding.registry_digest.text())
  try! writer.write_bytes(binding.canonical)
  let canonical = writer.finish()
  {
    registry_version: binding.registry_version,
    binding,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
/// Opaque receipt for one append-only registry evolution.
pub struct GuardedWorkflowEvolutionReceipt {
  registry_version : @contracts.Version
  prior_registry_generation : Int64
  prior_registry_digest : @contracts.ContentDigest
  current_binding : GuardedWorkflowBinding
  added_profile_id : String
  added_profile_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_guarded_evolution_receipt(
  prior : GuardedWorkflowBinding,
  current : GuardedWorkflowBinding,
  added : GuardProfile,
) -> GuardedWorkflowEvolutionReceipt raise StorageError {
  if !binding_extends_exactly(prior, current) ||
    current.profiles[current.profiles.length() - 1].canonical != added.canonical {
    raise GuardedBindingFork(workflow_id=current.mutation_workflow.id())
  }
  let writer = StorageWriter::new()
  writer.write_bytes(guarded_evolution_receipt_magic)
  writer.write_string(guarded_registry_version_text)
  writer.write_int64(prior.registry_generation)
  writer.write_string(prior.registry_digest.text())
  writer.write_int64(current.registry_generation)
  writer.write_string(current.registry_digest.text())
  writer.write_string(added.profile_id)
  writer.write_string(added.digest.text())
  let canonical = writer.finish()
  {
    registry_version: current.registry_version,
    prior_registry_generation: prior.registry_generation,
    prior_registry_digest: prior.registry_digest,
    current_binding: current,
    added_profile_id: added.profile_id,
    added_profile_digest: added.digest,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn GuardedWorkflowBinding::registry_version(
  self : GuardedWorkflowBinding,
) -> @contracts.Version {
  self.registry_version
}

///|
pub fn GuardedWorkflowBinding::registry_generation(
  self : GuardedWorkflowBinding,
) -> Int64 {
  self.registry_generation
}

///|
pub fn GuardedWorkflowBinding::prior_registry_digest(
  self : GuardedWorkflowBinding,
) -> @contracts.ContentDigest? {
  self.prior_registry_digest
}

///|
pub fn GuardedWorkflowBinding::registry_digest(
  self : GuardedWorkflowBinding,
) -> @contracts.ContentDigest {
  self.registry_digest
}

///|
pub fn GuardedWorkflowBinding::mutation_workflow(
  self : GuardedWorkflowBinding,
) -> @contracts.RecordRef {
  self.mutation_workflow
}

///|
pub fn GuardedWorkflowBinding::activation_revision(
  self : GuardedWorkflowBinding,
) -> Int64 {
  self.activation_revision
}

///|
pub fn GuardedWorkflowBinding::guard_profiles(
  self : GuardedWorkflowBinding,
) -> ReadOnlyArray[GuardProfile] {
  self.profiles
}

///|
pub fn GuardedWorkflowBinding::guard_profile(
  self : GuardedWorkflowBinding,
  profile_id : String,
) -> GuardProfile? {
  find_guard_profile(self, profile_id)
}

///|
pub fn GuardedWorkflowBinding::canonical_bytes(
  self : GuardedWorkflowBinding,
) -> Bytes {
  self.canonical
}

///|
pub fn GuardedWorkflowActivationReceipt::registry_version(
  self : GuardedWorkflowActivationReceipt,
) -> @contracts.Version {
  self.registry_version
}

///|
pub fn GuardedWorkflowActivationReceipt::workflow_binding(
  self : GuardedWorkflowActivationReceipt,
) -> GuardedWorkflowBinding {
  self.binding
}

///|
pub fn GuardedWorkflowActivationReceipt::mutation_workflow(
  self : GuardedWorkflowActivationReceipt,
) -> @contracts.RecordRef {
  self.binding.mutation_workflow
}

///|
pub fn GuardedWorkflowActivationReceipt::registry_generation(
  self : GuardedWorkflowActivationReceipt,
) -> Int64 {
  self.binding.registry_generation
}

///|
pub fn GuardedWorkflowActivationReceipt::registry_digest(
  self : GuardedWorkflowActivationReceipt,
) -> @contracts.ContentDigest {
  self.binding.registry_digest
}

///|
pub fn GuardedWorkflowActivationReceipt::activation_revision(
  self : GuardedWorkflowActivationReceipt,
) -> Int64 {
  self.binding.activation_revision
}

///|
pub fn GuardedWorkflowActivationReceipt::guard_profiles(
  self : GuardedWorkflowActivationReceipt,
) -> ReadOnlyArray[GuardProfile] {
  self.binding.profiles
}

///|
pub fn GuardedWorkflowActivationReceipt::canonical_bytes(
  self : GuardedWorkflowActivationReceipt,
) -> Bytes {
  self.canonical
}

///|
pub fn GuardedWorkflowActivationReceipt::digest(
  self : GuardedWorkflowActivationReceipt,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn GuardedWorkflowEvolutionReceipt::registry_version(
  self : GuardedWorkflowEvolutionReceipt,
) -> @contracts.Version {
  self.registry_version
}

///|
pub fn GuardedWorkflowEvolutionReceipt::workflow_binding(
  self : GuardedWorkflowEvolutionReceipt,
) -> GuardedWorkflowBinding {
  self.current_binding
}

///|
pub fn GuardedWorkflowEvolutionReceipt::mutation_workflow(
  self : GuardedWorkflowEvolutionReceipt,
) -> @contracts.RecordRef {
  self.current_binding.mutation_workflow
}

///|
pub fn GuardedWorkflowEvolutionReceipt::prior_registry_generation(
  self : GuardedWorkflowEvolutionReceipt,
) -> Int64 {
  self.prior_registry_generation
}

///|
pub fn GuardedWorkflowEvolutionReceipt::prior_registry_digest(
  self : GuardedWorkflowEvolutionReceipt,
) -> @contracts.ContentDigest {
  self.prior_registry_digest
}

///|
pub fn GuardedWorkflowEvolutionReceipt::registry_generation(
  self : GuardedWorkflowEvolutionReceipt,
) -> Int64 {
  self.current_binding.registry_generation
}

///|
pub fn GuardedWorkflowEvolutionReceipt::registry_digest(
  self : GuardedWorkflowEvolutionReceipt,
) -> @contracts.ContentDigest {
  self.current_binding.registry_digest
}

///|
pub fn GuardedWorkflowEvolutionReceipt::added_profile_id(
  self : GuardedWorkflowEvolutionReceipt,
) -> String {
  self.added_profile_id
}

///|
pub fn GuardedWorkflowEvolutionReceipt::added_profile_digest(
  self : GuardedWorkflowEvolutionReceipt,
) -> @contracts.ContentDigest {
  self.added_profile_digest
}

///|
pub fn GuardedWorkflowEvolutionReceipt::guard_profiles(
  self : GuardedWorkflowEvolutionReceipt,
) -> ReadOnlyArray[GuardProfile] {
  self.current_binding.profiles
}

///|
pub fn GuardedWorkflowEvolutionReceipt::activation_receipt(
  self : GuardedWorkflowEvolutionReceipt,
) -> GuardedWorkflowActivationReceipt {
  make_guarded_activation_receipt(self.current_binding)
}

///|
pub fn GuardedWorkflowEvolutionReceipt::canonical_bytes(
  self : GuardedWorkflowEvolutionReceipt,
) -> Bytes {
  self.canonical
}

///|
pub fn GuardedWorkflowEvolutionReceipt::digest(
  self : GuardedWorkflowEvolutionReceipt,
) -> @contracts.ContentDigest {
  self.digest
}
