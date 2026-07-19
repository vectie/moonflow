///|
pub fn schedule() -> Unit {
  ()
}

///|
pub struct RetryPolicy {
  record_version : String
}

///|
pub struct Lease {
  record_version : String
}

///|
pub struct FencingToken {
  record_version : String
}
