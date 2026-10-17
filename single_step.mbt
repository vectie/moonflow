///|
/// A pack's durable attempt store can be workspace-wide, so the attempt identity
/// includes the run. The ordinary director's per-item identity is unchanged.
pub fn single_step_request_for_item(
  projection : RunProjection,
  item : RuntimeItem,
  input_digest : String,
  recorded_at : String,
) -> AdapterRequest raise {
  guard item.status == Ready &&
    item.requested_authority == "workspace-mutation" &&
    item.required_claim == "digital-artifact" else {
    fail(
      "single-step requires one ready digital item within the workspace-mutation ceiling; the owner verifier validates its operation",
    )
  }
  let request = director_request_for_item(
    projection, item, input_digest, recorded_at,
  )
  let tuple = "run:" +
    projection.run_id.length().to_string() +
    ":" +
    projection.run_id +
    "|item:" +
    item.work_item_id.length().to_string() +
    ":" +
    item.work_item_id +
    "|attempt:" +
    (item.attempt_count + 1).to_string()
  let identity = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(tuple)),
  )
  {
    ..request,
    request_id: "request-" + identity,
    attempt_id: "attempt-" + identity,
  }
}
