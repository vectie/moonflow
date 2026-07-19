///|
/// Opaque replay-minted proof of the exact current release/expiry terminal.
pub struct CommittedLeaseTerminalReceiptV2 {
  receipt_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  schedule_registration_ref : @contracts.RecordRef
  schedule_registration_digest : @contracts.ContentDigest
  terminal_ref : @contracts.RecordRef
  terminal_digest : @contracts.ContentDigest
  terminal_bytes : Bytes
  owner : @contracts.RecordRef
  observed_at : Int64
  epoch : Int64
  fencing_token : Int64
  committed_event_ref : @contracts.RecordRef
  committed_event_digest : @contracts.ContentDigest
  projection_sequence : Int64
  projection_revision : Int64
  projection_head_digest : @contracts.ContentDigest
  semantic_projection_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn TerminalLeaseV2::terminal_ref(
  self : TerminalLeaseV2,
) -> @contracts.RecordRef {
  match self {
    ReleasedTerminal(value, _) => value.record_ref()
    ExpiredTerminal(value, _) => value.record_ref()
  }
}

///|
fn TerminalLeaseV2::terminal_digest(
  self : TerminalLeaseV2,
) -> @contracts.ContentDigest {
  match self {
    ReleasedTerminal(value, _) => value.digest()
    ExpiredTerminal(value, _) => value.digest()
  }
}

///|
fn TerminalLeaseV2::terminal_bytes(self : TerminalLeaseV2) -> Bytes {
  match self {
    ReleasedTerminal(value, _) => value.canonical_bytes()
    ExpiredTerminal(value, _) => value.canonical_bytes()
  }
}

///|
fn TerminalLeaseV2::registration_ref(
  self : TerminalLeaseV2,
) -> @contracts.RecordRef {
  match self {
    ReleasedTerminal(value, _) => value.schedule_registration_ref
    ExpiredTerminal(value, _) => value.schedule_registration_ref
  }
}

///|
fn TerminalLeaseV2::owner(self : TerminalLeaseV2) -> @contracts.RecordRef {
  match self {
    ReleasedTerminal(value, _) => value.owner()
    ExpiredTerminal(value, _) => value.owner()
  }
}

///|
fn TerminalLeaseV2::observed_at(self : TerminalLeaseV2) -> Int64 {
  match self {
    ReleasedTerminal(value, _) => value.observed_at()
    ExpiredTerminal(value, _) => value.observed_at()
  }
}

///|
fn TerminalLeaseV2::epoch(self : TerminalLeaseV2) -> Int64 {
  match self {
    ReleasedTerminal(value, _) => value.epoch()
    ExpiredTerminal(value, _) => value.epoch()
  }
}

///|
fn TerminalLeaseV2::fencing_token(self : TerminalLeaseV2) -> Int64 {
  match self {
    ReleasedTerminal(value, _) => value.fencing_token()
    ExpiredTerminal(value, _) => value.fencing_token()
  }
}

///|
fn TerminalLeaseV2::event_ref(self : TerminalLeaseV2) -> @contracts.RecordRef {
  match self {
    ReleasedTerminal(_, event_ref) | ExpiredTerminal(_, event_ref) => event_ref
  }
}

///|
fn mint_committed_terminal_receipt_v2(
  projection : OrchestrationProjectionV2,
  terminal : TerminalLeaseV2,
  registration : ScheduleRegisteredV2,
) -> CommittedLeaseTerminalReceiptV2 raise OrchestrationError {
  if terminal.registration_ref() != registration.record_ref() ||
    registration.workflow() != projection.workflow() {
    raise RecoveryViolation(field="lease_terminal_receipt_v2_registration")
  }
  guard projection.last_event_digest() is Some(head_digest) else {
    raise RecoveryViolation(field="lease_terminal_receipt_v2_head")
  }
  let event_ref = terminal.event_ref()
  if event_ref.digest() != head_digest {
    raise RecoveryViolation(field="lease_terminal_receipt_v2_event")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-LEASE-TERMINAL-RECEIPT-V2/2.1.0")
  writer.string("2.1.0")
  write_ref(writer, projection.workflow())
  write_ref(writer, registration.record_ref())
  writer.string(registration.digest().text())
  write_ref(writer, terminal.terminal_ref())
  writer.string(terminal.terminal_digest().text())
  writer.bytes(terminal.terminal_bytes())
  write_ref(writer, terminal.owner())
  writer.int64(terminal.observed_at())
  writer.int64(terminal.epoch())
  writer.int64(terminal.fencing_token())
  write_ref(writer, event_ref)
  writer.string(event_ref.digest().text())
  writer.int64(projection.sequence())
  writer.int64(projection.revision())
  writer.string(head_digest.text())
  writer.string(projection.state_digest().text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref_v2(
      "orchestration-committed-lease-terminal-receipt-v2",
      terminal.terminal_ref().id(),
      digest,
    ),
    workflow: projection.workflow(),
    schedule_registration_ref: registration.record_ref(),
    schedule_registration_digest: registration.digest(),
    terminal_ref: terminal.terminal_ref(),
    terminal_digest: terminal.terminal_digest(),
    terminal_bytes: terminal.terminal_bytes(),
    owner: terminal.owner(),
    observed_at: terminal.observed_at(),
    epoch: terminal.epoch(),
    fencing_token: terminal.fencing_token(),
    committed_event_ref: event_ref,
    committed_event_digest: event_ref.digest(),
    projection_sequence: projection.sequence(),
    projection_revision: projection.revision(),
    projection_head_digest: head_digest,
    semantic_projection_digest: projection.state_digest(),
    canonical,
    digest,
  }
}

///|
pub fn OrchestrationProjectionV2::committed_schedule_registration(
  self : OrchestrationProjectionV2,
) -> ScheduleRegisteredV2? {
  if self.schedules.is_empty() {
    None
  } else {
    self.schedules.last()
  }
}

///|
pub fn OrchestrationProjectionV2::committed_lease_terminal_receipt(
  self : OrchestrationProjectionV2,
) -> CommittedLeaseTerminalReceiptV2? raise OrchestrationError {
  guard self.terminal_lease is Some(terminal) else { return None }
  guard self.schedules.search_by(value => {
      value.record_ref() == terminal.registration_ref()
    })
    is Some(index) else {
    raise RecoveryViolation(field="lease_terminal_receipt_v2_schedule")
  }
  Some(
    mint_committed_terminal_receipt_v2(self, terminal, self.schedules[index]),
  )
}

///|
pub fn CommittedLeaseTerminalReceiptV2::validate_current(
  self : CommittedLeaseTerminalReceiptV2,
  projection : OrchestrationProjectionV2,
) -> Unit raise OrchestrationError {
  if self.workflow != projection.workflow() {
    raise WorkflowMismatch(field="lease_terminal_receipt_v2_workflow")
  }
  if self.projection_sequence != projection.sequence() {
    raise OrderingViolation(field="lease_terminal_receipt_v2_sequence")
  }
  if self.projection_revision != projection.revision() {
    raise RevisionMismatch(
      expected=self.projection_revision,
      actual=projection.revision(),
    )
  }
  if projection.last_event_digest() != Some(self.projection_head_digest) ||
    projection.state_digest() != self.semantic_projection_digest {
    raise DigestMismatch(field="lease_terminal_receipt_v2_projection")
  }
  if @contracts.sha256_digest(self.canonical) != self.digest ||
    self.receipt_ref.digest() != self.digest {
    raise DigestMismatch(field="lease_terminal_receipt_v2_integrity")
  }
  guard projection.committed_lease_terminal_receipt() is Some(current) else {
    raise ReplayBindingViolation(field="lease_terminal_receipt_v2_absent")
  }
  if current.receipt_ref != self.receipt_ref ||
    current.digest != self.digest ||
    current.canonical != self.canonical {
    raise ReplayBindingViolation(field="lease_terminal_receipt_v2_current")
  }
}

///|
pub fn CommittedLeaseTerminalReceiptV2::receipt_ref(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn CommittedLeaseTerminalReceiptV2::workflow(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn CommittedLeaseTerminalReceiptV2::schedule_registration_ref(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.RecordRef {
  self.schedule_registration_ref
}

///|
pub fn CommittedLeaseTerminalReceiptV2::schedule_registration_digest(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.ContentDigest {
  self.schedule_registration_digest
}

///|
pub fn CommittedLeaseTerminalReceiptV2::terminal_ref(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.RecordRef {
  self.terminal_ref
}

///|
pub fn CommittedLeaseTerminalReceiptV2::terminal_digest(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.ContentDigest {
  self.terminal_digest
}

///|
pub fn CommittedLeaseTerminalReceiptV2::owner(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn CommittedLeaseTerminalReceiptV2::observed_at(
  self : CommittedLeaseTerminalReceiptV2,
) -> Int64 {
  self.observed_at
}

///|
pub fn CommittedLeaseTerminalReceiptV2::epoch(
  self : CommittedLeaseTerminalReceiptV2,
) -> Int64 {
  self.epoch
}

///|
pub fn CommittedLeaseTerminalReceiptV2::fencing_token(
  self : CommittedLeaseTerminalReceiptV2,
) -> Int64 {
  self.fencing_token
}

///|
pub fn CommittedLeaseTerminalReceiptV2::committed_event_ref(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.RecordRef {
  self.committed_event_ref
}

///|
pub fn CommittedLeaseTerminalReceiptV2::projection_sequence(
  self : CommittedLeaseTerminalReceiptV2,
) -> Int64 {
  self.projection_sequence
}

///|
pub fn CommittedLeaseTerminalReceiptV2::projection_revision(
  self : CommittedLeaseTerminalReceiptV2,
) -> Int64 {
  self.projection_revision
}

///|
pub fn CommittedLeaseTerminalReceiptV2::projection_head_digest(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.ContentDigest {
  self.projection_head_digest
}

///|
pub fn CommittedLeaseTerminalReceiptV2::canonical_bytes(
  self : CommittedLeaseTerminalReceiptV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedLeaseTerminalReceiptV2::digest(
  self : CommittedLeaseTerminalReceiptV2,
) -> @contracts.ContentDigest {
  self.digest
}
