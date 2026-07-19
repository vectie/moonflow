// Mechanically mirrored from closed_loop/storage/pkg.generated.mbti.
// Types and trait:
// StorageError CheckpointRecord CommitRequest CommitResult CommittedBatchBoundary
// FileSystemGuardedStore FileSystemStore GuardConflictReceipt GuardedCommitOutcome
// GuardedCommitRequest MemoryStore OutboxIntent ReplayResult WorkflowEvent WorkflowHead
// GuardedStoragePort StoragePort WorkflowHeadGuard empty_replay_digest
// Checkpoint methods:
// CheckpointRecord::canonical_bytes CheckpointRecord::checkpoint_ref
// CheckpointRecord::event_sequence CheckpointRecord::evidence
// CheckpointRecord::last_event_digest CheckpointRecord::new
// CheckpointRecord::projection_version CheckpointRecord::record_version
// CheckpointRecord::schema_version CheckpointRecord::snapshot
// CheckpointRecord::workflow CheckpointRecord::workflow_revision
// Request methods:
// CommitRequest::canonical_bytes CommitRequest::command_idempotency_key
// CommitRequest::events CommitRequest::expected_revision CommitRequest::intents
// CommitRequest::new CommitRequest::record_version CommitRequest::schema_version
// CommitRequest::workflow
// Result methods:
// CommitResult::batch_digest CommitResult::command_idempotency_key
// CommitResult::event_count CommitResult::first_sequence
// CommitResult::intent_count CommitResult::last_event_digest
// CommitResult::last_sequence CommitResult::record_version
// CommitResult::schema_version CommitResult::workflow
// CommitResult::workflow_revision
// Committed batch boundary methods:
// CommittedBatchBoundary::batch_digest
// CommittedBatchBoundary::command_idempotency_key
// CommittedBatchBoundary::event_refs CommittedBatchBoundary::expected_revision
// CommittedBatchBoundary::intent_refs
// Filesystem methods:
// FileSystemStore::commit FileSystemStore::events FileSystemStore::head
// FileSystemStore::intents FileSystemStore::open
// FileSystemStore::read_checkpoint FileSystemStore::record_version
// FileSystemStore::replay FileSystemStore::schema_version
// FileSystemStore::storage_root FileSystemStore::workspace_root
// FileSystemStore::write_checkpoint
// Guarded filesystem methods:
// FileSystemGuardedStore::commit FileSystemGuardedStore::events
// FileSystemGuardedStore::guarded_commit FileSystemGuardedStore::head
// FileSystemGuardedStore::intents FileSystemGuardedStore::mutation_store
// FileSystemGuardedStore::new FileSystemGuardedStore::read_checkpoint
// FileSystemGuardedStore::replay FileSystemGuardedStore::write_checkpoint
// FileSystemStore::guarded_commit
// Guarded request and conflict methods:
// GuardConflictReceipt::actual_head_digest GuardConflictReceipt::actual_replay_digest
// GuardConflictReceipt::actual_revision GuardConflictReceipt::canonical_bytes
// GuardConflictReceipt::command_idempotency_key GuardConflictReceipt::digest
// GuardConflictReceipt::expected_head_digest GuardConflictReceipt::expected_replay_digest
// GuardConflictReceipt::expected_revision GuardConflictReceipt::guard_workflow
// GuardConflictReceipt::mutation_workflow GuardConflictReceipt::request_digest
// GuardConflictReceipt::validate_current
// GuardedCommitRequest::canonical_bytes GuardedCommitRequest::digest
// GuardedCommitRequest::guards GuardedCommitRequest::mutation GuardedCommitRequest::new
// WorkflowHeadGuard::canonical_bytes WorkflowHeadGuard::expected_head_digest
// WorkflowHeadGuard::expected_replay_digest WorkflowHeadGuard::expected_revision
// WorkflowHeadGuard::new WorkflowHeadGuard::workflow
// Memory methods:
// MemoryStore::commit MemoryStore::events MemoryStore::head MemoryStore::intents
// MemoryStore::guarded_commit MemoryStore::new MemoryStore::read_checkpoint MemoryStore::record_version
// MemoryStore::replay MemoryStore::schema_version MemoryStore::write_checkpoint
// Intent methods:
// OutboxIntent::canonical_bytes OutboxIntent::causative_event
// OutboxIntent::evidence OutboxIntent::idempotency_key OutboxIntent::intent_ref
// OutboxIntent::new OutboxIntent::payload OutboxIntent::record_version
// OutboxIntent::schema_version OutboxIntent::workflow
// Replay methods:
// ReplayResult::checkpoint ReplayResult::committed_batches ReplayResult::events
// ReplayResult::head ReplayResult::verified_prefix
// ReplayResult::intents ReplayResult::record_version ReplayResult::replay_digest
// ReplayResult::schema_version ReplayResult::tail_events ReplayResult::workflow
// Event methods:
// WorkflowEvent::canonical_bytes WorkflowEvent::event_ref WorkflowEvent::evidence
// WorkflowEvent::idempotency_key WorkflowEvent::new WorkflowEvent::payload
// WorkflowEvent::previous_event_digest WorkflowEvent::record_version
// WorkflowEvent::revision WorkflowEvent::schema_version WorkflowEvent::sequence
// WorkflowEvent::workflow
// Head methods:
// WorkflowHead::event_count WorkflowHead::intent_count
// WorkflowHead::last_event_digest WorkflowHead::revision
// WorkflowHead::sequence WorkflowHead::workflow
