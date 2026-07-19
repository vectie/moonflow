///|
/// A parsed, credential-free HTTP(S) target used by the ordered transport.
/// The package keeps this private so the public v2 contract does not change.
priv struct FixedHttpTarget {
  secure : Bool
  host : String
  authority : String
  port : Int
  path : String
}

///|
priv struct FixedHttpResponse {
  code : Int
  body : Bytes
}

///|
let ordered_http_timeout_ms : Int = 30000

///|
let maximum_http_line_bytes : Int = 16384

///|
let maximum_http_header_count : Int = 128

///|
fn parse_port(value : String) -> Int raise {
  let port = @string.parse_int(value, base=10) catch {
    _ => fail("HTTP URL contains an invalid port")
  }
  guard port is (1..<65536) else { fail("HTTP URL port is out of range") }
  port
}

///|
fn parse_fixed_http_target(url : String) -> FixedHttpTarget raise {
  let (secure, default_port, remainder) = if url.has_prefix("http://") {
    (false, 80, url[7:])
  } else if url.has_prefix("https://") {
    (true, 443, url[8:])
  } else {
    fail("HTTP URL must use http or https")
  }
  let path_start = remainder.find("/").unwrap_or(remainder.length())
  let authority = remainder[:path_start].to_owned()
  let path = if path_start == remainder.length() {
    "/"
  } else {
    remainder[path_start:].to_owned()
  }
  guard !authority.is_blank() &&
    !authority.contains("@") &&
    !path.contains("\r") &&
    !path.contains("\n") &&
    !authority.contains("\r") &&
    !authority.contains("\n") else {
    fail("HTTP URL contains an unsafe authority or path")
  }
  let (host, port) = if authority.has_prefix("[") {
    guard authority.find("]") is Some(close) && close > 1 else {
      fail("HTTP URL contains an invalid IPv6 authority")
    }
    let host = authority[1:close].to_owned()
    let port = if close + 1 == authority.length() {
      default_port
    } else {
      guard authority[close + 1:close + 2] == ":" else {
        fail("HTTP URL contains an invalid IPv6 port separator")
      }
      parse_port(authority[close + 2:].to_owned())
    }
    (host, port)
  } else {
    match authority.find(":") {
      Some(colon) =>
        (
          authority[:colon].to_owned(),
          parse_port(authority[colon + 1:].to_owned()),
        )
      None => (authority, default_port)
    }
  }
  guard !host.is_blank() else { fail("HTTP URL host is required") }
  { secure, host, authority, port, path }
}

///|
async fn[R : @io.Reader] read_http_line(reader : R) -> String {
  let buffer = FixedArray::make(maximum_http_line_bytes + 2, b'0')
  let mut length = 0
  while length < buffer.length() {
    let count = reader.read(buffer, offset=length, max_len=1)
    guard count == 1 else { fail("HTTP connection closed during a line") }
    length += 1
    if length >= 2 && buffer[length - 2] == b'\r' && buffer[length - 1] == b'\n' {
      return @utf8.decode(
        buffer.unsafe_reinterpret_as_bytes()[:length - 2].to_owned(),
      ) catch {
        _ => fail("HTTP line is not UTF-8")
      }
    }
  }
  fail("HTTP line exceeds the line-size limit")
}

///|
async fn[R : @io.Reader] read_http_headers(reader : R) -> Map[String, String] {
  let headers : Map[String, String] = {}
  for index = 0; index < maximum_http_header_count; index = index + 1 {
    let line = read_http_line(reader)
    if line == "" {
      return headers
    }
    guard line.find(":") is Some(colon) && colon > 0 else {
      fail("HTTP response contains an invalid header")
    }
    let key = line[:colon].trim().to_lower().to_owned()
    let value = line[colon + 1:].trim().to_owned()
    match headers.get(key) {
      Some(existing) => headers[key] = existing + "," + value
      None => headers[key] = value
    }
  }
  fail("HTTP response contains too many headers")
}

///|
async fn[R : @io.Reader] read_exact_http_body(
  reader : R,
  length : Int,
  ceiling : Int,
) -> Bytes {
  guard length <= ceiling else {
    fail("HTTP response exceeds configured byte ceiling")
  }
  reader.read_exactly(length)
}

///|
async fn[R : @io.Reader] read_close_delimited_http_body(
  reader : R,
  ceiling : Int,
) -> Bytes {
  let buffer = FixedArray::make(ceiling + 1, b'0')
  let mut received = 0
  while received <= ceiling {
    let count = reader.read(
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
async fn[R : @io.Reader] read_chunked_http_body(
  reader : R,
  ceiling : Int,
) -> Bytes {
  let output = Buffer()
  let mut received = 0
  for ;; {
    let size_line = read_http_line(reader)
    let size_text = match size_line.find(";") {
      Some(index) => size_line[:index].trim().to_owned()
      None => size_line.trim().to_owned()
    }
    guard !size_text.is_blank() else { fail("HTTP chunk size is empty") }
    let size = @string.parse_int(size_text, base=16) catch {
      _ => fail("HTTP chunk size is invalid")
    }
    guard size >= 0 && received + size <= ceiling else {
      fail("HTTP response exceeds configured byte ceiling")
    }
    if size == 0 {
      for trailer_count = 0
          trailer_count < maximum_http_header_count
          trailer_count = trailer_count + 1 {
        let trailer = read_http_line(reader)
        if trailer == "" {
          return output.contents()
        }
      }
      fail("HTTP response contains too many chunk trailers")
    }
    output.write_bytes(reader.read_exactly(size))
    received += size
    guard reader.read_exactly(2) == b"\r\n" else {
      fail("HTTP chunk is missing its terminator")
    }
  }
}

///|
async fn[R : @io.Reader] read_fixed_http_response(
  reader : R,
  ceiling : Int,
) -> FixedHttpResponse {
  let status_line = read_http_line(reader)
  let parts = status_line.split(" ").to_array()
  guard parts.length() >= 2 &&
    (parts[0] == "HTTP/1.1" || parts[0] == "HTTP/1.0") else {
    fail("HTTP response contains an invalid status line")
  }
  let code = @string.parse_int(parts[1], base=10) catch {
    _ => fail("HTTP response contains an invalid status code")
  }
  let headers = read_http_headers(reader)
  let transfer_encoding = headers
    .get("transfer-encoding")
    .map(value => value.to_lower())
  let content_length = headers.get("content-length")
  guard !(transfer_encoding is Some(_) && content_length is Some(_)) else {
    fail("HTTP response contains conflicting body framing")
  }
  let body = match (transfer_encoding, content_length) {
    (Some(value), None) => {
      guard value == "chunked" else {
        fail("HTTP response uses an unsupported transfer encoding")
      }
      read_chunked_http_body(reader, ceiling)
    }
    (None, Some(value)) => {
      let length = @string.parse_int(value, base=10) catch {
        _ => fail("HTTP response contains an invalid Content-Length")
      }
      guard length >= 0 else {
        fail("HTTP response contains a negative Content-Length")
      }
      read_exact_http_body(reader, length, ceiling)
    }
    (None, None) =>
      if code is (100..=199) || code == 204 || code == 304 {
        b""
      } else {
        read_close_delimited_http_body(reader, ceiling)
      }
    (Some(_), Some(_)) =>
      fail("HTTP response contains conflicting body framing")
  }
  { code, body }
}

///|
async fn[R : @io.Reader + @io.Writer] exchange_fixed_http_json(
  connection : R,
  target : FixedHttpTarget,
  method_ : String,
  body : Bytes,
  ceiling : Int,
  idempotency_key : String?,
) -> FixedHttpResponse {
  let idempotency_header = match idempotency_key {
    Some(value) => "Idempotency-Key: " + value + "\r\n"
    None => ""
  }
  let headers = method_ +
    " " +
    target.path +
    " HTTP/1.1\r\n" +
    "Host: " +
    target.authority +
    "\r\n" +
    "Accept: application/json\r\n" +
    (if method_ == "POST" { "Content-Type: application/json\r\n" } else { "" }) +
    idempotency_header +
    "Content-Length: " +
    body.length().to_string() +
    "\r\n" +
    "Connection: close\r\n\r\n"
  connection.write(@utf8.encode(headers))
  if !body.is_empty() {
    connection.write(body)
  }
  read_fixed_http_response(connection, ceiling)
}

///|
async fn fixed_http_json_request(
  url : String,
  method_ : String,
  body : Bytes,
  ceiling : Int,
  idempotency_key : String?,
) -> FixedHttpResponse {
  let target = parse_fixed_http_target(url)
  @async.with_timeout(ordered_http_timeout_ms, () => {
    let tcp = @socket.Tcp::connect_to_host(target.host, port=target.port)
    if target.secure {
      let tls = @tls.Tls::client(tcp, host=target.host)
      defer tls.close()
      exchange_fixed_http_json(
        tls, target, method_, body, ceiling, idempotency_key,
      )
    } else {
      defer tcp.close()
      exchange_fixed_http_json(
        tcp, target, method_, body, ceiling, idempotency_key,
      )
    }
  })
}
