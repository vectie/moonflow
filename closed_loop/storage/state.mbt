///|
fn workflow_batches(
  batches : Array[StoredBatch],
  workflow : @contracts.RecordRef,
) -> Array[StoredBatch] {
  let selected = batches.filter(batch => {
    exact_record_equal(batch.request.workflow, workflow)
  })
  selected.sort_by((left, right) => {
    left.result.first_sequence.compare(right.result.first_sequence)
  })
  selected
}

///|
fn all_events(batches : Array[StoredBatch]) -> Array[WorkflowEvent] {
  let values : Array[WorkflowEvent] = []
  for batch in batches {
    for event in batch.request.events {
      values.push(event)
    }
  }
  values
}

///|
fn all_intents(batches : Array[StoredBatch]) -> Array[OutboxIntent] {
  let values : Array[OutboxIntent] = []
  for batch in batches {
    for intent in batch.request.intents {
      values.push(intent)
    }
  }
  values
}

///|
fn find_event(
  events : Array[WorkflowEvent],
  reference : @contracts.RecordRef,
) -> WorkflowEvent? {
  events
  .search_by(event => exact_record_equal(event.event_ref, reference))
  .map(index => events[index])
}

///|
fn validate_global_uniqueness(
  batches : Array[StoredBatch],
) -> Unit raise StorageError {
  for batch_index, batch in batches {
    for prior_index in 0..<batch_index {
      let prior_batch = batches[prior_index]
      if batch.request.command_idempotency_key ==
        prior_batch.request.command_idempotency_key {
        raise IdempotencyConflict(key=batch.request.command_idempotency_key)
      }
    }
  }
  let events = all_events(batches)
  for index, event in events {
    for prior_index in 0..<index {
      let prior = events[prior_index]
      if record_identity_equal(prior.event_ref, event.event_ref) {
        raise IdentityConflict(
          kind=event.event_ref.kind(),
          id=event.event_ref.id(),
          version=event.event_ref.version().text(),
        )
      }
      if prior.idempotency_key == event.idempotency_key {
        raise IdempotencyConflict(key=event.idempotency_key)
      }
    }
  }
  let intents = all_intents(batches)
  for index, intent in intents {
    for prior_index in 0..<index {
      let prior = intents[prior_index]
      if record_identity_equal(prior.intent_ref, intent.intent_ref) {
        raise IdentityConflict(
          kind=intent.intent_ref.kind(),
          id=intent.intent_ref.id(),
          version=intent.intent_ref.version().text(),
        )
      }
      if prior.idempotency_key == intent.idempotency_key {
        raise IdempotencyConflict(key=intent.idempotency_key)
      }
    }
  }
}

///|
fn validate_workflow_history(
  batches : Array[StoredBatch],
  workflow : @contracts.RecordRef,
) -> Unit raise StorageError {
  let selected = workflow_batches(batches, workflow)
  let mut expected_sequence = 1L
  let mut expected_revision = 1L
  let mut previous_digest : @contracts.ContentDigest? = None
  let mut event_count = 0L
  let mut intent_count = 0L
  let accepted_events : Array[WorkflowEvent] = []
  for batch in selected {
    if batch.request.expected_revision != expected_revision - 1L {
      raise RevisionGap(
        workflow_id=workflow.id(),
        expected=expected_revision - 1L,
        actual=batch.request.expected_revision,
      )
    }
    for event in batch.request.events {
      if event.sequence != expected_sequence {
        raise SequenceGap(
          workflow_id=workflow.id(),
          expected=expected_sequence,
          actual=event.sequence,
        )
      }
      if event.revision != expected_revision {
        raise RevisionGap(
          workflow_id=workflow.id(),
          expected=expected_revision,
          actual=event.revision,
        )
      }
      if event.previous_event_digest != previous_digest {
        raise DigestMismatch(
          record_kind="workflow_event_chain",
          record_id=event.event_ref.id(),
          expected=previous_digest.map(value => value.text()).unwrap_or("none"),
          actual=event.previous_event_digest
            .map(value => value.text())
            .unwrap_or("none"),
        )
      }
      accepted_events.push(event)
      previous_digest = Some(event.event_ref.digest())
      expected_sequence += 1L
      expected_revision += 1L
      event_count += 1L
    }
    for intent in batch.request.intents {
      if find_event(accepted_events, intent.causative_event) is None {
        raise ValidationFailure(field="causative_event_binding")
      }
      intent_count += 1L
    }
    if batch.result.event_count != event_count ||
      batch.result.intent_count != intent_count ||
      batch.result.last_sequence != expected_sequence - 1L ||
      batch.result.workflow_revision != expected_revision - 1L ||
      Some(batch.result.last_event_digest) != previous_digest {
      raise ValidationFailure(field="commit_result_cardinality")
    }
  }
}

///|
fn validate_batches(batches : Array[StoredBatch]) -> Unit raise StorageError {
  validate_global_uniqueness(batches)
  let workflows : Array[@contracts.RecordRef] = []
  for batch in batches {
    if !workflows.any(value => exact_record_equal(value, batch.request.workflow)) {
      workflows.push(batch.request.workflow)
    }
  }
  for workflow in workflows {
    validate_workflow_history(batches, workflow)
  }
}

///|
fn head_from_batches(
  batches : Array[StoredBatch],
  workflow : @contracts.RecordRef,
) -> WorkflowHead raise StorageError {
  validate_batches(batches)
  let selected = workflow_batches(batches, workflow)
  match selected.last() {
    None =>
      {
        workflow,
        sequence: 0L,
        revision: 0L,
        last_event_digest: None,
        event_count: 0L,
        intent_count: 0L,
      }
    Some(batch) =>
      {
        workflow,
        sequence: batch.result.last_sequence,
        revision: batch.result.workflow_revision,
        last_event_digest: Some(batch.result.last_event_digest),
        event_count: batch.result.event_count,
        intent_count: batch.result.intent_count,
      }
  }
}

///|
fn events_from_batches(
  batches : Array[StoredBatch],
  workflow : @contracts.RecordRef,
) -> Array[WorkflowEvent] raise StorageError {
  validate_batches(batches)
  let values : Array[WorkflowEvent] = []
  for batch in workflow_batches(batches, workflow) {
    for event in batch.request.events {
      values.push(event)
    }
  }
  values
}

///|
fn intents_from_batches(
  batches : Array[StoredBatch],
  workflow : @contracts.RecordRef,
) -> Array[OutboxIntent] raise StorageError {
  validate_batches(batches)
  let values : Array[OutboxIntent] = []
  for batch in workflow_batches(batches, workflow) {
    for intent in batch.request.intents {
      values.push(intent)
    }
  }
  values
}

///|
fn find_command_batch(
  batches : Array[StoredBatch],
  key : String,
) -> StoredBatch? {
  batches
  .search_by(batch => batch.request.command_idempotency_key == key)
  .map(index => batches[index])
}

///|
fn check_new_record_conflicts(
  batches : Array[StoredBatch],
  request : CommitRequest,
) -> Unit raise StorageError {
  let existing_events = all_events(batches)
  for incoming in request.events {
    for existing in existing_events {
      if record_identity_equal(existing.event_ref, incoming.event_ref) {
        raise IdentityConflict(
          kind=incoming.event_ref.kind(),
          id=incoming.event_ref.id(),
          version=incoming.event_ref.version().text(),
        )
      }
      if existing.idempotency_key == incoming.idempotency_key {
        raise IdempotencyConflict(key=incoming.idempotency_key)
      }
    }
  }
  let existing_intents = all_intents(batches)
  for incoming in request.intents {
    for existing in existing_intents {
      if record_identity_equal(existing.intent_ref, incoming.intent_ref) {
        raise IdentityConflict(
          kind=incoming.intent_ref.kind(),
          id=incoming.intent_ref.id(),
          version=incoming.intent_ref.version().text(),
        )
      }
      if existing.idempotency_key == incoming.idempotency_key {
        raise IdempotencyConflict(key=incoming.idempotency_key)
      }
    }
  }
}

///|
fn prepare_commit(
  batches : Array[StoredBatch],
  request : CommitRequest,
) -> (StoredBatch?, StoredBatch?) raise StorageError {
  validate_batches(batches)
  // Genuine retries are classified before the optimistic revision check.
  match find_command_batch(batches, request.command_idempotency_key) {
    Some(existing) => {
      if existing.request == request {
        return (Some(existing), None)
      }
      raise IdempotencyConflict(key=request.command_idempotency_key)
    }
    None => ()
  }
  let head = head_from_batches(batches, request.workflow)
  if request.expected_revision != head.revision {
    raise OptimisticRevisionConflict(
      workflow_id=request.workflow.id(),
      expected=request.expected_revision,
      actual=head.revision,
    )
  }
  let first = request.events[0]
  if first.sequence != head.sequence + 1L {
    raise SequenceGap(
      workflow_id=request.workflow.id(),
      expected=head.sequence + 1L,
      actual=first.sequence,
    )
  }
  if first.revision != head.revision + 1L {
    raise RevisionGap(
      workflow_id=request.workflow.id(),
      expected=head.revision + 1L,
      actual=first.revision,
    )
  }
  if first.previous_event_digest != head.last_event_digest {
    raise DigestMismatch(
      record_kind="workflow_event_chain",
      record_id=first.event_ref.id(),
      expected=head.last_event_digest
        .map(value => value.text())
        .unwrap_or("none"),
      actual=first.previous_event_digest
        .map(value => value.text())
        .unwrap_or("none"),
    )
  }
  check_new_record_conflicts(batches, request)
  let available_events = all_events(batches)
  for event in request.events {
    available_events.push(event)
  }
  for intent in request.intents {
    if find_event(available_events, intent.causative_event) is None {
      raise ValidationFailure(field="causative_event_binding")
    }
  }
  let batch = make_stored_batch(
    request,
    head.event_count + request.events.length().to_int64(),
    head.intent_count + request.intents.length().to_int64(),
  )
  (None, Some(batch))
}

///|
fn checkpoint_is_valid(
  checkpoint : CheckpointRecord,
  workflow : @contracts.RecordRef,
  events : Array[WorkflowEvent],
) -> Bool {
  if !exact_record_equal(checkpoint.workflow, workflow) {
    return false
  }
  if checkpoint.event_sequence == 0L {
    return checkpoint.workflow_revision == 0L &&
      checkpoint.last_event_digest is None
  }
  match events.search_by(event => event.sequence == checkpoint.event_sequence) {
    None => false
    Some(index) => {
      let event = events[index]
      event.revision == checkpoint.workflow_revision &&
      checkpoint.last_event_digest == Some(event.event_ref.digest())
    }
  }
}

///|
fn latest_valid_checkpoint(
  checkpoints : Array[CheckpointRecord],
  workflow : @contracts.RecordRef,
  events : Array[WorkflowEvent],
) -> CheckpointRecord? {
  let candidates = checkpoints.filter(value => {
    exact_record_equal(value.workflow, workflow)
  })
  candidates.sort_by((left, right) => {
    let boundary = right.event_sequence.compare(left.event_sequence)
    if boundary != 0 {
      boundary
    } else {
      left.checkpoint_ref.digest().compare(right.checkpoint_ref.digest())
    }
  })
  candidates
  .search_by(value => checkpoint_is_valid(value, workflow, events))
  .map(index => candidates[index])
}

///|
fn replay_digest_for(
  workflow : @contracts.RecordRef,
  events : Array[WorkflowEvent],
) -> @contracts.ContentDigest {
  let writer = StorageWriter::new()
  try! writer.write_string("1.0.0")
  try! writer.write_bytes(encode_record_ref(workflow, false))
  try! writer.write_count(events.length())
  for event in events {
    try! writer.write_bytes(event.canonical_bytes())
  }
  @contracts.sha256_digest(writer.finish())
}

///|
/// Returns the authoritative replay digest for a verified empty workflow.
/// This keeps genesis authorities coupled to the storage-owned replay codec.
pub fn empty_replay_digest(
  workflow : @contracts.RecordRef,
) -> @contracts.ContentDigest {
  replay_digest_for(workflow, [])
}

///|
fn replay_from_state(
  batches : Array[StoredBatch],
  checkpoints : Array[CheckpointRecord],
  workflow : @contracts.RecordRef,
) -> ReplayResult raise StorageError {
  let events = events_from_batches(batches, workflow)
  let intents = intents_from_batches(batches, workflow)
  let committed_batches = workflow_batches(batches, workflow).map(batch => {
    committed_batch_boundary(batch)
  })
  let checkpoint = latest_valid_checkpoint(checkpoints, workflow, events)
  let boundary = checkpoint.map(value => value.event_sequence).unwrap_or(0L)
  let tail = events.filter(event => event.sequence > boundary)
  {
    record_version: storage_version("1.0.0", "replay_result"),
    schema_version: storage_version("1.0.0", "replay_result_schema"),
    workflow,
    events: ReadOnlyArray::from_array(events),
    intents: ReadOnlyArray::from_array(intents),
    committed_batches: ReadOnlyArray::from_array(committed_batches),
    checkpoint,
    tail_events: ReadOnlyArray::from_array(tail),
    head: head_from_batches(batches, workflow),
    replay_digest: replay_digest_for(workflow, events),
  }
}
