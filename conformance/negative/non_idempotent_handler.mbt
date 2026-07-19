///|
fn apply_event(projection : RunProjection, event : RuntimeEvent) -> Unit {
  projection.applied_events.push(event)
}
