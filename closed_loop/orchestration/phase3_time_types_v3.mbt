///|
/// Canonical millisecond UTC instant used by Phase 3. Civil time and host
/// timezone settings never participate in replay decisions.
pub struct UtcInstantV3 {
  epoch_millis : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn UtcInstantV3::new(
  epoch_millis : Int64,
) -> UtcInstantV3 raise OrchestrationError {
  if epoch_millis < 0L {
    raise MalformedInput(field="utc_instant_v3_epoch_millis")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/UTC-INSTANT-V3/3.0.0")
  writer.string("3.0.0")
  writer.int64(epoch_millis)
  let canonical = writer.finish()
  { epoch_millis, canonical, digest: @contracts.sha256_digest(canonical) }
}

///|
pub fn UtcInstantV3::epoch_millis(self : UtcInstantV3) -> Int64 {
  self.epoch_millis
}

///|
pub fn UtcInstantV3::canonical_bytes(self : UtcInstantV3) -> Bytes {
  self.canonical
}

///|
pub fn UtcInstantV3::digest(self : UtcInstantV3) -> @contracts.ContentDigest {
  self.digest
}

///|
pub impl Eq for UtcInstantV3 with fn equal(left, right) {
  left.canonical == right.canonical
}

///|
fn phase3_is_leap_year(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn phase3_days_in_month(year : Int, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if phase3_is_leap_year(year) { 29 } else { 28 }
    _ => 0
  }
}

///|
fn phase3_days_from_civil(year : Int, month : Int, day : Int) -> Int64 {
  let y = year.to_int64() - (if month <= 2 { 1L } else { 0L })
  let era = y / 400L
  let yoe = y - era * 400L
  let m = month.to_int64()
  let shifted_month = m + (if month > 2 { -3L } else { 9L })
  let doy = (153L * shifted_month + 2L) / 5L + day.to_int64() - 1L
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy
  era * 146097L + doe - 719468L
}

///|
/// Explicit local civil boundary. The supported production range starts at
/// the Unix epoch so every resolved UTC value shares the existing non-negative
/// orchestration clock domain.
pub struct LocalCivilTimeV3 {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
  millisecond : Int
  local_epoch_millis : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn LocalCivilTimeV3::new(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
  millisecond : Int,
) -> LocalCivilTimeV3 raise OrchestrationError {
  if year < 1970 ||
    year > 9999 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > phase3_days_in_month(year, month) ||
    hour < 0 ||
    hour > 23 ||
    minute < 0 ||
    minute > 59 ||
    second < 0 ||
    second > 59 ||
    millisecond < 0 ||
    millisecond > 999 {
    raise MalformedInput(field="local_civil_time_v3")
  }
  let days = phase3_days_from_civil(year, month, day)
  let local_epoch_millis = days * 86400000L +
    hour.to_int64() * 3600000L +
    minute.to_int64() * 60000L +
    second.to_int64() * 1000L +
    millisecond.to_int64()
  if local_epoch_millis < 0L {
    raise MalformedInput(field="local_civil_time_v3_before_epoch")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/LOCAL-CIVIL-TIME-V3/3.0.0")
  writer.string("3.0.0")
  writer.int64(year.to_int64())
  writer.int64(month.to_int64())
  writer.int64(day.to_int64())
  writer.int64(hour.to_int64())
  writer.int64(minute.to_int64())
  writer.int64(second.to_int64())
  writer.int64(millisecond.to_int64())
  writer.int64(local_epoch_millis)
  let canonical = writer.finish()
  {
    year,
    month,
    day,
    hour,
    minute,
    second,
    millisecond,
    local_epoch_millis,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn LocalCivilTimeV3::local_epoch_millis(self : LocalCivilTimeV3) -> Int64 {
  self.local_epoch_millis
}

///|
pub fn LocalCivilTimeV3::canonical_bytes(self : LocalCivilTimeV3) -> Bytes {
  self.canonical
}

///|
pub fn LocalCivilTimeV3::digest(
  self : LocalCivilTimeV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// One half-open UTC period from an immutable timezone-rules snapshot.
pub struct TimeZonePeriodV3 {
  starts_at_utc_inclusive : Int64
  ends_at_utc_exclusive : Int64?
  offset_seconds : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn TimeZonePeriodV3::new(
  starts_at_utc_inclusive : Int64,
  ends_at_utc_exclusive : Int64?,
  offset_seconds : Int64,
) -> TimeZonePeriodV3 raise OrchestrationError {
  if starts_at_utc_inclusive < 0L ||
    offset_seconds < -64800L ||
    offset_seconds > 64800L {
    raise MalformedInput(field="timezone_period_v3")
  }
  match ends_at_utc_exclusive {
    Some(value) if value <= starts_at_utc_inclusive =>
      raise OrderingViolation(field="timezone_period_v3_end")
    _ => ()
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/TIMEZONE-PERIOD-V3/3.0.0")
  writer.string("3.0.0")
  writer.int64(starts_at_utc_inclusive)
  writer.optional_int64(ends_at_utc_exclusive)
  writer.int64(offset_seconds)
  let canonical = writer.finish()
  {
    starts_at_utc_inclusive,
    ends_at_utc_exclusive,
    offset_seconds,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn TimeZonePeriodV3::starts_at_utc_inclusive(
  self : TimeZonePeriodV3,
) -> Int64 {
  self.starts_at_utc_inclusive
}

///|
pub fn TimeZonePeriodV3::ends_at_utc_exclusive(
  self : TimeZonePeriodV3,
) -> Int64? {
  self.ends_at_utc_exclusive
}

///|
pub fn TimeZonePeriodV3::offset_seconds(self : TimeZonePeriodV3) -> Int64 {
  self.offset_seconds
}

///|
pub fn TimeZonePeriodV3::canonical_bytes(self : TimeZonePeriodV3) -> Bytes {
  self.canonical
}

///|
pub struct TimeZoneRulesV3 {
  rules_ref : @contracts.RecordRef
  timezone_id : String
  ruleset_version : String
  periods : ReadOnlyArray[TimeZonePeriodV3]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn TimeZoneRulesV3::new(
  rules_id : String,
  timezone_id : String,
  ruleset_version : String,
  periods : Array[TimeZonePeriodV3],
) -> TimeZoneRulesV3 raise OrchestrationError {
  require_text(rules_id, "timezone_rules_v3_id")
  require_text(timezone_id, "timezone_rules_v3_timezone_id")
  require_text(ruleset_version, "timezone_rules_v3_ruleset")
  if periods.is_empty() {
    raise MalformedInput(field="timezone_rules_v3_periods")
  }
  let ordered = periods.copy()
  ordered.sort_by((left, right) => {
    left.starts_at_utc_inclusive.compare(right.starts_at_utc_inclusive)
  })
  for index, period in ordered {
    if index > 0 {
      let previous = ordered[index - 1]
      guard previous.ends_at_utc_exclusive is Some(previous_end) else {
        raise OrderingViolation(field="timezone_rules_v3_open_period_not_last")
      }
      if previous_end != period.starts_at_utc_inclusive {
        raise OrderingViolation(field="timezone_rules_v3_noncontiguous")
      }
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/TIMEZONE-RULES-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(rules_id)
  writer.string(timezone_id)
  writer.string(ruleset_version)
  writer.count(ordered.length())
  for period in ordered {
    writer.bytes(period.canonical)
  }
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    rules_ref: self_ref_v3("orchestration-timezone-rules-v3", rules_id, digest),
    timezone_id,
    ruleset_version,
    periods: ReadOnlyArray::from_array(ordered),
    canonical,
    digest,
  }
}

///|
pub fn TimeZoneRulesV3::record_ref(
  self : TimeZoneRulesV3,
) -> @contracts.RecordRef {
  self.rules_ref
}

///|
pub fn TimeZoneRulesV3::timezone_id(self : TimeZoneRulesV3) -> String {
  self.timezone_id
}

///|
pub fn TimeZoneRulesV3::ruleset_version(self : TimeZoneRulesV3) -> String {
  self.ruleset_version
}

///|
pub fn TimeZoneRulesV3::periods(
  self : TimeZoneRulesV3,
) -> ReadOnlyArray[TimeZonePeriodV3] {
  self.periods
}

///|
pub fn TimeZoneRulesV3::canonical_bytes(self : TimeZoneRulesV3) -> Bytes {
  self.canonical
}

///|
pub fn TimeZoneRulesV3::digest(
  self : TimeZoneRulesV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum CivilGapResolutionV3 {
  RejectCivilGapV3
  ShiftCivilGapForwardV3
  ShiftCivilGapBackwardV3
} derive(Eq, Debug)

///|
pub(all) enum CivilFoldResolutionV3 {
  EarlierCivilFoldInstantV3
  LaterCivilFoldInstantV3
} derive(Eq, Debug)

///|
pub(all) enum CivilResolutionKindV3 {
  UniqueCivilInstantV3
  ShiftedCivilGapForwardV3
  ShiftedCivilGapBackwardV3
  EarlierCivilFoldSelectedV3
  LaterCivilFoldSelectedV3
} derive(Eq, Debug)

///|
fn CivilResolutionKindV3::wire(self : CivilResolutionKindV3) -> String {
  match self {
    UniqueCivilInstantV3 => "unique"
    ShiftedCivilGapForwardV3 => "gap-shift-forward"
    ShiftedCivilGapBackwardV3 => "gap-shift-backward"
    EarlierCivilFoldSelectedV3 => "fold-earlier"
    LaterCivilFoldSelectedV3 => "fold-later"
  }
}

///|
pub struct ResolvedCivilTimeV3 {
  resolution_ref : @contracts.RecordRef
  local : LocalCivilTimeV3
  timezone_rules_ref : @contracts.RecordRef
  timezone_id : String
  resolution_kind : CivilResolutionKindV3
  instant : UtcInstantV3
  selected_offset_seconds : Int64
  candidate_count : Int
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn phase3_period_contains(period : TimeZonePeriodV3, instant : Int64) -> Bool {
  instant >= period.starts_at_utc_inclusive &&
  (match period.ends_at_utc_exclusive {
    None => true
    Some(value) => instant < value
  })
}

///|
fn phase3_make_resolved_civil(
  resolution_id : String,
  local : LocalCivilTimeV3,
  rules : TimeZoneRulesV3,
  kind : CivilResolutionKindV3,
  instant_millis : Int64,
  offset_seconds : Int64,
  candidate_count : Int,
) -> ResolvedCivilTimeV3 raise OrchestrationError {
  require_text(resolution_id, "resolved_civil_time_v3_id")
  let instant = UtcInstantV3::new(instant_millis)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/RESOLVED-CIVIL-TIME-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(resolution_id)
  writer.bytes(local.canonical)
  write_ref(writer, rules.rules_ref)
  writer.string(rules.digest.text())
  writer.string(rules.timezone_id)
  writer.string(kind.wire())
  writer.bytes(instant.canonical)
  writer.int64(offset_seconds)
  writer.int64(candidate_count.to_int64())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    resolution_ref: self_ref_v3(
      "orchestration-resolved-civil-time-v3", resolution_id, digest,
    ),
    local,
    timezone_rules_ref: rules.rules_ref,
    timezone_id: rules.timezone_id,
    resolution_kind: kind,
    instant,
    selected_offset_seconds: offset_seconds,
    candidate_count,
    canonical,
    digest,
  }
}

///|
/// Resolve an explicit civil boundary against frozen timezone rules. A gap is
/// never silently guessed and a fold always records which candidate won.
pub fn TimeZoneRulesV3::resolve(
  self : TimeZoneRulesV3,
  resolution_id : String,
  local : LocalCivilTimeV3,
  gap_resolution : CivilGapResolutionV3,
  fold_resolution : CivilFoldResolutionV3,
) -> ResolvedCivilTimeV3 raise OrchestrationError {
  let candidates : Array[(Int64, Int64)] = []
  for period in self.periods {
    let candidate = local.local_epoch_millis - period.offset_seconds * 1000L
    if candidate >= 0L &&
      phase3_period_contains(period, candidate) &&
      !candidates.any(value => value.0 == candidate) {
      candidates.push((candidate, period.offset_seconds))
    }
  }
  candidates.sort_by((left, right) => left.0.compare(right.0))
  match candidates.length() {
    1 =>
      phase3_make_resolved_civil(
        resolution_id,
        local,
        self,
        UniqueCivilInstantV3,
        candidates[0].0,
        candidates[0].1,
        1,
      )
    2 => {
      let selected = match fold_resolution {
        EarlierCivilFoldInstantV3 => candidates[0]
        LaterCivilFoldInstantV3 => candidates[1]
      }
      let kind = match fold_resolution {
        EarlierCivilFoldInstantV3 => EarlierCivilFoldSelectedV3
        LaterCivilFoldInstantV3 => LaterCivilFoldSelectedV3
      }
      phase3_make_resolved_civil(
        resolution_id,
        local,
        self,
        kind,
        selected.0,
        selected.1,
        2,
      )
    }
    0 =>
      match gap_resolution {
        RejectCivilGapV3 =>
          raise ScheduleStateViolation(field="civil_time_v3_gap")
        ShiftCivilGapForwardV3 => {
          let mut selected : (Int64, Int64)? = None
          let mut selected_local = int64_max
          for period in self.periods {
            let local_start = period.starts_at_utc_inclusive +
              period.offset_seconds * 1000L
            if local_start > local.local_epoch_millis &&
              local_start < selected_local {
              selected_local = local_start
              selected = Some(
                (period.starts_at_utc_inclusive, period.offset_seconds),
              )
            }
          }
          guard selected is Some(value) else {
            raise ScheduleStateViolation(
              field="civil_time_v3_gap_unbounded_forward",
            )
          }
          phase3_make_resolved_civil(
            resolution_id,
            local,
            self,
            ShiftedCivilGapForwardV3,
            value.0,
            value.1,
            0,
          )
        }
        ShiftCivilGapBackwardV3 => {
          let mut selected : (Int64, Int64)? = None
          let mut selected_local = -1L
          for period in self.periods {
            match period.ends_at_utc_exclusive {
              Some(period_end) => {
                let local_end = period_end + period.offset_seconds * 1000L
                if local_end <= local.local_epoch_millis &&
                  local_end > selected_local {
                  selected_local = local_end
                  selected = Some((period_end - 1L, period.offset_seconds))
                }
              }
              None => ()
            }
          }
          guard selected is Some(value) else {
            raise ScheduleStateViolation(
              field="civil_time_v3_gap_unbounded_backward",
            )
          }
          phase3_make_resolved_civil(
            resolution_id,
            local,
            self,
            ShiftedCivilGapBackwardV3,
            value.0,
            value.1,
            0,
          )
        }
      }
    _ => raise ScheduleStateViolation(field="civil_time_v3_ambiguous_rules")
  }
}

///|
pub fn ResolvedCivilTimeV3::record_ref(
  self : ResolvedCivilTimeV3,
) -> @contracts.RecordRef {
  self.resolution_ref
}

///|
pub fn ResolvedCivilTimeV3::timezone_id(self : ResolvedCivilTimeV3) -> String {
  self.timezone_id
}

///|
pub fn ResolvedCivilTimeV3::resolution_kind(
  self : ResolvedCivilTimeV3,
) -> CivilResolutionKindV3 {
  self.resolution_kind
}

///|
pub fn ResolvedCivilTimeV3::instant(self : ResolvedCivilTimeV3) -> UtcInstantV3 {
  self.instant
}

///|
pub fn ResolvedCivilTimeV3::canonical_bytes(
  self : ResolvedCivilTimeV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ResolvedCivilTimeV3::digest(
  self : ResolvedCivilTimeV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum DeadlineSourceKindV3 {
  WorkflowDeadlineV3
  AuthorityDeadlineV3
  ReviewDeadlineV3
  LeaseDeadlineV3
  RequestDeadlineV3
  RetryPolicyDeadlineV3
  ScheduleDeadlineV3
} derive(Eq, Debug)

///|
fn DeadlineSourceKindV3::wire(self : DeadlineSourceKindV3) -> String {
  match self {
    WorkflowDeadlineV3 => "workflow"
    AuthorityDeadlineV3 => "authority"
    ReviewDeadlineV3 => "review"
    LeaseDeadlineV3 => "lease"
    RequestDeadlineV3 => "request"
    RetryPolicyDeadlineV3 => "retry-policy"
    ScheduleDeadlineV3 => "schedule"
  }
}

///|
fn DeadlineSourceKindV3::order(self : DeadlineSourceKindV3) -> Int {
  match self {
    WorkflowDeadlineV3 => 0
    AuthorityDeadlineV3 => 1
    ReviewDeadlineV3 => 2
    LeaseDeadlineV3 => 3
    RequestDeadlineV3 => 4
    RetryPolicyDeadlineV3 => 5
    ScheduleDeadlineV3 => 6
  }
}

///|
pub(all) enum DeadlineBoundaryV3 {
  DeadlineInclusiveV3
  DeadlineExclusiveV3
} derive(Eq, Debug)

///|
fn DeadlineBoundaryV3::wire(self : DeadlineBoundaryV3) -> String {
  match self {
    DeadlineInclusiveV3 => "inclusive"
    DeadlineExclusiveV3 => "exclusive"
  }
}

///|
pub struct DeadlineConstraintV3 {
  constraint_ref : @contracts.RecordRef
  source_kind : DeadlineSourceKindV3
  source_ref : @contracts.RecordRef
  boundary : DeadlineBoundaryV3
  instant : UtcInstantV3
  exclusive_cutoff_millis : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn DeadlineConstraintV3::new(
  constraint_id : String,
  source_kind : DeadlineSourceKindV3,
  source_ref : @contracts.RecordRef,
  boundary : DeadlineBoundaryV3,
  instant : UtcInstantV3,
) -> DeadlineConstraintV3 raise OrchestrationError {
  require_text(constraint_id, "deadline_constraint_v3_id")
  let exclusive_cutoff_millis = match boundary {
    DeadlineExclusiveV3 => instant.epoch_millis
    DeadlineInclusiveV3 => {
      if instant.epoch_millis == int64_max {
        raise ArithmeticOverflow(field="deadline_constraint_v3_inclusive")
      }
      instant.epoch_millis + 1L
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/DEADLINE-CONSTRAINT-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(constraint_id)
  writer.string(source_kind.wire())
  write_ref(writer, source_ref)
  writer.string(boundary.wire())
  writer.bytes(instant.canonical)
  writer.int64(exclusive_cutoff_millis)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    constraint_ref: self_ref_v3(
      "orchestration-deadline-constraint-v3", constraint_id, digest,
    ),
    source_kind,
    source_ref,
    boundary,
    instant,
    exclusive_cutoff_millis,
    canonical,
    digest,
  }
}

///|
pub fn DeadlineConstraintV3::record_ref(
  self : DeadlineConstraintV3,
) -> @contracts.RecordRef {
  self.constraint_ref
}

///|
pub fn DeadlineConstraintV3::source_kind(
  self : DeadlineConstraintV3,
) -> DeadlineSourceKindV3 {
  self.source_kind
}

///|
pub fn DeadlineConstraintV3::boundary(
  self : DeadlineConstraintV3,
) -> DeadlineBoundaryV3 {
  self.boundary
}

///|
pub fn DeadlineConstraintV3::instant(
  self : DeadlineConstraintV3,
) -> UtcInstantV3 {
  self.instant
}

///|
pub fn DeadlineConstraintV3::exclusive_cutoff_millis(
  self : DeadlineConstraintV3,
) -> Int64 {
  self.exclusive_cutoff_millis
}

///|
pub fn DeadlineConstraintV3::canonical_bytes(
  self : DeadlineConstraintV3,
) -> Bytes {
  self.canonical
}

///|
pub fn DeadlineConstraintV3::digest(
  self : DeadlineConstraintV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Frozen Phase-3 rule: due/not-before is inclusive; all deadline inputs are
/// normalized to one exclusive millisecond cutoff before taking the minimum.
pub struct EffectiveDeadlineV3 {
  deadline_ref : @contracts.RecordRef
  constraints : ReadOnlyArray[DeadlineConstraintV3]
  controlling_constraint_ref : @contracts.RecordRef
  exclusive_cutoff : UtcInstantV3
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn EffectiveDeadlineV3::new(
  deadline_id : String,
  constraints : Array[DeadlineConstraintV3],
) -> EffectiveDeadlineV3 raise OrchestrationError {
  require_text(deadline_id, "effective_deadline_v3_id")
  if constraints.is_empty() {
    raise MalformedInput(field="effective_deadline_v3_constraints")
  }
  let ordered = constraints.copy()
  ordered.sort_by((left, right) => {
    left.source_kind.order().compare(right.source_kind.order())
  })
  for index, constraint in ordered {
    if index > 0 && ordered[index - 1].source_kind == constraint.source_kind {
      raise MalformedInput(field="effective_deadline_v3_duplicate_source")
    }
  }
  let mut controlling = ordered[0]
  for constraint in ordered {
    if constraint.exclusive_cutoff_millis < controlling.exclusive_cutoff_millis ||
      (
        constraint.exclusive_cutoff_millis ==
        controlling.exclusive_cutoff_millis &&
        constraint.source_kind.order() < controlling.source_kind.order()
      ) {
      controlling = constraint
    }
  }
  let exclusive_cutoff = UtcInstantV3::new(controlling.exclusive_cutoff_millis)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/EFFECTIVE-DEADLINE-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(deadline_id)
  writer.count(ordered.length())
  for constraint in ordered {
    writer.bytes(constraint.canonical)
  }
  write_ref(writer, controlling.constraint_ref)
  writer.bytes(exclusive_cutoff.canonical)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    deadline_ref: self_ref_v3(
      "orchestration-effective-deadline-v3", deadline_id, digest,
    ),
    constraints: ReadOnlyArray::from_array(ordered),
    controlling_constraint_ref: controlling.constraint_ref,
    exclusive_cutoff,
    canonical,
    digest,
  }
}

///|
pub fn EffectiveDeadlineV3::record_ref(
  self : EffectiveDeadlineV3,
) -> @contracts.RecordRef {
  self.deadline_ref
}

///|
pub fn EffectiveDeadlineV3::constraints(
  self : EffectiveDeadlineV3,
) -> ReadOnlyArray[DeadlineConstraintV3] {
  self.constraints
}

///|
pub fn EffectiveDeadlineV3::controlling_constraint_ref(
  self : EffectiveDeadlineV3,
) -> @contracts.RecordRef {
  self.controlling_constraint_ref
}

///|
pub fn EffectiveDeadlineV3::exclusive_cutoff(
  self : EffectiveDeadlineV3,
) -> UtcInstantV3 {
  self.exclusive_cutoff
}

///|
pub fn EffectiveDeadlineV3::canonical_bytes(
  self : EffectiveDeadlineV3,
) -> Bytes {
  self.canonical
}

///|
pub fn EffectiveDeadlineV3::digest(
  self : EffectiveDeadlineV3,
) -> @contracts.ContentDigest {
  self.digest
}
