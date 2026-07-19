///|
/// A strict `major.minor.patch` version with canonical decimal components.
/// Leading zeroes, signs, missing components, and components above 999999999
/// are rejected.
pub struct Version {
  major : Int
  minor : Int
  patch : Int
  text : String
} derive(Eq, Compare, Debug)

///|
fn parse_version_component(
  component : StringView,
  field : String,
) -> Int raise ContractError {
  if component.is_empty() || (component.length() > 1 && component[0] == '0') {
    raise MalformedVersion(field~)
  }
  let mut value = 0
  for char in component {
    if !char.is_ascii_digit() {
      raise MalformedVersion(field~)
    }
    let digit = char.to_int() - '0'.to_int()
    if value > 99999999 || (value == 99999999 && digit > 9) {
      raise MalformedVersion(field~)
    }
    value = value * 10 + digit
  }
  value
}

///|
fn parse_version_named(
  input : String,
  field : String,
) -> Version raise ContractError {
  let parts = input.split(".").to_array()
  if parts.length() != 3 {
    raise MalformedVersion(field~)
  }
  let major = parse_version_component(parts[0], field)
  let minor = parse_version_component(parts[1], field)
  let patch = parse_version_component(parts[2], field)
  let text = "\{major}.\{minor}.\{patch}"
  if text != input {
    raise MalformedVersion(field~)
  }
  { major, minor, patch, text }
}

///|
pub fn Version::parse(input : String) -> Version raise ContractError {
  parse_version_named(input, "version")
}

///|
pub fn Version::major(self : Version) -> Int {
  self.major
}

///|
pub fn Version::minor(self : Version) -> Int {
  self.minor
}

///|
pub fn Version::patch(self : Version) -> Int {
  self.patch
}

///|
pub fn Version::text(self : Version) -> String {
  self.text
}

///|
/// An immutable, ascending, duplicate-free supported-version snapshot.
pub struct VersionProfile {
  versions : ReadOnlyArray[Version]
} derive(Eq, Debug)

///|
pub fn VersionProfile::new(
  values : Array[String],
) -> VersionProfile raise ContractError {
  if values.is_empty() {
    raise InvalidVersionProfile
  }
  let parsed = values.map(value => {
    parse_version_named(value, "supported_version")
  })
  parsed.sort()
  let normalized : Array[Version] = []
  for version in parsed {
    if normalized.last() != Some(version) {
      normalized.push(version)
    }
  }
  { versions: ReadOnlyArray::from_array(normalized) }
}

///|
pub fn VersionProfile::versions(
  self : VersionProfile,
) -> ReadOnlyArray[Version] {
  self.versions
}

///|
pub fn VersionProfile::supports(
  self : VersionProfile,
  version : Version,
) -> Bool {
  self.versions.contains(version)
}

///|
pub fn VersionProfile::require_supported(
  self : VersionProfile,
  version : Version,
) -> Unit raise ContractError {
  if !self.supports(version) {
    raise UnsupportedVersion(field="supported_version", version=version.text())
  }
}

///|
/// Select the highest exact version present in both normalized profiles.
pub fn negotiate_highest(
  offered : VersionProfile,
  remote : VersionProfile,
) -> Version raise ContractError {
  for index = offered.versions.length() - 1; index >= 0; index = index - 1 {
    let candidate = offered.versions[index]
    if remote.supports(candidate) {
      return candidate
    }
  }
  raise NoCommonVersion
}
