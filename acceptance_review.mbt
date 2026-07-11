///|
pub(all) struct AcceptanceCriterionReview {
  criterion : String
  satisfied : Bool
  evidence_refs : Array[String]
  note : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct AcceptanceReviewReceipt {
  contract_id : String
  review_id : String
  run_id : String
  work_item_id : String
  declaration_id : String
  result_id : String
  attempt_id : String
  output_digest : String
  decision : String
  criteria : Array[AcceptanceCriterionReview]
  reviewer_id : String
  review_authority_id : String
  receipt_artifact : String
  recorded_at : String
} derive(Debug, Eq, ToJson)

///|
pub(all) suberror AcceptanceReviewError {
  InvalidAcceptanceReview(Array[String])
  AcceptanceReviewItemUnavailable(String)
  AcceptanceReviewIdentityMismatch(
    field~ : String,
    expected~ : String,
    actual~ : String
  )
  AcceptanceReviewConflict(String)
} derive(Debug, Eq, ToJson)

///|
fn decode_criterion_review(value : Json) -> AcceptanceCriterionReview raise {
  let fields = wire_object(value, "acceptance criterion review")
  {
    criterion: wire_string(fields, "criterion"),
    satisfied: wire_bool(fields, "satisfied"),
    evidence_refs: wire_strings(fields, "evidence_refs", required=false),
    note: wire_string(fields, "note"),
  }
}

///|
pub fn decode_acceptance_review_receipt(
  value : Json,
) -> AcceptanceReviewReceipt raise {
  let fields = wire_object(value, "acceptance review receipt")
  guard fields.get("criteria") is Some(Array(criteria)) else {
    fail("acceptance review receipt requires criteria array")
  }
  {
    contract_id: wire_string(fields, "contract_id"),
    review_id: wire_string(fields, "review_id"),
    run_id: wire_string(fields, "run_id"),
    work_item_id: wire_string(fields, "work_item_id"),
    declaration_id: wire_string(fields, "declaration_id"),
    result_id: wire_string(fields, "result_id"),
    attempt_id: wire_string(fields, "attempt_id"),
    output_digest: wire_string(fields, "output_digest"),
    decision: wire_string(fields, "decision"),
    criteria: criteria.map(value => decode_criterion_review(value)),
    reviewer_id: wire_string(fields, "reviewer_id"),
    review_authority_id: wire_string(fields, "review_authority_id"),
    receipt_artifact: wire_string(fields, "receipt_artifact"),
    recorded_at: wire_string(fields, "recorded_at"),
  }
}

///|
pub fn AcceptanceReviewReceipt::quality_issues(
  self : AcceptanceReviewReceipt,
) -> Array[String] {
  let issues : Array[String] = []
  if self.contract_id != "moonflow.acceptance-review.v1" {
    issues.push("unsupported acceptance review contract")
  }
  if self.decision != "accepted" && self.decision != "rejected" {
    issues.push("decision must be accepted or rejected")
  }
  if self.criteria.is_empty() {
    issues.push("criterion reviews are required")
  }
  let seen : Array[String] = []
  for review in self.criteria {
    if review.criterion.trim().is_empty() {
      issues.push("review criterion is required")
    } else if seen.contains(review.criterion) {
      issues.push("duplicate reviewed criterion: \{review.criterion}")
    } else {
      seen.push(review.criterion)
    }
    if review.note.trim().is_empty() {
      issues.push("criterion review note is required")
    }
    if review.satisfied && review.evidence_refs.is_empty() {
      issues.push("satisfied criterion requires evidence: \{review.criterion}")
    }
  }
  if self.decision == "accepted" &&
    self.criteria.any(review => !review.satisfied) {
    issues.push("accepted review requires every criterion to be satisfied")
  }
  if self.decision == "rejected" &&
    self.criteria.all(review => review.satisfied) {
    issues.push("rejected review requires an unsatisfied criterion")
  }
  if !artifact_ref_is_workspace_relative(self.receipt_artifact) {
    issues.push("acceptance receipt must be a workspace-relative artifact")
  }
  issues
}

///|
fn require_review_identity(
  field : String,
  expected : String,
  actual : String,
) -> Unit raise AcceptanceReviewError {
  if expected != actual {
    raise AcceptanceReviewIdentityMismatch(field~, expected~, actual~)
  }
}

///|
pub fn acceptance_review_event(
  projection : RunProjection,
  receipt : AcceptanceReviewReceipt,
) -> RuntimeEvent raise AcceptanceReviewError {
  let issues = receipt.quality_issues()
  if !issues.is_empty() {
    raise InvalidAcceptanceReview(issues)
  }
  guard projection.find_item(receipt.work_item_id) is Some(item) else {
    raise AcceptanceReviewItemUnavailable(receipt.work_item_id)
  }
  require_review_identity("run_id", projection.run_id, receipt.run_id)
  require_review_identity(
    "declaration_id",
    item.declaration_id,
    receipt.declaration_id,
  )
  require_review_identity("result_id", item.result_id, receipt.result_id)
  require_review_identity(
    "attempt_id",
    item.active_attempt_id,
    receipt.attempt_id,
  )
  require_review_identity(
    "output_digest",
    item.output_digest,
    receipt.output_digest,
  )
  if receipt.criteria.length() != item.acceptance_criteria.length() {
    raise InvalidAcceptanceReview([
      "criterion review count must match the declaration",
    ])
  }
  for index in 0..<item.acceptance_criteria.length() {
    if receipt.criteria[index].criterion != item.acceptance_criteria[index] {
      raise InvalidAcceptanceReview([
        "reviewed criteria must exactly match declaration order and text",
      ])
    }
    for evidence in receipt.criteria[index].evidence_refs {
      if !item.artifacts.contains(evidence) {
        raise InvalidAcceptanceReview([
          "criterion evidence is not attached to the Work item: \{evidence}",
        ])
      }
    }
  }
  let event_id = "event-\{projection.run_id}-acceptance-\{receipt.review_id}"
  if item.acceptance_review_id == receipt.review_id {
    for previous in projection.applied_events {
      if previous.event_id == event_id &&
        previous.artifact_id == receipt.receipt_artifact &&
        previous.authority_id == receipt.review_authority_id &&
        previous.output_digest == receipt.output_digest {
        return previous
      }
    }
    raise AcceptanceReviewConflict(receipt.review_id)
  }
  if item.status != Review {
    raise InvalidAcceptanceReview([
      "Work item must be in review before an acceptance decision",
    ])
  }
  let rejected_notes : Array[String] = []
  let evidence : Array[String] = []
  for review in receipt.criteria {
    if !review.satisfied {
      rejected_notes.push("\{review.criterion}: \{review.note}")
    }
    for artifact in review.evidence_refs {
      if !evidence.contains(artifact) {
        evidence.push(artifact)
      }
    }
  }
  {
    sequence: projection.last_sequence + 1,
    event_id,
    run_id: projection.run_id,
    work_item_id: item.work_item_id,
    kind: if receipt.decision == "accepted" {
      ItemAccepted
    } else {
      ItemBlocked
    },
    product_id: item.product_id,
    declaration_id: item.declaration_id,
    book_id: projection.book_id,
    declaration_revision: projection.declaration_revision,
    source_digest: projection.source_digest,
    requested_authority: item.requested_authority,
    acceptance_criteria: item.acceptance_criteria.copy(),
    request_id: item.request_id,
    result_id: if receipt.decision == "accepted" {
      receipt.result_id
    } else {
      receipt.review_id
    },
    attempt_id: receipt.attempt_id,
    idempotency_key: item.idempotency_key,
    external_job_id: item.external_job_id,
    attempt_status: item.attempt_status,
    input_digest: item.input_digest,
    output_digest: receipt.output_digest,
    output_artifacts: evidence,
    error_kind: if receipt.decision == "accepted" {
      ""
    } else {
      "acceptance-rejected"
    },
    compensable: item.compensable,
    depends_on: [],
    detail: if receipt.decision == "accepted" {
      receipt.review_id
    } else {
      "Acceptance rejected by \{receipt.review_id}: \{rejected_notes.join("; ")}"
    },
    artifact_id: receipt.receipt_artifact,
    authority_id: receipt.review_authority_id,
    recorded_at: receipt.recorded_at,
  }
}
