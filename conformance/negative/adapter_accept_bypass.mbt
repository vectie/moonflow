///|
fn import_result(status : String, item : RuntimeItem) -> Unit {
  match status {
    "succeeded" => item.status = Accepted
    _ => ()
  }
}
