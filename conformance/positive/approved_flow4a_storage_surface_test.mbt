///|
fn empty_replay_digest() -> Unit { () }

///|
type StorageError

///|
type CheckpointRecord

///|
fn CheckpointRecord::canonical_bytes() -> Unit { () }

///|
fn CheckpointRecord::checkpoint_ref() -> Unit { () }

///|
fn CheckpointRecord::event_sequence() -> Unit { () }

///|
fn CheckpointRecord::evidence() -> Unit { () }

///|
fn CheckpointRecord::last_event_digest() -> Unit { () }

///|
fn CheckpointRecord::new() -> Unit { () }

///|
fn CheckpointRecord::projection_version() -> Unit { () }

///|
fn CheckpointRecord::record_version() -> Unit { () }

///|
fn CheckpointRecord::schema_version() -> Unit { () }

///|
fn CheckpointRecord::snapshot() -> Unit { () }

///|
fn CheckpointRecord::workflow() -> Unit { () }

///|
fn CheckpointRecord::workflow_revision() -> Unit { () }

///|
type CommitRequest

///|
fn CommitRequest::canonical_bytes() -> Unit { () }

///|
fn CommitRequest::command_idempotency_key() -> Unit { () }

///|
fn CommitRequest::events() -> Unit { () }

///|
fn CommitRequest::expected_revision() -> Unit { () }

///|
fn CommitRequest::intents() -> Unit { () }

///|
fn CommitRequest::new() -> Unit { () }

///|
fn CommitRequest::record_version() -> Unit { () }

///|
fn CommitRequest::schema_version() -> Unit { () }

///|
fn CommitRequest::workflow() -> Unit { () }

///|
type CommitResult

///|
fn CommitResult::batch_digest() -> Unit { () }

///|
fn CommitResult::command_idempotency_key() -> Unit { () }

///|
fn CommitResult::event_count() -> Unit { () }

///|
fn CommitResult::first_sequence() -> Unit { () }

///|
fn CommitResult::intent_count() -> Unit { () }

///|
fn CommitResult::last_event_digest() -> Unit { () }

///|
fn CommitResult::last_sequence() -> Unit { () }

///|
fn CommitResult::record_version() -> Unit { () }

///|
fn CommitResult::schema_version() -> Unit { () }

///|
fn CommitResult::workflow() -> Unit { () }

///|
fn CommitResult::workflow_revision() -> Unit { () }

///|
type CommittedBatchBoundary

///|
fn CommittedBatchBoundary::batch_digest() -> Unit { () }

///|
fn CommittedBatchBoundary::command_idempotency_key() -> Unit { () }

///|
fn CommittedBatchBoundary::event_refs() -> Unit { () }

///|
fn CommittedBatchBoundary::expected_revision() -> Unit { () }

///|
fn CommittedBatchBoundary::intent_refs() -> Unit { () }

///|
type FileSystemStore

///|
fn FileSystemStore::commit() -> Unit { () }

///|
fn FileSystemStore::events() -> Unit { () }

///|
fn FileSystemStore::head() -> Unit { () }

///|
fn FileSystemStore::intents() -> Unit { () }

///|
fn FileSystemStore::open() -> Unit { () }

///|
fn FileSystemStore::read_checkpoint() -> Unit { () }

///|
fn FileSystemStore::record_version() -> Unit { () }

///|
fn FileSystemStore::replay() -> Unit { () }

///|
fn FileSystemStore::schema_version() -> Unit { () }

///|
fn FileSystemStore::storage_root() -> Unit { () }

///|
fn FileSystemStore::workspace_root() -> Unit { () }

///|
fn FileSystemStore::write_checkpoint() -> Unit { () }

///|
fn FileSystemStore::guarded_commit() -> Unit { () }

///|
type FileSystemGuardedStore

///|
fn FileSystemGuardedStore::commit() -> Unit { () }

///|
fn FileSystemGuardedStore::events() -> Unit { () }

///|
fn FileSystemGuardedStore::guarded_commit() -> Unit { () }

///|
fn FileSystemGuardedStore::head() -> Unit { () }

///|
fn FileSystemGuardedStore::intents() -> Unit { () }

///|
fn FileSystemGuardedStore::mutation_store() -> Unit { () }

///|
fn FileSystemGuardedStore::new() -> Unit { () }

///|
fn FileSystemGuardedStore::read_checkpoint() -> Unit { () }

///|
fn FileSystemGuardedStore::replay() -> Unit { () }

///|
fn FileSystemGuardedStore::write_checkpoint() -> Unit { () }

///|
type GuardConflictReceipt

///|
fn GuardConflictReceipt::actual_head_digest() -> Unit { () }

///|
fn GuardConflictReceipt::actual_replay_digest() -> Unit { () }

///|
fn GuardConflictReceipt::actual_revision() -> Unit { () }

///|
fn GuardConflictReceipt::canonical_bytes() -> Unit { () }

///|
fn GuardConflictReceipt::command_idempotency_key() -> Unit { () }

///|
fn GuardConflictReceipt::digest() -> Unit { () }

///|
fn GuardConflictReceipt::expected_head_digest() -> Unit { () }

///|
fn GuardConflictReceipt::expected_replay_digest() -> Unit { () }

///|
fn GuardConflictReceipt::expected_revision() -> Unit { () }

///|
fn GuardConflictReceipt::guard_workflow() -> Unit { () }

///|
fn GuardConflictReceipt::mutation_workflow() -> Unit { () }

///|
fn GuardConflictReceipt::request_digest() -> Unit { () }

///|
fn GuardConflictReceipt::validate_current() -> Unit { () }

///|
type GuardedCommitOutcome

///|
type GuardedCommitRequest

///|
fn GuardedCommitRequest::canonical_bytes() -> Unit { () }

///|
fn GuardedCommitRequest::digest() -> Unit { () }

///|
fn GuardedCommitRequest::guards() -> Unit { () }

///|
fn GuardedCommitRequest::mutation() -> Unit { () }

///|
fn GuardedCommitRequest::new() -> Unit { () }

///|
type MemoryStore

///|
fn MemoryStore::commit() -> Unit { () }

///|
fn MemoryStore::events() -> Unit { () }

///|
fn MemoryStore::head() -> Unit { () }

///|
fn MemoryStore::intents() -> Unit { () }

///|
fn MemoryStore::guarded_commit() -> Unit { () }

///|
fn MemoryStore::new() -> Unit { () }

///|
fn MemoryStore::read_checkpoint() -> Unit { () }

///|
fn MemoryStore::record_version() -> Unit { () }

///|
fn MemoryStore::replay() -> Unit { () }

///|
fn MemoryStore::schema_version() -> Unit { () }

///|
fn MemoryStore::write_checkpoint() -> Unit { () }

///|
type OutboxIntent

///|
fn OutboxIntent::canonical_bytes() -> Unit { () }

///|
fn OutboxIntent::causative_event() -> Unit { () }

///|
fn OutboxIntent::evidence() -> Unit { () }

///|
fn OutboxIntent::idempotency_key() -> Unit { () }

///|
fn OutboxIntent::intent_ref() -> Unit { () }

///|
fn OutboxIntent::new() -> Unit { () }

///|
fn OutboxIntent::payload() -> Unit { () }

///|
fn OutboxIntent::record_version() -> Unit { () }

///|
fn OutboxIntent::schema_version() -> Unit { () }

///|
fn OutboxIntent::workflow() -> Unit { () }

///|
type ReplayResult

///|
fn ReplayResult::checkpoint() -> Unit { () }

///|
fn ReplayResult::committed_batches() -> Unit { () }

///|
fn ReplayResult::events() -> Unit { () }

///|
fn ReplayResult::head() -> Unit { () }

///|
fn ReplayResult::verified_prefix() -> Unit { () }

///|
fn ReplayResult::intents() -> Unit { () }

///|
fn ReplayResult::record_version() -> Unit { () }

///|
fn ReplayResult::replay_digest() -> Unit { () }

///|
fn ReplayResult::schema_version() -> Unit { () }

///|
fn ReplayResult::tail_events() -> Unit { () }

///|
fn ReplayResult::workflow() -> Unit { () }

///|
type WorkflowEvent

///|
fn WorkflowEvent::canonical_bytes() -> Unit { () }

///|
fn WorkflowEvent::event_ref() -> Unit { () }

///|
fn WorkflowEvent::evidence() -> Unit { () }

///|
fn WorkflowEvent::idempotency_key() -> Unit { () }

///|
fn WorkflowEvent::new() -> Unit { () }

///|
fn WorkflowEvent::payload() -> Unit { () }

///|
fn WorkflowEvent::previous_event_digest() -> Unit { () }

///|
fn WorkflowEvent::record_version() -> Unit { () }

///|
fn WorkflowEvent::revision() -> Unit { () }

///|
fn WorkflowEvent::schema_version() -> Unit { () }

///|
fn WorkflowEvent::sequence() -> Unit { () }

///|
fn WorkflowEvent::workflow() -> Unit { () }

///|
type WorkflowHead

///|
fn WorkflowHead::event_count() -> Unit { () }

///|
fn WorkflowHead::intent_count() -> Unit { () }

///|
fn WorkflowHead::last_event_digest() -> Unit { () }

///|
fn WorkflowHead::revision() -> Unit { () }

///|
fn WorkflowHead::sequence() -> Unit { () }

///|
fn WorkflowHead::workflow() -> Unit { () }

///|
trait StoragePort {}

///|
trait GuardedStoragePort {}

///|
type WorkflowHeadGuard

///|
fn WorkflowHeadGuard::canonical_bytes() -> Unit { () }

///|
fn WorkflowHeadGuard::expected_head_digest() -> Unit { () }

///|
fn WorkflowHeadGuard::expected_replay_digest() -> Unit { () }

///|
fn WorkflowHeadGuard::expected_revision() -> Unit { () }

///|
fn WorkflowHeadGuard::new() -> Unit { () }

///|
fn WorkflowHeadGuard::workflow() -> Unit { () }
