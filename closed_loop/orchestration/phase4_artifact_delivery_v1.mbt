///|
/// Immutable artifact revision. Artifact contents, media semantics, and pack
/// vocabulary remain opaque to MoonFlow.
pub struct DeliverableArtifactRevisionV1 {
  revision_ref : @contracts.RecordRef
  lineage_root_ref : @contracts.RecordRef
  previous_revision_ref : @contracts.RecordRef?
  revision_ordinal : Int64
  candidate_ref : @contracts.RecordRef
  finalization_decision_ref : @contracts.RecordRef
  artifact : @contracts.ArtifactRef
  manifest : @contracts.WireEnvelope
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  created_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn artifact_revision_signing_bytes_v1(
  revision_id : String,
  lineage_root_ref : @contracts.RecordRef?,
  previous_revision_ref : @contracts.RecordRef?,
  revision_ordinal : Int64,
  candidate_ref : @contracts.RecordRef,
  decision_ref : @contracts.RecordRef,
  artifact : @contracts.ArtifactRef,
  manifest : @contracts.WireEnvelope,
  evidence : ArrayView[@contracts.EvidenceRef],
  created_at : Int64,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/DELIVERABLE-ARTIFACT-REVISION-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(revision_id)
  write_optional_ref(writer, lineage_root_ref)
  write_optional_ref(writer, previous_revision_ref)
  writer.int64(revision_ordinal)
  write_ref(writer, candidate_ref)
  write_ref(writer, decision_ref)
  write_ref(writer, artifact.record())
  writer.string(artifact.locator())
  writer.string(artifact.media_type())
  write_ref(writer, artifact.provenance_ref())
  writer.string(artifact.observed_digest().text())
  writer.bytes(manifest.canonical_bytes())
  write_evidence(writer, evidence)
  writer.int64(created_at)
  writer.finish()
}

///|
fn make_artifact_revision_v1(
  revision_id : String,
  decision : FinalDeliverableDecisionV1,
  artifact : @contracts.ArtifactRef,
  manifest : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  created_at : Int64,
  parent : DeliverableArtifactRevisionV1?,
) -> DeliverableArtifactRevisionV1 raise OrchestrationError {
  require_text(revision_id, "deliverable_artifact_revision_id_v1")
  require_non_negative(created_at, "deliverable_artifact_created_at_v1")
  if decision.disposition != DeliverableAcceptedV1 {
    raise ScheduleStateViolation(
      field="deliverable_artifact_requires_accept_v1",
    )
  }
  if manifest.subject() != artifact.record() {
    raise IdentityMismatch(field="deliverable_artifact_manifest_subject_v1")
  }
  if created_at < decision.decided_at {
    raise OrderingViolation(field="deliverable_artifact_created_at_v1")
  }
  let evidence = copy_evidence_v1(evidence)
  let (lineage_root_ref, previous_ref, ordinal) = match parent {
    None => (artifact.record(), None, 1L)
    Some(previous) => {
      if previous.candidate_ref != decision.candidate_ref ||
        previous.artifact.record().kind() != artifact.record().kind() ||
        previous.artifact.record().id() != artifact.record().id() ||
        previous.artifact.record() == artifact.record() ||
        created_at < previous.created_at {
        raise IdentityMismatch(field="deliverable_artifact_lineage_v1")
      }
      (
        previous.lineage_root_ref,
        Some(previous.revision_ref),
        checked_add_non_negative(
          previous.revision_ordinal,
          1L,
          "deliverable_artifact_ordinal_v1",
        ),
      )
    }
  }
  let canonical = artifact_revision_signing_bytes_v1(
    revision_id,
    Some(lineage_root_ref),
    previous_ref,
    ordinal,
    decision.candidate_ref,
    decision.decision_ref,
    artifact,
    manifest,
    evidence,
    created_at,
  )
  let digest = @contracts.sha256_digest(canonical)
  let revision_ref = self_ref(
    "orchestration-deliverable-artifact-revision-v1", revision_id, digest,
  )
  {
    revision_ref,
    lineage_root_ref,
    previous_revision_ref: previous_ref,
    revision_ordinal: ordinal,
    candidate_ref: decision.candidate_ref,
    finalization_decision_ref: decision.decision_ref,
    artifact,
    manifest,
    evidence,
    created_at,
    canonical,
    digest,
  }
}

///|
pub fn DeliverableArtifactRevisionV1::initial(
  revision_id : String,
  decision : FinalDeliverableDecisionV1,
  artifact : @contracts.ArtifactRef,
  manifest : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  created_at : Int64,
) -> DeliverableArtifactRevisionV1 raise OrchestrationError {
  make_artifact_revision_v1(
    revision_id,
    decision,
    artifact,
    manifest,
    evidence,
    created_at,
    None,
  )
}

///|
pub fn DeliverableArtifactRevisionV1::revise(
  self : DeliverableArtifactRevisionV1,
  revision_id : String,
  decision : FinalDeliverableDecisionV1,
  artifact : @contracts.ArtifactRef,
  manifest : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  created_at : Int64,
) -> DeliverableArtifactRevisionV1 raise OrchestrationError {
  make_artifact_revision_v1(
    revision_id,
    decision,
    artifact,
    manifest,
    evidence,
    created_at,
    Some(self),
  )
}

///|
pub fn DeliverableArtifactRevisionV1::record_ref(
  self : DeliverableArtifactRevisionV1,
) -> @contracts.RecordRef {
  self.revision_ref
}

///|
pub fn DeliverableArtifactRevisionV1::lineage_root_ref(
  self : DeliverableArtifactRevisionV1,
) -> @contracts.RecordRef {
  self.lineage_root_ref
}

///|
pub fn DeliverableArtifactRevisionV1::previous_revision_ref(
  self : DeliverableArtifactRevisionV1,
) -> @contracts.RecordRef? {
  self.previous_revision_ref
}

///|
pub fn DeliverableArtifactRevisionV1::revision_ordinal(
  self : DeliverableArtifactRevisionV1,
) -> Int64 {
  self.revision_ordinal
}

///|
pub fn DeliverableArtifactRevisionV1::candidate_ref(
  self : DeliverableArtifactRevisionV1,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn DeliverableArtifactRevisionV1::finalization_decision_ref(
  self : DeliverableArtifactRevisionV1,
) -> @contracts.RecordRef {
  self.finalization_decision_ref
}

///|
pub fn DeliverableArtifactRevisionV1::artifact(
  self : DeliverableArtifactRevisionV1,
) -> @contracts.ArtifactRef {
  self.artifact
}

///|
pub fn DeliverableArtifactRevisionV1::manifest(
  self : DeliverableArtifactRevisionV1,
) -> @contracts.WireEnvelope {
  self.manifest
}

///|
pub fn DeliverableArtifactRevisionV1::evidence(
  self : DeliverableArtifactRevisionV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn DeliverableArtifactRevisionV1::created_at(
  self : DeliverableArtifactRevisionV1,
) -> Int64 {
  self.created_at
}

///|
pub fn DeliverableArtifactRevisionV1::canonical_bytes(
  self : DeliverableArtifactRevisionV1,
) -> Bytes {
  self.canonical
}

///|
pub fn DeliverableArtifactRevisionV1::digest(
  self : DeliverableArtifactRevisionV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Evidence-only receipt for a delivery performed by an authorized host. This
/// constructor never performs publication, network, or filesystem effects.
pub struct GovernedDeliveryReceiptV1 {
  receipt_ref : @contracts.RecordRef
  candidate_ref : @contracts.RecordRef
  finalization_decision_ref : @contracts.RecordRef
  artifact_revision_ref : @contracts.RecordRef
  artifact_ref : @contracts.RecordRef
  destination_ref : @contracts.RecordRef
  delivery : @contracts.WireEnvelope
  authority_ref : @contracts.RecordRef
  review_request_ref : @contracts.RecordRef
  review_decision_ref : @contracts.RecordRef
  human_reviewer_ref : @contracts.RecordRef
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  delivered_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn GovernedDeliveryReceiptV1::new(
  receipt_id : String,
  decision : FinalDeliverableDecisionV1,
  artifact_revision : DeliverableArtifactRevisionV1,
  destination_ref : @contracts.RecordRef,
  delivery : @contracts.WireEnvelope,
  delivery_authority : @governance.AuthorityDecision,
  delivery_review_request : @governance.ReviewRequest,
  delivery_human_review : @governance.ReviewDecision,
  evidence : Array[@contracts.EvidenceRef],
  delivered_at : Int64,
) -> GovernedDeliveryReceiptV1 raise OrchestrationError {
  require_text(receipt_id, "governed_delivery_receipt_id_v1")
  require_non_negative(delivered_at, "governed_delivery_time_v1")
  if decision.disposition != DeliverableAcceptedV1 ||
    artifact_revision.candidate_ref != decision.candidate_ref ||
    artifact_revision.finalization_decision_ref != decision.decision_ref {
    raise ScheduleStateViolation(field="governed_delivery_acceptance_v1")
  }
  if delivery.subject() != artifact_revision.artifact.record() {
    raise IdentityMismatch(field="governed_delivery_subject_v1")
  }
  require_granted_authority_v1(
    delivery_authority, "governed_delivery_authority_v1",
  )
  require_review_binding_v1(
    delivery_review_request,
    delivery_human_review,
    artifact_revision.manifest,
    "governed_delivery_human_review_v1",
  )
  if delivery_human_review.outcome() != @governance.Approved {
    raise GovernanceMismatch(field="governed_delivery_review_outcome_v1")
  }
  if delivery_authority.decision_ref() == decision.authority_ref ||
    delivery_human_review.decision_ref() == decision.review_decision_ref {
    raise GovernanceMismatch(field="governed_delivery_separate_governance_v1")
  }
  if delivered_at < artifact_revision.created_at ||
    delivered_at < delivery_human_review.decided_at() {
    raise OrderingViolation(field="governed_delivery_time_v1")
  }
  let evidence = copy_evidence_v1(evidence)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/GOVERNED-DELIVERY-RECEIPT-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(receipt_id)
  write_ref(writer, decision.candidate_ref)
  write_ref(writer, decision.decision_ref)
  write_ref(writer, artifact_revision.revision_ref)
  write_ref(writer, artifact_revision.artifact.record())
  write_ref(writer, destination_ref)
  writer.bytes(delivery.canonical_bytes())
  write_authority_decision_binding_v1(writer, delivery_authority)
  write_review_decision_binding_v1(
    writer, delivery_review_request, delivery_human_review,
  )
  write_evidence(writer, evidence)
  writer.int64(delivered_at)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref(
      "orchestration-governed-delivery-receipt-v1", receipt_id, digest,
    ),
    candidate_ref: decision.candidate_ref,
    finalization_decision_ref: decision.decision_ref,
    artifact_revision_ref: artifact_revision.revision_ref,
    artifact_ref: artifact_revision.artifact.record(),
    destination_ref,
    delivery,
    authority_ref: delivery_authority.decision_ref(),
    review_request_ref: delivery_review_request.request_ref(),
    review_decision_ref: delivery_human_review.decision_ref(),
    human_reviewer_ref: delivery_human_review.reviewer_ref(),
    evidence,
    delivered_at,
    canonical,
    digest,
  }
}

///|
pub fn GovernedDeliveryReceiptV1::record_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn GovernedDeliveryReceiptV1::artifact_revision_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.artifact_revision_ref
}

///|
pub fn GovernedDeliveryReceiptV1::candidate_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn GovernedDeliveryReceiptV1::finalization_decision_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.finalization_decision_ref
}

///|
pub fn GovernedDeliveryReceiptV1::artifact_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.artifact_ref
}

///|
pub fn GovernedDeliveryReceiptV1::destination_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.destination_ref
}

///|
pub fn GovernedDeliveryReceiptV1::delivery(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.WireEnvelope {
  self.delivery
}

///|
pub fn GovernedDeliveryReceiptV1::human_reviewer_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.human_reviewer_ref
}

///|
pub fn GovernedDeliveryReceiptV1::authority_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.authority_ref
}

///|
pub fn GovernedDeliveryReceiptV1::review_request_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.review_request_ref
}

///|
pub fn GovernedDeliveryReceiptV1::review_decision_ref(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.RecordRef {
  self.review_decision_ref
}

///|
pub fn GovernedDeliveryReceiptV1::evidence(
  self : GovernedDeliveryReceiptV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn GovernedDeliveryReceiptV1::delivered_at(
  self : GovernedDeliveryReceiptV1,
) -> Int64 {
  self.delivered_at
}

///|
pub fn GovernedDeliveryReceiptV1::canonical_bytes(
  self : GovernedDeliveryReceiptV1,
) -> Bytes {
  self.canonical
}

///|
pub fn GovernedDeliveryReceiptV1::digest(
  self : GovernedDeliveryReceiptV1,
) -> @contracts.ContentDigest {
  self.digest
}
