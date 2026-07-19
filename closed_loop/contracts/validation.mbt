///|
fn require_text(
  value : String,
  reference : String,
  field : String,
) -> Unit raise ContractError {
  let trimmed = value.trim()
  if trimmed.is_empty() ||
    trimmed.length() != value.length() ||
    has_control(value) {
    raise InvalidReferenceField(reference~, field~)
  }
}

///|
fn require_optional_text(
  value : String?,
  reference : String,
  field : String,
) -> Unit raise ContractError {
  match value {
    Some(value) => require_text(value, reference, field)
    None => ()
  }
}

///|
fn has_control(value : String) -> Bool {
  value.iter().any(char => char.is_control())
}

///|
fn require_locator(
  value : String,
  reference : String,
) -> Unit raise ContractError {
  require_text(value, reference, "locator")
  let lowered = value.to_lower()
  if has_control(value) ||
    value.contains("\\") ||
    value.contains("?") ||
    value.contains("#") ||
    value.contains("@") ||
    lowered.contains("password=") ||
    lowered.contains("token=") ||
    lowered.contains("api_key=") {
    raise InvalidReferenceField(reference~, field="locator")
  }
  for segment in value.split("/") {
    if segment == ".." {
      raise InvalidReferenceField(reference~, field="locator")
    }
  }
}

///|
fn require_media_type(
  value : String,
  reference : String,
) -> Unit raise ContractError {
  require_text(value, reference, "media_type")
  guard value.split_once("/") is Some((family, subtype)) else {
    raise InvalidReferenceField(reference~, field="media_type")
  }
  if family.is_empty() || subtype.is_empty() || value.contains(" ") {
    raise InvalidReferenceField(reference~, field="media_type")
  }
}
