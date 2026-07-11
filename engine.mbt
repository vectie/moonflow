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
        request_id: "",
        result_id: "",
        active_attempt_id: "",
        idempotency_key: "",
        external_job_id: "",
        attempt_status: "",
        operation: "",
        input_digest: "",
        output_digest: "",
        error_kind: "",
        compensable: false,
        blocker: "",
        acceptance_review_id: "",
        acceptance_review_artifact: "",
        acceptance_reviewer_id: "",
        artifacts: [],
        approvals: [],
      })
    }
    _ => {
      guard self.find_item(event.work_item_id) is Some(item) else {
        raise MissingWorkItem(event.work_item_id)
      }
      if !event.product_id.is_empty() && event.product_id != item.product_id {
        raise SourceContextMismatch(
          field="product_id",
          expected=item.product_id,
          actual=event.product_id,
        )
      }
      if !event.declaration_id.is_empty() &&
        event.declaration_id != item.declaration_id {
        raise SourceContextMismatch(
          field="declaration_id",
          expected=item.declaration_id,
          actual=event.declaration_id,
        )
      }
      if !event.requested_authority.is_empty() &&
        event.requested_authority != item.requested_authority {
        raise SourceContextMismatch(
          field="requested_authority",
          expected=item.requested_authority,
          actual=event.requested_authority,
        )
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
          if event.error_kind == "acceptance-rejected" {
            item.acceptance_review_id = event.result_id
            item.acceptance_review_artifact = event.artifact_id
            item.acceptance_reviewer_id = event.authority_id
            if !event.artifact_id.is_empty() &&
              !item.artifacts.contains(event.artifact_id) {
              item.artifacts.push(event.artifact_id)
            }
          }
        }
        ItemReviewRequested => {
          require_transition(item, event, [Active])
          item.status = Review
        }
        ItemAccepted => {
          require_transition(item, event, [Review])
          for
            pair in [
              ("review_id", event.detail),
              ("receipt_artifact", event.artifact_id),
              ("reviewer_id", event.authority_id),
              ("result_id", event.result_id),
              ("attempt_id", event.attempt_id),
              ("output_digest", event.output_digest),
            ] {
            let (field, value) = pair
            if value.trim().is_empty() {
              raise MissingAcceptanceReviewField(
                item_id=item.work_item_id,
                field~,
              )
            }
          }
          for
            identity in [
              ("acceptance_result_id", item.result_id, event.result_id),
              (
                "acceptance_attempt_id",
                item.active_attempt_id,
                event.attempt_id,
              ),
              (
                "acceptance_output_digest",
                item.output_digest,
                event.output_digest,
              ),
            ] {
            let (field, expected, actual) = identity
            if expected != actual {
              raise SourceContextMismatch(field~, expected~, actual~)
            }
          }
          item.status = Accepted
          item.blocker = ""
          item.acceptance_review_id = event.detail
          item.acceptance_review_artifact = event.artifact_id
          item.acceptance_reviewer_id = event.authority_id
          if !item.artifacts.contains(event.artifact_id) {
            item.artifacts.push(event.artifact_id)
          }
          if !item.approvals.contains(event.authority_id) {
            item.approvals.push(event.authority_id)
          }
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
        AttemptSubmitted => {
          require_transition(item, event, [Ready])
          for
            pair in [
              ("request_id", event.request_id),
              ("attempt_id", event.attempt_id),
              ("idempotency_key", event.idempotency_key),
              ("input_digest", event.input_digest),
            ] {
            let (field, value) = pair
            if value.trim().is_empty() {
              raise MissingAttemptField(item_id=item.work_item_id, field~)
            }
          }
          if event.attempt_status != "submitted" {
            raise UnsupportedAttemptStatus(
              item_id=item.work_item_id,
              status=event.attempt_status,
            )
          }
          item.status = Active
          item.attempt_count += 1
          item.request_id = event.request_id
          item.result_id = ""
          item.active_attempt_id = event.attempt_id
          item.idempotency_key = event.idempotency_key
          item.external_job_id = ""
          item.attempt_status = event.attempt_status
          item.operation = event.detail
          item.input_digest = event.input_digest
          item.output_digest = ""
          item.error_kind = ""
          item.compensable = false
          item.blocker = ""
        }
        AttemptReconciled => {
          require_transition(item, event, [Active, Waiting, Blocked])
          for
            pair in [
              ("result_id", event.result_id),
              ("request_id", event.request_id),
              ("attempt_id", event.attempt_id),
              ("idempotency_key", event.idempotency_key),
              ("attempt_status", event.attempt_status),
            ] {
            let (field, value) = pair
            if value.trim().is_empty() {
              raise MissingAttemptField(item_id=item.work_item_id, field~)
            }
          }
          for
            identity in [
              (item.request_id, event.request_id),
              (item.active_attempt_id, event.attempt_id),
              (item.idempotency_key, event.idempotency_key),
            ] {
            let (expected, actual) = identity
            if expected != actual {
              raise AttemptIdentityMismatch(
                item_id=item.work_item_id,
                expected~,
                actual~,
              )
            }
          }
          item.result_id = event.result_id
          item.external_job_id = event.external_job_id
          item.attempt_status = event.attempt_status
          item.compensable = event.compensable
          item.error_kind = event.error_kind
          for artifact in event.output_artifacts {
            if !item.artifacts.contains(artifact) {
              item.artifacts.push(artifact)
            }
          }
          match event.attempt_status {
            "submitted" | "running" => item.status = Active
            "succeeded" => {
              if event.output_digest.trim().is_empty() {
                raise MissingAttemptField(
                  item_id=item.work_item_id,
                  field="output_digest",
                )
              }
              item.output_digest = event.output_digest
              item.status = Review
              item.blocker = ""
            }
            "failed" => {
              if event.error_kind.trim().is_empty() {
                raise MissingAttemptField(
                  item_id=item.work_item_id,
                  field="error_kind",
                )
              }
              item.status = Failed
              item.blocker = event.error_kind
            }
            "cancelled" => {
              item.status = Cancelled
              item.blocker = "adapter attempt cancelled"
            }
            "unknown" => {
              item.status = Blocked
              item.blocker = "adapter outcome unknown; reconciliation required"
            }
            status =>
              raise UnsupportedAttemptStatus(item_id=item.work_item_id, status~)
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
