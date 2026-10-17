///|
priv struct MermaidJsonReader {
  chars : Array[Char]
  mut position : Int
}

///|
fn MermaidJsonReader::space(self : MermaidJsonReader) -> Unit {
  while self.position < self.chars.length() &&
        [' ', '\t', '\r', '\n'].contains(self.chars[self.position]) {
    self.position += 1
  }
}

///|
fn MermaidJsonReader::string(self : MermaidJsonReader) -> String raise {
  let token = StringBuilder()
  token.write_char('"')
  self.position += 1
  while self.position < self.chars.length() {
    let ch = self.chars[self.position]
    token.write_char(ch)
    self.position += 1
    if ch == '\\' {
      token.write_char(self.chars[self.position])
      self.position += 1
    } else if ch == '"' {
      break
    }
  }
  guard @json.parse(token.to_string()) is String(value) else {
    fail("Mermaid invalid JSON string")
  }
  value
}

///|
// Syntax, Unicode and depth are checked first by the standard JSON parser.
// This second pass preserves numeric spellings and refuses decoded duplicates
// before any binding or integer conversion can discard that information.
fn MermaidJsonReader::value(self : MermaidJsonReader) -> Json raise {
  self.space()
  match self.chars[self.position] {
    '{' => {
      self.position += 1
      self.space()
      let fields : Map[String, Json] = Map([])
      if self.chars[self.position] != '}' {
        while true {
          let key = self.string()
          guard !fields.contains(key) else {
            fail("Mermaid JSON has duplicate decoded object key: \{key}")
          }
          self.space()
          self.position += 1
          fields[key] = self.value()
          self.space()
          if self.chars[self.position] == '}' {
            break
          }
          self.position += 1
          self.space()
        }
      }
      self.position += 1
      Json::object(fields)
    }
    '[' => {
      self.position += 1
      self.space()
      let values : Array[Json] = []
      if self.chars[self.position] != ']' {
        while true {
          values.push(self.value())
          self.space()
          if self.chars[self.position] == ']' {
            break
          }
          self.position += 1
        }
      }
      self.position += 1
      Json::array(values)
    }
    '"' => Json::string(self.string())
    _ => {
      let token = StringBuilder()
      while self.position < self.chars.length() &&
            ![' ', '\t', '\r', '\n', ',', '}', ']'].contains(
              self.chars[self.position],
            ) {
        token.write_char(self.chars[self.position])
        self.position += 1
      }
      let spelling = token.to_string()
      match @json.parse(spelling) {
        Number(n, ..) => Json::number(n, repr=spelling)
        value => value
      }
    }
  }
}

///|
fn mermaid_parse_json(text : String) -> Json raise {
  ignore(@json.parse(text, max_nesting_depth=64))
  let reader : MermaidJsonReader = {
    chars: text.iter().collect(),
    position: 0,
  }
  reader.value()
}

///|
// The caller supplies a syntax-validated numeric token. Remove coefficient
// zeros and apply its exact decimal exponent; no floating rounding is used.
fn mermaid_exact_integer(spelling : String) -> Int64? {
  let chars = spelling.iter().collect()
  let negative = chars[0] == '-'
  let digits : Array[Int] = []
  let mut fraction = 0
  let mut point = false
  let mut cursor = if negative { 1 } else { 0 }
  while cursor < chars.length() && chars[cursor] != 'e' && chars[cursor] != 'E' {
    if chars[cursor] == '.' {
      point = true
    } else {
      digits.push(chars[cursor].to_int() - 48)
      if point {
        fraction += 1
      }
    }
    cursor += 1
  }
  let mut exponent = 0
  let mut negative_exponent = false
  if cursor < chars.length() {
    cursor += 1
    if chars[cursor] == '-' || chars[cursor] == '+' {
      negative_exponent = chars[cursor] == '-'
      cursor += 1
    }
    let cap = chars.length() + 32
    while cursor < chars.length() {
      exponent = (exponent * 10 + chars[cursor].to_int() - 48).min(cap)
      cursor += 1
    }
  }
  if negative_exponent {
    exponent = -exponent
  }
  let mut first = 0
  while first < digits.length() && digits[first] == 0 {
    first += 1
  }
  if first == digits.length() {
    return Some(0L)
  }
  let mut end = digits.length()
  while digits[end - 1] == 0 {
    end -= 1
  }
  let power = exponent - fraction + digits.length() - end
  if power < 0 || end - first + power > 8 {
    return None
  }
  let mut value = 0L
  for i in first..<end {
    value = value * 10L + digits[i].to_int64()
  }
  for _ in 0..<power {
    value *= 10L
  }
  Some(if negative { -value } else { value })
}

///|
fn mermaid_timeout(value : Json, label : String) -> Int raise {
  guard value is Number(number, repr~) else {
    fail("\{label}: timeout_ms must be a whole number in 1..86400000")
  }
  let spelling = repr.unwrap_or(number.to_string())
  guard spelling.length() <= 1048576 &&
    (@json.parse(spelling) catch { _ => Json::null() }) is Number(parsed, ..) &&
    parsed == number else {
    fail("\{label}: invalid numeric spelling")
  }
  guard mermaid_exact_integer(spelling) is Some(exact) &&
    exact >= 1L &&
    exact <= 86400000L else {
    fail("\{label}: timeout_ms must be an exact whole number in 1..86400000")
  }
  exact.to_int()
}

///|
/// Import original JSON texts without erasing duplicate keys or decimal tokens.
/// Prefer this entrypoint for file/API input; the Json entrypoint cannot recover
/// information already discarded by a caller's parser.
pub fn declared_plan_from_mermaid_text_v1(
  source_text : String,
  bindings_text : String,
  diagram : String,
  draft_id : String,
  recorded_at : String,
) -> MermaidPlanImportV1 raise {
  guard @utf8.encode(source_text).length() +
    @utf8.encode(bindings_text).length() +
    @utf8.encode(diagram).length() <=
    2097152 else {
    fail("Mermaid input exceeds 2,097,152 aggregate UTF-8 bytes")
  }
  declared_plan_from_mermaid_v1(
    mermaid_parse_json(source_text),
    mermaid_parse_json(bindings_text),
    diagram,
    draft_id,
    recorded_at,
  )
}
