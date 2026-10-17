///|
async fn change_responsibility(
  workspace : String,
  run_id : String,
  change_path : String,
) -> Unit {
  let directory = run_dir(workspace, run_id)
  // This lock serializes responsibility writers, not unrelated older commands.
  // Existing runtime commands must not run concurrently with this operation.
  let lock = @flow_host.acquire_named_writer_lock_v1(
    directory, "responsibility",
  )
  defer @flow_host.release_named_writer_lock_v1(lock)
  let events = load_events(workspace, run_id)
  let original = events.copy()
  let projection = @moonflow.replay(run_id, events)
  let change = @moonflow.decode_responsibility_change_v1(read_json(change_path))
  let event = @moonflow.responsibility_event_v1(projection, change)
  if !projection.applied_event_ids.contains(event.event_id) {
    projection.apply(event)
    events.push(event)
    // Recheck the head immediately before the authoritative atomic replacement.
    let current = load_events(workspace, run_id)
    if current != original {
      fail("run changed while assigning responsibility")
    }
    @flow_host.atomic_replace_named_json_v1(
      directory,
      "events.json",
      @moonflow.event_array_json(events).stringify(indent=2),
    )
  }
  // Event store is authoritative. A retry also repairs an interrupted projection write.
  @flow_host.atomic_replace_named_json_v1(
    directory,
    "projection.json",
    @moonflow.projection_json(projection).stringify(indent=2),
  )
  println(@moonflow.projection_json(projection).stringify(indent=2))
}
