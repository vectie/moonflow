///|
pub fn empty_projection(run_id : String) -> RunProjection {
  {
    run_id,
    book_id: "",
    declaration_revision: "",
    source_digest: "",
    last_sequence: -1,
    items: [],
    applied_event_ids: [],
    applied_events: [],
    outcome: "proposed",
  }
}

///|
pub fn RunProjection::find_item(
  self : RunProjection,
  item_id : String,
) -> RuntimeItem? {
  for item in self.items {
    if item.work_item_id == item_id {
      return Some(item)
    }
  }
  None
}

///|
fn RunProjection::unaccepted_dependency(
  self : RunProjection,
  item : RuntimeItem,
) -> String? {
  for dependency_id in item.depends_on {
    match self.find_item(dependency_id) {
      Some(dependency) =>
        if dependency.status != Accepted {
          return Some(dependency_id)
        }
      None => return Some(dependency_id)
    }
  }
  None
}

///|
fn RunProjection::refresh_outcome(self : RunProjection) -> Unit {
  if self.items.is_empty() {
    self.outcome = "proposed"
  } else if self.items.all(item => item.status == Accepted) {
    self.outcome = "accepted"
  } else if self.items.any(item => item.status == Active) {
    self.outcome = "active"
  } else if self.items.any(item => item.status == Review) {
    self.outcome = "review"
  } else if self.items.any(item => item.status == Blocked) {
    self.outcome = "blocked"
  } else if self.items.any(item => item.status == Failed) {
    self.outcome = "failed"
  } else if self.items.any(item => item.status == Ready) {
    self.outcome = "ready"
  } else {
    self.outcome = "waiting"
  }
}

///|
fn require_transition(
  item : RuntimeItem,
  event : RuntimeEvent,
  allowed : Array[RuntimeStatus],
) -> Unit raise FlowError {
  if !allowed.contains(item.status) {
    raise InvalidTransition(
      item_id=item.work_item_id,
      from=item.status.id(),
      event=event.kind.id(),
    )
  }
}

///|
fn RunProjection::apply_new_event(
  self : RunProjection,
  event : RuntimeEvent,
) -> Unit raise FlowError {
  match event.kind {
    RunCreated => {
      if event.work_item_id != "" {
        raise InvalidTransition(
          item_id=event.work_item_id,
          from="none",
          event=event.kind.id(),
        )
      }
      if event.book_id.trim().is_empty() {
        raise MissingRunSource("book_id")
      }
      if event.declaration_revision.trim().is_empty() {
        raise MissingRunSource("declaration_revision")
      }
      if event.source_digest.trim().is_empty() {
        raise MissingRunSource("source_digest")
      }
      self.book_id = event.book_id
      self.declaration_revision = event.declaration_revision
      self.source_digest = event.source_digest
    }
    ItemRegistered => {
      if event.work_item_id.trim().is_empty() {
        raise MissingWorkItem(event.work_item_id)
      }
      if self.find_item(event.work_item_id) is Some(_) {
        raise DuplicateWorkItem(event.work_item_id)
      }
      if event.declaration_id.trim().is_empty() {
        raise MissingDeclarationId(event.work_item_id)
      }
      if event.acceptance_criteria.is_empty() {
        raise MissingAcceptanceCriteria(event.work_item_id)
      }
      if ![
          "observe", "cognitive-maintenance", "sandbox-execution", "workspace-mutation",
          "external-effect", "physical-effect",
        ].contains(event.requested_authority) {
        raise InvalidAuthority(
          item_id=event.work_item_id,
          authority=event.requested_authority,
        )
      }
      self.items.push({
        work_item_id: event.work_item_id,
        declaration_id: event.declaration_id,
        product_id: event.product_id,
        requested_authority: event.requested_authority,
        acceptance_criteria: event.acceptance_criteria.copy(),
        depends_on: event.depends_on.copy(),
        status: Proposed,
        attempt_count: 0,
        blocker: "",
        artifacts: [],
        approvals: [],
      })
    }
    _ => {
      guard self.find_item(event.work_item_id) is Some(item) else {
        raise MissingWorkItem(event.work_item_id)
      }
      match event.kind {
        ItemReady => {
          require_transition(item, event, [Proposed, Waiting, Blocked])
          match self.unaccepted_dependency(item) {
            Some(dependency_id) =>
              raise DependencyNotAccepted(
                item_id=item.work_item_id,
                dependency_id~,
              )
            None => {
              item.status = Ready
              item.blocker = ""
            }
          }
        }
        ItemStarted => {
          require_transition(item, event, [Ready])
          item.status = Active
          item.attempt_count += 1
        }
        ItemWaiting => {
          require_transition(item, event, [Proposed, Ready, Active, Blocked])
          item.status = Waiting
          item.blocker = event.detail
        }
        ItemBlocked => {
          require_transition(item, event, [
            Proposed,
            Ready,
            Active,
            Waiting,
            Review,
          ])
          item.status = Blocked
          item.blocker = event.detail
        }
        ItemReviewRequested => {
          require_transition(item, event, [Active])
          item.status = Review
        }
        ItemAccepted => {
          require_transition(item, event, [Active, Review])
          item.status = Accepted
          item.blocker = ""
        }
        ItemFailed => {
          require_transition(item, event, [
            Ready,
            Active,
            Waiting,
            Blocked,
            Review,
          ])
          item.status = Failed
          item.blocker = event.detail
        }
        ItemCancelled => {
          require_transition(item, event, [
            Proposed,
            Ready,
            Active,
            Waiting,
            Blocked,
            Review,
          ])
          item.status = Cancelled
          item.blocker = event.detail
        }
        ItemSuperseded => {
          require_transition(item, event, [
            Proposed,
            Ready,
            Active,
            Waiting,
            Blocked,
            Review,
          ])
          item.status = Superseded
          item.blocker = event.detail
        }
        ArtifactAttached => {
          if event.artifact_id.trim().is_empty() {
            raise MissingArtifactId(item.work_item_id)
          }
          if !item.artifacts.contains(event.artifact_id) {
            item.artifacts.push(event.artifact_id)
          }
        }
        ApprovalGranted => {
          if event.authority_id.trim().is_empty() {
            raise MissingAuthorityId(item.work_item_id)
          }
          if !item.approvals.contains(event.authority_id) {
            item.approvals.push(event.authority_id)
          }
        }
        RunCreated | ItemRegistered => ()
      }
    }
  }
}

///|
pub fn RunProjection::apply(
  self : RunProjection,
  event : RuntimeEvent,
) -> Unit raise FlowError {
  if event.event_id.trim().is_empty() {
    raise EmptyEventId
  }
  if event.run_id.trim().is_empty() {
    raise EmptyRunId
  }
  if event.run_id != self.run_id {
    raise RunIdMismatch(expected=self.run_id, actual=event.run_id)
  }
  if event.kind != RunCreated {
    if event.book_id != self.book_id {
      raise SourceContextMismatch(
        field="book_id",
        expected=self.book_id,
        actual=event.book_id,
      )
    }
    if event.declaration_revision != self.declaration_revision {
      raise SourceContextMismatch(
        field="declaration_revision",
        expected=self.declaration_revision,
        actual=event.declaration_revision,
      )
    }
    if event.source_digest != self.source_digest {
      raise SourceContextMismatch(
        field="source_digest",
        expected=self.source_digest,
        actual=event.source_digest,
      )
    }
  }
  for previous in self.applied_events {
    if previous.event_id == event.event_id {
      if previous == event {
        return
      }
      raise ConflictingDuplicateEvent(event.event_id)
    }
  }
  let expected = self.last_sequence + 1
  if event.sequence != expected {
    raise InvalidSequence(expected~, actual=event.sequence)
  }
  self.apply_new_event(event)
  self.applied_event_ids.push(event.event_id)
  self.applied_events.push(event)
  self.last_sequence = event.sequence
  self.refresh_outcome()
}

///|
pub fn replay(
  run_id : String,
  events : Array[RuntimeEvent],
) -> RunProjection raise FlowError {
  let projection = empty_projection(run_id)
  for event in events {
    projection.apply(event)
  }
  projection
}

///|
pub fn RunProjection::runnable_item_ids(self : RunProjection) -> Array[String] {
  self.items.filter_map(item => {
    if item.status == Ready {
      Some(item.work_item_id)
    } else {
      None
    }
  })
}
