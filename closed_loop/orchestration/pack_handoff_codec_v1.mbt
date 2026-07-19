///|
let pack_handoff_contract_id_v1 = "moonflow.pack-handoff.v1"

///|
let pack_handoff_contract_version_v1 = "1.0.0"

///|
pub(all) enum PackHandoffRecordKindV1 {
  PackScheduledActionV3
  PackDeliverableCandidateV1
  PackDeliverableDecisionV1
  PackArtifactRevisionV1
  PackDeliveryReceiptV1
  PackOutcomeObservationV1
  PackGapAssessmentV1
  PackImprovementProposalV1
  PackOfflineEvaluationV1
  PackHumanVersionDecisionV1
  PackOperatorCommandV1
} derive(Eq, Debug)

///|
fn PackHandoffRecordKindV1::wire(self : PackHandoffRecordKindV1) -> String {
  match self {
    PackScheduledActionV3 => "scheduled-action-v3"
    PackDeliverableCandidateV1 => "deliverable-candidate-v1"
    PackDeliverableDecisionV1 => "deliverable-decision-v1"
    PackArtifactRevisionV1 => "artifact-revision-v1"
    PackDeliveryReceiptV1 => "delivery-receipt-v1"
    PackOutcomeObservationV1 => "outcome-observation-v1"
    PackGapAssessmentV1 => "gap-assessment-v1"
    PackImprovementProposalV1 => "improvement-proposal-v1"
    PackOfflineEvaluationV1 => "offline-evaluation-v1"
    PackHumanVersionDecisionV1 => "human-version-decision-v1"
    PackOperatorCommandV1 => "operator-command-v1"
  }
}

///|
fn pack_handoff_kind_from_wire_v1(
  value : String,
) -> PackHandoffRecordKindV1 raise OrchestrationError {
  match value {
    "scheduled-action-v3" => PackScheduledActionV3
    "deliverable-candidate-v1" => PackDeliverableCandidateV1
    "deliverable-decision-v1" => PackDeliverableDecisionV1
    "artifact-revision-v1" => PackArtifactRevisionV1
    "delivery-receipt-v1" => PackDeliveryReceiptV1
    "outcome-observation-v1" => PackOutcomeObservationV1
    "gap-assessment-v1" => PackGapAssessmentV1
    "improvement-proposal-v1" => PackImprovementProposalV1
    "offline-evaluation-v1" => PackOfflineEvaluationV1
    "human-version-decision-v1" => PackHumanVersionDecisionV1
    "operator-command-v1" => PackOperatorCommandV1
    _ =>
      raise UnsupportedVersion(
        field="pack_handoff_record_kind_v1",
        version=value,
      )
  }
}

///|
fn handoff_json_object_v1(
  value : Json,
  field : String,
  allowed : Array[String],
) -> Map[String, Json] raise OrchestrationError {
  guard value is Object(fields) else { raise MalformedInput(field~) }
  for key, _ in fields {
    if !allowed.contains(key) {
      raise MalformedInput(field="\{field}.\{key}")
    }
  }
  fields
}

///|
fn handoff_json_string_v1(
  fields : Map[String, Json],
  key : String,
) -> String raise OrchestrationError {
  match fields.get(key) {
    Some(String(value)) => {
      require_text(value, key)
      value
    }
    _ => raise MalformedInput(field=key)
  }
}

///|
fn handoff_json_optional_string_v1(
  fields : Map[String, Json],
  key : String,
) -> String? raise OrchestrationError {
  match fields.get(key) {
    Some(Null) => None
    Some(String(value)) => {
      require_text(value, key)
      Some(value)
    }
    _ => raise MalformedInput(field=key)
  }
}

///|
fn handoff_hex_nibble_v1(value : UInt16) -> Int raise OrchestrationError {
  if value >= ('0' : UInt16) && value <= ('9' : UInt16) {
    value.to_int() - ('0' : UInt16).to_int()
  } else if value >= ('a' : UInt16) && value <= ('f' : UInt16) {
    value.to_int() - ('a' : UInt16).to_int() + 10
  } else {
    raise MalformedInput(field="pack_handoff_hex_v1")
  }
}

///|
fn handoff_bytes_from_hex_v1(value : String) -> Bytes raise OrchestrationError {
  if value.length() % 2 != 0 {
    raise MalformedInput(field="pack_handoff_hex_v1")
  }
  let bytes : Array[Byte] = []
  for index in 0..<(value.length() / 2) {
    let high = handoff_hex_nibble_v1(value[index * 2])
    let low = handoff_hex_nibble_v1(value[index * 2 + 1])
    bytes.push((high * 16 + low).to_byte())
  }
  Bytes::from_array(bytes)
}

///|
fn handoff_bytes_hex_v1(value : Bytes) -> String {
  let builder = StringBuilder()
  for byte in value {
    let encoded = byte.to_int().to_string(radix=16)
    if encoded.length() == 1 {
      builder.write_string("0")
    }
    builder.write_string(encoded)
  }
  builder.to_string()
}

///|
fn handoff_record_ref_json_v1(value : @contracts.RecordRef) -> Json {
  {
    "kind": value.kind(),
    "id": value.id(),
    "version": value.version().text(),
    "digest": value.digest().text(),
  }
}

///|
fn handoff_decode_record_ref_v1(
  value : Json,
  field : String,
) -> @contracts.RecordRef raise OrchestrationError {
  let fields = handoff_json_object_v1(value, field, [
    "kind", "id", "version", "digest",
  ])
  @contracts.RecordRef::new(
    handoff_json_string_v1(fields, "kind"),
    handoff_json_string_v1(fields, "id"),
    handoff_json_string_v1(fields, "version"),
    handoff_json_string_v1(fields, "digest"),
  ) catch {
    _ => raise MalformedInput(field~)
  }
}

///|
fn handoff_optional_ref_json_v1(value : @contracts.RecordRef?) -> Json {
  match value {
    Some(reference) => handoff_record_ref_json_v1(reference)
    None => Json::null()
  }
}

///|
fn handoff_decode_optional_ref_v1(
  value : Json,
  field : String,
) -> @contracts.RecordRef? raise OrchestrationError {
  match value {
    Null => None
    _ => Some(handoff_decode_record_ref_v1(value, field))
  }
}

///|
fn handoff_evidence_json_v1(value : @contracts.EvidenceRef) -> Json {
  {
    "record": handoff_record_ref_json_v1(value.record()),
    "provenance_ref": handoff_record_ref_json_v1(value.provenance_ref()),
    "observed_digest": value.observed_digest().text(),
    "locator": match value.locator() {
      Some(item) => Json::string(item)
      None => Json::null()
    },
    "media_type": match value.media_type() {
      Some(item) => Json::string(item)
      None => Json::null()
    },
  }
}

///|
fn handoff_decode_evidence_v1(
  value : Json,
) -> @contracts.EvidenceRef raise OrchestrationError {
  let fields = handoff_json_object_v1(value, "evidence", [
    "record", "provenance_ref", "observed_digest", "locator", "media_type",
  ])
  guard fields.get("record") is Some(record_json) &&
    fields.get("provenance_ref") is Some(provenance_json) else {
    raise MalformedInput(field="evidence")
  }
  @contracts.EvidenceRef::new(
    handoff_decode_record_ref_v1(record_json, "evidence.record"),
    handoff_decode_record_ref_v1(provenance_json, "evidence.provenance_ref"),
    handoff_json_string_v1(fields, "observed_digest"),
    locator?=handoff_json_optional_string_v1(fields, "locator"),
    media_type?=handoff_json_optional_string_v1(fields, "media_type"),
  ) catch {
    _ => raise MalformedInput(field="evidence")
  }
}

///|
pub struct PackHeadBindingV1 {
  role : String
  workflow : @contracts.RecordRef
  revision : Int64
  head_digest : @contracts.ContentDigest?
  replay_digest : @contracts.ContentDigest
}

///|
pub fn PackHeadBindingV1::new(
  role : String,
  workflow : @contracts.RecordRef,
  revision : Int64,
  head_digest : @contracts.ContentDigest?,
  replay_digest : @contracts.ContentDigest,
) -> PackHeadBindingV1 raise OrchestrationError {
  require_text(role, "pack_head_role_v1")
  if revision < 0L || (revision == 0L) != (head_digest is None) {
    raise MalformedInput(field="pack_head_binding_v1")
  }
  { role, workflow, revision, head_digest, replay_digest }
}

///|
fn handoff_head_json_v1(value : PackHeadBindingV1) -> Json {
  {
    "role": value.role,
    "workflow": handoff_record_ref_json_v1(value.workflow),
    "revision": value.revision.to_string(),
    "head_digest": match value.head_digest {
      Some(item) => Json::string(item.text())
      None => Json::null()
    },
    "replay_digest": value.replay_digest.text(),
  }
}

///|
fn handoff_decode_head_v1(
  value : Json,
) -> PackHeadBindingV1 raise OrchestrationError {
  let fields = handoff_json_object_v1(value, "head_binding", [
    "role", "workflow", "revision", "head_digest", "replay_digest",
  ])
  guard fields.get("workflow") is Some(workflow_json) else {
    raise MalformedInput(field="head_binding.workflow")
  }
  let revision = @string.parse_int64(handoff_json_string_v1(fields, "revision")) catch {
    _ => raise MalformedInput(field="head_binding.revision")
  }
  let head_digest = match
    handoff_json_optional_string_v1(fields, "head_digest") {
    Some(text) =>
      Some(
        @contracts.ContentDigest::parse(text) catch {
          _ => raise MalformedInput(field="head_binding.head_digest")
        },
      )
    None => None
  }
  let replay_digest = @contracts.ContentDigest::parse(
    handoff_json_string_v1(fields, "replay_digest"),
  ) catch {
    _ => raise MalformedInput(field="head_binding.replay_digest")
  }
  if revision < 0L || (revision == 0L) != (head_digest is None) {
    raise MalformedInput(field="head_binding.revision")
  }
  {
    role: handoff_json_string_v1(fields, "role"),
    workflow: handoff_decode_record_ref_v1(
      workflow_json, "head_binding.workflow",
    ),
    revision,
    head_digest,
    replay_digest,
  }
}

///|
pub struct PackHandoffEnvelopeV1 {
  kind : PackHandoffRecordKindV1
  payload_ref : @contracts.RecordRef
  payload : Bytes
  payload_digest : @contracts.ContentDigest
  source_refs : ReadOnlyArray[@contracts.RecordRef]
  authority_ref : @contracts.RecordRef?
  review_ref : @contracts.RecordRef?
  previous_lineage_ref : @contracts.RecordRef?
  snapshot_ref : @contracts.RecordRef?
  snapshot : Bytes?
  state_tag : String
  ordinal : Int64
  limit : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  occurred_at : Int64
  heads : ReadOnlyArray[PackHeadBindingV1]
  json : Json
  canonical_json : String
  digest : @contracts.ContentDigest
}

///|
fn pack_handoff_requires_authority_v1(kind : PackHandoffRecordKindV1) -> Bool {
  kind == PackDeliverableCandidateV1 ||
  kind == PackDeliverableDecisionV1 ||
  kind == PackDeliveryReceiptV1 ||
  kind == PackHumanVersionDecisionV1
}

///|
fn pack_handoff_requires_review_v1(kind : PackHandoffRecordKindV1) -> Bool {
  kind == PackDeliverableDecisionV1 ||
  kind == PackDeliveryReceiptV1 ||
  kind == PackHumanVersionDecisionV1
}

///|
pub fn encode_pack_handoff_envelope_v1(
  kind : PackHandoffRecordKindV1,
  payload_ref : @contracts.RecordRef,
  payload : Bytes,
  source_refs : Array[@contracts.RecordRef],
  authority_ref : @contracts.RecordRef?,
  review_ref : @contracts.RecordRef?,
  previous_lineage_ref : @contracts.RecordRef?,
  snapshot_ref : @contracts.RecordRef?,
  snapshot : Bytes?,
  state_tag : String,
  ordinal : Int64,
  limit : Int64,
  evidence : Array[@contracts.EvidenceRef],
  occurred_at : Int64,
  heads : Array[PackHeadBindingV1],
) -> Json raise OrchestrationError {
  let payload_digest = @contracts.sha256_digest(payload)
  if payload_ref.digest() != payload_digest {
    raise DigestMismatch(field="pack_handoff_payload_v1")
  }
  let (snapshot_digest, snapshot_hex) : (Json, Json) = match
    (snapshot_ref, snapshot) {
    (None, None) => (Json::null(), Json::null())
    (Some(reference), Some(bytes)) => {
      let digest = @contracts.sha256_digest(bytes)
      if reference.digest() != digest {
        raise DigestMismatch(field="pack_handoff_snapshot_v1")
      }
      (Json::string(digest.text()), Json::string(handoff_bytes_hex_v1(bytes)))
    }
    _ => raise MalformedInput(field="pack_handoff_snapshot_v1")
  }
  let value : Json = {
    "contract_id": pack_handoff_contract_id_v1,
    "contract_version": pack_handoff_contract_version_v1,
    "record_kind": kind.wire(),
    "payload_ref": handoff_record_ref_json_v1(payload_ref),
    "payload_digest": payload_digest.text(),
    "payload_hex": handoff_bytes_hex_v1(payload),
    "source_refs": [
      for reference in source_refs => handoff_record_ref_json_v1(reference)
    ],
    "authority_ref": handoff_optional_ref_json_v1(authority_ref),
    "review_ref": handoff_optional_ref_json_v1(review_ref),
    "previous_lineage_ref": handoff_optional_ref_json_v1(previous_lineage_ref),
    "snapshot_ref": handoff_optional_ref_json_v1(snapshot_ref),
    "snapshot_digest": snapshot_digest,
    "snapshot_hex": snapshot_hex,
    "state_tag": state_tag,
    "ordinal": ordinal.to_string(),
    "limit": limit.to_string(),
    "evidence": [
      for item in evidence => handoff_evidence_json_v1(item)
    ],
    "occurred_at": occurred_at.to_string(),
    "head_bindings": [
      for head in heads => handoff_head_json_v1(head)
    ],
  }
  ignore(decode_pack_handoff_envelope_v1(value))
  value
}

///|
pub fn decode_pack_handoff_envelope_v1(
  value : Json,
) -> PackHandoffEnvelopeV1 raise OrchestrationError {
  let keys = [
    "contract_id", "contract_version", "record_kind", "payload_ref", "payload_digest",
    "payload_hex", "source_refs", "authority_ref", "review_ref", "previous_lineage_ref",
    "snapshot_ref", "snapshot_digest", "snapshot_hex", "state_tag", "ordinal", "limit",
    "evidence", "occurred_at", "head_bindings",
  ]
  let fields = handoff_json_object_v1(value, "pack_handoff", keys)
  if handoff_json_string_v1(fields, "contract_id") !=
    pack_handoff_contract_id_v1 ||
    handoff_json_string_v1(fields, "contract_version") !=
    pack_handoff_contract_version_v1 {
    raise UnsupportedVersion(
      field="pack_handoff_contract_v1",
      version=handoff_json_string_v1(fields, "contract_version"),
    )
  }
  let kind = pack_handoff_kind_from_wire_v1(
    handoff_json_string_v1(fields, "record_kind"),
  )
  guard fields.get("payload_ref") is Some(payload_ref_json) &&
    fields.get("authority_ref") is Some(authority_json) &&
    fields.get("review_ref") is Some(review_json) &&
    fields.get("previous_lineage_ref") is Some(previous_json) &&
    fields.get("snapshot_ref") is Some(snapshot_ref_json) &&
    fields.get("source_refs") is Some(Array(source_values)) &&
    fields.get("evidence") is Some(Array(evidence_values)) &&
    fields.get("head_bindings") is Some(Array(head_values)) else {
    raise MalformedInput(field="pack_handoff_shape_v1")
  }
  let payload_ref = handoff_decode_record_ref_v1(
    payload_ref_json, "payload_ref",
  )
  let payload_digest = @contracts.ContentDigest::parse(
    handoff_json_string_v1(fields, "payload_digest"),
  ) catch {
    _ => raise MalformedInput(field="payload_digest")
  }
  let payload = handoff_bytes_from_hex_v1(
    handoff_json_string_v1(fields, "payload_hex"),
  )
  if payload_ref.digest() != payload_digest ||
    @contracts.sha256_digest(payload) != payload_digest {
    raise DigestMismatch(field="pack_handoff_payload_v1")
  }
  let source_refs = [
    for item in source_values => {
      handoff_decode_record_ref_v1(item, "source_refs")
    }
  ]
  let authority_ref = handoff_decode_optional_ref_v1(
    authority_json, "authority_ref",
  )
  let review_ref = handoff_decode_optional_ref_v1(review_json, "review_ref")
  let previous_lineage_ref = handoff_decode_optional_ref_v1(
    previous_json, "previous_lineage_ref",
  )
  let snapshot_ref = handoff_decode_optional_ref_v1(
    snapshot_ref_json, "snapshot_ref",
  )
  let snapshot_digest_text = handoff_json_optional_string_v1(
    fields, "snapshot_digest",
  )
  let snapshot_hex = handoff_json_optional_string_v1(fields, "snapshot_hex")
  let snapshot = match (snapshot_ref, snapshot_digest_text, snapshot_hex) {
    (None, None, None) => None
    (Some(reference), Some(digest_text), Some(hex)) => {
      let digest = @contracts.ContentDigest::parse(digest_text) catch {
        _ => raise MalformedInput(field="snapshot_digest")
      }
      let bytes = handoff_bytes_from_hex_v1(hex)
      if reference.digest() != digest ||
        @contracts.sha256_digest(bytes) != digest {
        raise DigestMismatch(field="pack_handoff_snapshot_v1")
      }
      Some(bytes)
    }
    _ => raise MalformedInput(field="pack_handoff_snapshot_v1")
  }
  let evidence = [
    for item in evidence_values => handoff_decode_evidence_v1(item)
  ]
  let heads = [ for item in head_values => handoff_decode_head_v1(item) ]
  for index, head in heads {
    if heads[:index].any(value => value.role == head.role) {
      raise MalformedInput(field="pack_handoff_duplicate_head_role_v1")
    }
  }
  let required_head_roles = match kind {
    PackScheduledActionV3 => ["scheduler", "time"]
    PackOperatorCommandV1 => ["command"]
    _ => ["stream", "source", "governance"]
  }
  if heads.length() != required_head_roles.length() ||
    !required_head_roles.all(role => heads.any(head => head.role == role)) {
    raise MalformedInput(field="pack_handoff_head_roles_v1")
  }
  let ordinal = @string.parse_int64(handoff_json_string_v1(fields, "ordinal")) catch {
    _ => raise MalformedInput(field="ordinal")
  }
  let limit = @string.parse_int64(handoff_json_string_v1(fields, "limit")) catch {
    _ => raise MalformedInput(field="limit")
  }
  let occurred_at = @string.parse_int64(
    handoff_json_string_v1(fields, "occurred_at"),
  ) catch {
    _ => raise MalformedInput(field="occurred_at")
  }
  let state_tag = handoff_json_string_v1(fields, "state_tag")
  if ordinal < 0L ||
    limit < 0L ||
    occurred_at < 0L ||
    evidence.is_empty() ||
    (pack_handoff_requires_authority_v1(kind) && authority_ref is None) ||
    (pack_handoff_requires_review_v1(kind) && review_ref is None) {
    raise MalformedInput(field="pack_handoff_required_binding_v1")
  }
  match kind {
    PackScheduledActionV3 =>
      if authority_ref is Some(_) ||
        review_ref is Some(_) ||
        previous_lineage_ref is Some(_) ||
        snapshot_ref is Some(_) ||
        ordinal != 0L ||
        limit != 0L ||
        source_refs.length() != 1 {
        raise MalformedInput(
          field="pack_handoff_scheduled_action_unsupported_fields_v1",
        )
      }
    PackOperatorCommandV1 =>
      if !source_refs.is_empty() ||
        previous_lineage_ref is Some(_) ||
        snapshot_ref is Some(_) ||
        ordinal != 0L ||
        limit != 0L {
        raise MalformedInput(
          field="pack_handoff_operator_unsupported_fields_v1",
        )
      }
    _ => ()
  }
  match authority_ref {
    Some(reference) if !source_refs.contains(reference) &&
      kind != PackOperatorCommandV1 =>
      raise ReplayBindingViolation(field="pack_handoff_authority_source_v1")
    _ => ()
  }
  match review_ref {
    Some(reference) if !source_refs.contains(reference) &&
      kind != PackOperatorCommandV1 =>
      raise ReplayBindingViolation(field="pack_handoff_review_source_v1")
    _ => ()
  }
  let canonical_json = value.stringify()
  {
    kind,
    payload_ref,
    payload,
    payload_digest,
    source_refs: ReadOnlyArray::from_array(source_refs),
    authority_ref,
    review_ref,
    previous_lineage_ref,
    snapshot_ref,
    snapshot,
    state_tag,
    ordinal,
    limit,
    evidence: ReadOnlyArray::from_array(evidence),
    occurred_at,
    heads: ReadOnlyArray::from_array(heads),
    json: value,
    canonical_json,
    digest: @contracts.sha256_digest(@utf8.encode(canonical_json)),
  }
}

///|
pub fn decode_pack_handoff_json_bytes_v1(
  bytes : Bytes,
) -> PackHandoffEnvelopeV1 raise OrchestrationError {
  let text = @utf8.decode(bytes) catch {
    _ => raise MalformedInput(field="pack_handoff_utf8_v1")
  }
  let value = @json.parse(text) catch {
    _ => raise MalformedInput(field="pack_handoff_json_v1")
  }
  decode_pack_handoff_envelope_v1(value)
}

///|
pub fn encode_operator_projection_materialization_json_v1(
  value : OperatorProjectionMaterializationV1,
) -> Json {
  {
    "contract_id": "moonflow.operator-materialization.v1",
    "contract_version": "1.0.0",
    "relative_path": value.relative_path(),
    "content_digest": value.digest().text(),
    "content_hex": handoff_bytes_hex_v1(value.bytes()),
  }
}

///|
pub fn decode_operator_projection_materialization_json_v1(
  value : Json,
) -> OperatorProjectionMaterializationV1 raise OrchestrationError {
  let fields = handoff_json_object_v1(value, "operator_materialization", [
    "contract_id", "contract_version", "relative_path", "content_digest", "content_hex",
  ])
  if handoff_json_string_v1(fields, "contract_id") !=
    "moonflow.operator-materialization.v1" ||
    handoff_json_string_v1(fields, "contract_version") != "1.0.0" ||
    handoff_json_string_v1(fields, "relative_path") !=
    operator_projection_relative_path_v1 {
    raise UnsupportedVersion(
      field="operator_materialization_contract_v1",
      version=handoff_json_string_v1(fields, "contract_version"),
    )
  }
  let digest = @contracts.ContentDigest::parse(
    handoff_json_string_v1(fields, "content_digest"),
  ) catch {
    _ => raise MalformedInput(field="operator_materialization_digest_v1")
  }
  let bytes = handoff_bytes_from_hex_v1(
    handoff_json_string_v1(fields, "content_hex"),
  )
  if @contracts.sha256_digest(bytes) != digest {
    raise DigestMismatch(field="operator_materialization_content_v1")
  }
  { relative_path: operator_projection_relative_path_v1, bytes, digest }
}

///|
pub fn PackHandoffEnvelopeV1::to_json(self : PackHandoffEnvelopeV1) -> Json {
  self.json
}

///|
pub fn PackHandoffEnvelopeV1::head(
  self : PackHandoffEnvelopeV1,
  role : String,
) -> PackHeadBindingV1? {
  self.heads.filter(value => value.role == role).last()
}

///|
pub fn PackHandoffEnvelopeV1::digest(
  self : PackHandoffEnvelopeV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn PackHandoffEnvelopeV1::kind(
  self : PackHandoffEnvelopeV1,
) -> PackHandoffRecordKindV1 {
  self.kind
}

///|
fn handoff_deadline_source_kind_v1(
  value : String,
) -> DeadlineSourceKindV3 raise OrchestrationError {
  match value {
    "workflow" => WorkflowDeadlineV3
    "authority" => AuthorityDeadlineV3
    "review" => ReviewDeadlineV3
    "lease" => LeaseDeadlineV3
    "request" => RequestDeadlineV3
    "retry-policy" => RetryPolicyDeadlineV3
    "schedule" => ScheduleDeadlineV3
    _ => raise MalformedInput(field="scheduled_action_deadline_source_v1")
  }
}

///|
fn handoff_deadline_boundary_v1(
  value : String,
) -> DeadlineBoundaryV3 raise OrchestrationError {
  match value {
    "inclusive" => DeadlineInclusiveV3
    "exclusive" => DeadlineExclusiveV3
    _ => raise MalformedInput(field="scheduled_action_deadline_boundary_v1")
  }
}

///|
fn decode_deadline_constraint_handoff_v1(
  bytes : Bytes,
) -> DeadlineConstraintV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/DEADLINE-CONSTRAINT-V3/3.0.0" ||
    reader.read_string() != "3.0.0" {
    raise MalformedInput(field="scheduled_action_deadline_constraint_v1")
  }
  let id = reader.read_string()
  let source_kind = handoff_deadline_source_kind_v1(reader.read_string())
  let source_ref = reader.read_ref()
  let boundary = handoff_deadline_boundary_v1(reader.read_string())
  let instant = decode_utc_instant_v3(reader.read_bytes())
  let cutoff = reader.read_int64()
  reader.require_end()
  let value = DeadlineConstraintV3::new(
    id, source_kind, source_ref, boundary, instant,
  )
  if value.exclusive_cutoff_millis() != cutoff ||
    value.canonical_bytes() != bytes {
    raise ReplayBindingViolation(
      field="scheduled_action_deadline_constraint_v1",
    )
  }
  value
}

///|
fn decode_effective_deadline_handoff_v1(
  bytes : Bytes,
) -> EffectiveDeadlineV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/EFFECTIVE-DEADLINE-V3/3.0.0" ||
    reader.read_string() != "3.0.0" {
    raise MalformedInput(field="scheduled_action_effective_deadline_v1")
  }
  let id = reader.read_string()
  let constraints : Array[DeadlineConstraintV3] = []
  let count = reader.read_count()
  for _ in 0..<count {
    constraints.push(decode_deadline_constraint_handoff_v1(reader.read_bytes()))
  }
  let controlling_ref = reader.read_ref()
  let cutoff = decode_utc_instant_v3(reader.read_bytes())
  reader.require_end()
  let value = EffectiveDeadlineV3::new(id, constraints)
  if value.controlling_constraint_ref() != controlling_ref ||
    value.exclusive_cutoff().canonical_bytes() != cutoff.canonical_bytes() ||
    value.canonical_bytes() != bytes {
    raise ReplayBindingViolation(field="scheduled_action_effective_deadline_v1")
  }
  value
}

///|
fn decode_scheduled_action_handoff_v1(
  bytes : Bytes,
) -> ScheduledActionV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/SCHEDULED-ACTION-V3/3.0.0" ||
    reader.read_string() != "3.0.0" {
    raise MalformedInput(field="scheduled_action_handoff_v1")
  }
  let action_id = reader.read_string()
  let action_kind = reader.read_string()
  let target_workflow = reader.read_ref()
  let subject_ref = reader.read_ref()
  let source_ref = reader.read_ref()
  let source_digest = reader.read_digest()
  let time_workflow = reader.read_ref()
  let due_at = decode_utc_instant_v3(reader.read_bytes())
  let deadline = decode_effective_deadline_handoff_v1(reader.read_bytes())
  let evidence = reader.read_evidence()
  reader.require_end()
  let value = ScheduledActionV3::new(
    action_id, action_kind, target_workflow, subject_ref, source_ref, source_digest,
    time_workflow, due_at, deadline, evidence,
  )
  if value.canonical_bytes() != bytes {
    raise ReplayBindingViolation(field="scheduled_action_handoff_v1")
  }
  value
}

///|
pub fn PackHandoffEnvelopeV1::scheduled_action(
  self : PackHandoffEnvelopeV1,
) -> ScheduledActionV3 raise OrchestrationError {
  if self.kind != PackScheduledActionV3 {
    raise MalformedInput(field="pack_handoff_scheduled_action_kind_v1")
  }
  let value = decode_scheduled_action_handoff_v1(self.payload)
  if value.record_ref() != self.payload_ref ||
    value.digest() != self.payload_digest ||
    !same_evidence(value.evidence, self.evidence) {
    raise ReplayBindingViolation(field="pack_handoff_scheduled_action_v1")
  }
  value
}

///|
fn handoff_operator_kind_v1(
  value : String,
) -> OperatorCommandKindV1 raise OrchestrationError {
  match value {
    "reconcile-query" => OperatorReconcileQueryV1
    "recovery-retry" => OperatorRecoveryRetryV1
    "quarantine-resolution" => OperatorQuarantineResolutionV1
    "manual-intervention-resolution" => OperatorManualInterventionResolutionV1
    "finalization-disposition" => OperatorFinalizationDispositionV1
    "delivery-authorization" => OperatorDeliveryAuthorizationV1
    "outcome-append" => OperatorOutcomeAppendV1
    "outcome-correction" => OperatorOutcomeCorrectionV1
    "offline-evaluation" => OperatorOfflineEvaluationV1
    "human-adopt" => OperatorHumanAdoptV1
    "human-reject" => OperatorHumanRejectV1
    _ => raise MalformedInput(field="operator_command_kind_v1")
  }
}

///|
fn handoff_operator_scope_v1(
  value : String,
) -> OperatorHeadScopeV1 raise OrchestrationError {
  match value {
    "work" => OperatorWorkHeadV1
    "final-learning" => OperatorFinalLearningHeadV1
    _ => raise MalformedInput(field="operator_command_scope_v1")
  }
}

///|
fn decode_operator_command_handoff_v1(
  bytes : Bytes,
) -> OperatorCommandRequestV1 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/OPERATOR-COMMAND-REQUEST-V1/1.0.0" ||
    reader.read_string() != "1.0.0" {
    raise MalformedInput(field="operator_command_handoff_v1")
  }
  let command_id = reader.read_string()
  let run_id = reader.read_string()
  let kind = handoff_operator_kind_v1(reader.read_string())
  let scope = handoff_operator_scope_v1(reader.read_string())
  let subject_ref = reader.read_ref()
  let authority_ref = reader.read_optional_ref()
  let review_ref = reader.read_optional_ref()
  let expected_head_digest = reader.read_optional_digest()
  let expected_replay_digest = reader.read_digest()
  let expected_state_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  let payload = @contracts.decode_wire_envelope(reader.read_bytes()) catch {
    _ => raise MalformedInput(field="operator_command_payload_v1")
  }
  let requested_at = reader.read_int64()
  reader.require_end()
  let value = OperatorCommandRequestV1::new(
    command_id, run_id, kind, scope, subject_ref, authority_ref, review_ref, expected_head_digest,
    expected_replay_digest, expected_state_digest, evidence, payload, requested_at,
  )
  if value.canonical_bytes() != bytes {
    raise ReplayBindingViolation(field="operator_command_handoff_v1")
  }
  value
}

///|
pub fn PackHandoffEnvelopeV1::operator_command(
  self : PackHandoffEnvelopeV1,
) -> OperatorCommandRequestV1 raise OrchestrationError {
  if self.kind != PackOperatorCommandV1 {
    raise MalformedInput(field="pack_handoff_operator_kind_v1")
  }
  let value = decode_operator_command_handoff_v1(self.payload)
  if value.record_ref() != self.payload_ref ||
    value.digest() != self.payload_digest ||
    value.authority_ref() != self.authority_ref ||
    value.review_ref() != self.review_ref ||
    value.requested_at() != self.occurred_at ||
    !same_evidence(value.evidence(), self.evidence) {
    raise ReplayBindingViolation(field="pack_handoff_operator_command_v1")
  }
  if self.state_tag != value.kind().wire() {
    raise ReplayBindingViolation(field="pack_handoff_operator_state_tag_v1")
  }
  guard self.head("command") is Some(head) else {
    raise MalformedInput(field="pack_handoff_operator_head_v1")
  }
  if head.head_digest != value.expected_head_digest ||
    head.replay_digest != value.expected_replay_digest {
    raise ReplayBindingViolation(field="pack_handoff_operator_head_v1")
  }
  value
}
