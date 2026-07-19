///|
pub fn ordered_http_json_contract_version() -> String {
  "moonflow.ordered_http_json.v2"
}

///|
pub(all) struct OrderedJsonPostStep {
  field : String
  destination_url : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OrderedHttpJsonConfig {
  contract_version : String
  transfer_id : String
  source_url : String
  expected_source_digest : String
  max_response_bytes : Int
  max_attempts : Int
  retry_delay_ms : Int
  steps : Array[OrderedJsonPostStep]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OrderedHttpJsonStepReceipt {
  ordinal : Int
  field : String
  destination_url : String
  request_digest : String
  idempotency_key : String
  attempt_count : Int
  response_status : Int
  response_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OrderedHttpJsonReceipt {
  contract_version : String
  transfer_id : String
  source_url : String
  expected_source_digest : String
  source_status : Int
  source_response_digest : String
  max_attempts : Int
  retry_delay_ms : Int
  steps : Array[OrderedHttpJsonStepReceipt]
  receipt_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
fn digest(bytes : Bytes) -> String {
  @contracts.sha256_digest(bytes).text()
}

///|
fn allowed_key(key : String, allowed : ArrayView[String]) -> Bool {
  allowed.any(value => value == key)
}

///|
fn require_exact_keys(
  value : Json,
  allowed : ArrayView[String],
  label : String,
) -> Unit raise {
  guard value is Object(fields) else { fail("\{label} must be a JSON object") }
  for key, _ in fields {
    if !allowed_key(key, allowed) {
      fail("\{label} contains unsupported field: \{key}")
    }
  }
}

///|
fn url_is_credential_free(value : String) -> Bool {
  let supported = value.has_prefix("http://") || value.has_prefix("https://")
  guard supported && !value.contains("?") && !value.contains("#") else {
    return false
  }
  let scheme_end = value.find("://").unwrap_or(0) + 3
  let authority_and_path = value[scheme_end:]
  let authority = match authority_and_path.find("/") {
    Some(index) => authority_and_path[:index]
    None => authority_and_path
  }
  !authority.is_blank() && !authority.contains("@")
}

///|
pub fn decode_ordered_http_json_config(
  value : Json,
) -> OrderedHttpJsonConfig raise {
  require_exact_keys(
    value,
    [
      "contract_version", "transfer_id", "source_url", "expected_source_digest",
      "max_response_bytes", "max_attempts", "retry_delay_ms", "steps",
    ],
    "transport config",
  )
  let config : OrderedHttpJsonConfig = @json.from_json(value)
  guard config.contract_version == ordered_http_json_contract_version() else {
    fail("unsupported ordered HTTP JSON contract")
  }
  guard !config.transfer_id.is_blank() else { fail("transfer_id is required") }
  guard url_is_credential_free(config.source_url) else {
    fail(
      "source_url must be an absolute credential-free HTTP(S) URL without query or fragment",
    )
  }
  ignore(@contracts.ContentDigest::parse(config.expected_source_digest))
  guard config.max_response_bytes is (1..=16777216) else {
    fail("max_response_bytes must be between 1 and 16777216")
  }
  guard config.max_attempts is (1..=10) else {
    fail("max_attempts must be between 1 and 10")
  }
  guard config.retry_delay_ms is (0..=60000) else {
    fail("retry_delay_ms must be between 0 and 60000")
  }
  guard config.steps.length() is (1..=32) else {
    fail("steps must contain between 1 and 32 ordered entries")
  }
  let seen : Array[String] = []
  guard value is Object(fields) && fields.get("steps") is Some(Array(raw_steps)) else {
    fail("steps must be an array")
  }
  for index, step in config.steps {
    require_exact_keys(raw_steps[index], ["field", "destination_url"], "step")
    guard !step.field.is_blank() else { fail("step field is required") }
    guard !seen.contains(step.field) else {
      fail("step fields must be unique: \{step.field}")
    }
    guard url_is_credential_free(step.destination_url) else {
      fail(
        "destination_url must be an absolute credential-free HTTP(S) URL without query or fragment",
      )
    }
    seen.push(step.field)
  }
  config
}

///|
async fn read_limited(client : @http.Client, ceiling : Int) -> Bytes {
  let buffer = FixedArray::make(ceiling + 1, b'0')
  let mut received = 0
  while received <= ceiling {
    let count = client.read(
      buffer,
      offset=received,
      max_len=ceiling + 1 - received,
    )
    if count == 0 {
      return buffer.unsafe_reinterpret_as_bytes()[:received].to_owned()
    }
    received += count
  }
  fail("HTTP response exceeds configured byte ceiling")
}

///|
fn json_signals_error(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  match fields.get("error") {
    Some(Null) | None => ()
    Some(_) => return true
  }
  match fields.get("errors") {
    Some(Array(values)) if !values.is_empty() => return true
    Some(String(value)) if !value.is_blank() => return true
    Some(Object(values)) if !values.is_empty() => return true
    _ => ()
  }
  for field in ["ok", "success", "accepted"] {
    match fields.get(field) {
      Some(False) => return true
      _ => ()
    }
  }
  false
}

///|
fn decode_success_body(
  bytes : Bytes,
  status : Int,
  label : String,
) -> Json raise {
  guard status is (200..=299) else { fail("\{label} returned HTTP \{status}") }
  let text = @utf8.decode(bytes) catch {
    _ => fail("\{label} response is not UTF-8 JSON")
  }
  let value = @json.parse(text) catch {
    _ => fail("\{label} response is not valid JSON")
  }
  guard !json_signals_error(value) else {
    fail("\{label} response contains a generic error signal")
  }
  value
}

///|
async fn get_json(url : String, ceiling : Int) -> (Int, Bytes, Json) {
  let (response, client) = @http.get_stream(url, headers={
    "Accept": "application/json",
    "Connection": "close",
  })
  defer client.close()
  let body = read_limited(client, ceiling)
  let value = decode_success_body(body, response.code, "source GET")
  (response.code, body, value)
}

///|
async fn post_json(
  url : String,
  body : Bytes,
  ceiling : Int,
  idempotency_key : String,
) -> (Int, Bytes, Json) {
  let client = @http.post_stream(url, headers={
    "Accept": "application/json",
    "Content-Type": "application/json",
    "Idempotency-Key": idempotency_key,
    "Connection": "close",
  })
  defer client.close()
  client.write(body)
  let response = client.end_request()
  let response_body = read_limited(client, ceiling)
  let value = decode_success_body(
    response_body,
    response.code,
    "destination POST",
  )
  (response.code, response_body, value)
}

///|
fn step_idempotency_key(
  transfer_id : String,
  ordinal : Int,
  field : String,
  destination_url : String,
  request_digest : String,
) -> String {
  let material : Json = {
    "contract_version": ordered_http_json_contract_version(),
    "transfer_id": transfer_id,
    "ordinal": ordinal,
    "field": field,
    "destination_url": destination_url,
    "request_digest": request_digest,
  }
  digest(@utf8.encode(material.stringify()))
}

///|
async fn post_json_with_retry(
  url : String,
  body : Bytes,
  ceiling : Int,
  idempotency_key : String,
  max_attempts : Int,
  retry_delay_ms : Int,
) -> (Int, Bytes, Json, Int) {
  let mut attempt_count = 1
  for ;; {
    try post_json(url, body, ceiling, idempotency_key) catch {
      err => {
        if attempt_count >= max_attempts {
          raise err
        }
        if retry_delay_ms > 0 {
          @async.sleep(retry_delay_ms)
        }
        attempt_count += 1
      }
    } noraise {
      (status, response_body, response_json) =>
        return (status, response_body, response_json, attempt_count)
    }
  }
}

///|
fn receipt_core(
  transfer_id : String,
  source_url : String,
  expected_source_digest : String,
  source_status : Int,
  source_response_digest : String,
  max_attempts : Int,
  retry_delay_ms : Int,
  steps : Array[OrderedHttpJsonStepReceipt],
) -> Json {
  {
    "contract_version": ordered_http_json_contract_version(),
    "transfer_id": transfer_id,
    "source_url": source_url,
    "expected_source_digest": expected_source_digest,
    "source_status": source_status,
    "source_response_digest": source_response_digest,
    "max_attempts": max_attempts,
    "retry_delay_ms": retry_delay_ms,
    "steps": steps.to_json(),
  }
}

///|
fn build_receipt(
  config : OrderedHttpJsonConfig,
  source_status : Int,
  source_body : Bytes,
  steps : Array[OrderedHttpJsonStepReceipt],
) -> OrderedHttpJsonReceipt {
  let source_response_digest = digest(source_body)
  let core = receipt_core(
    config.transfer_id,
    config.source_url,
    config.expected_source_digest,
    source_status,
    source_response_digest,
    config.max_attempts,
    config.retry_delay_ms,
    steps,
  )
  {
    contract_version: ordered_http_json_contract_version(),
    transfer_id: config.transfer_id,
    source_url: config.source_url,
    expected_source_digest: config.expected_source_digest,
    source_status,
    source_response_digest,
    max_attempts: config.max_attempts,
    retry_delay_ms: config.retry_delay_ms,
    steps,
    receipt_digest: digest(@utf8.encode(core.stringify())),
  }
}

///|
pub fn OrderedHttpJsonReceipt::canonical_json(
  self : OrderedHttpJsonReceipt,
) -> String {
  self.to_json().stringify()
}

///|
pub fn OrderedHttpJsonReceipt::valid(self : OrderedHttpJsonReceipt) -> Bool {
  self.contract_version == ordered_http_json_contract_version() &&
  self.receipt_digest ==
  digest(
    @utf8.encode(
      receipt_core(
        self.transfer_id,
        self.source_url,
        self.expected_source_digest,
        self.source_status,
        self.source_response_digest,
        self.max_attempts,
        self.retry_delay_ms,
        self.steps,
      ).stringify(),
    ),
  )
}

///|
pub async fn execute_ordered_http_json(
  config : OrderedHttpJsonConfig,
) -> OrderedHttpJsonReceipt {
  let (source_status, source_body, bundle) = get_json(
    config.source_url,
    config.max_response_bytes,
  )
  let source_response_digest = digest(source_body)
  guard source_response_digest == config.expected_source_digest else {
    fail(
      "source GET digest does not match expected_source_digest: expected " +
      "\{config.expected_source_digest}, observed \{source_response_digest}",
    )
  }
  guard bundle is Object(fields) else {
    fail("source bundle must be a top-level JSON object")
  }
  let receipts : Array[OrderedHttpJsonStepReceipt] = []
  for ordinal, step in config.steps {
    guard fields.get(step.field) is Some(selected) else {
      fail("source bundle is missing configured top-level field: \{step.field}")
    }
    let request_body = @utf8.encode(selected.stringify())
    let request_digest = digest(request_body)
    let idempotency_key = step_idempotency_key(
      config.transfer_id,
      ordinal,
      step.field,
      step.destination_url,
      request_digest,
    )
    let (response_status, response_body, _, attempt_count) = post_json_with_retry(
      step.destination_url,
      request_body,
      config.max_response_bytes,
      idempotency_key,
      config.max_attempts,
      config.retry_delay_ms,
    )
    receipts.push({
      ordinal,
      field: step.field,
      destination_url: step.destination_url,
      request_digest,
      idempotency_key,
      attempt_count,
      response_status,
      response_digest: digest(response_body),
    })
  }
  build_receipt(config, source_status, source_body, receipts)
}
