///|
fn acceptance_review_event(
  projection : RunProjection,
  receipt : AcceptanceReviewReceipt,
) -> RuntimeEvent {
  { ..projection.applied_events[0], detail: receipt.review_id }
}
