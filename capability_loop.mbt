///|
/// Generic activation contract consumed from MoonBook. Domain reward meaning
/// remains opaque to MoonFlow and is carried only through evidence references.
pub fn capability_loop_contract_version() -> String {
  "moonflow.capability_loop.v1"
}

///|
pub(all) struct CapabilityRecordRefV1 {
  record_id : String
  record_version : String
  record_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilityActivationRequestV1 {
  contract_version : String
  request : CapabilityRecordRefV1
  receipt : CapabilityRecordRefV1
  scope_id : String
  rollout_mode : String
  challenger_participant_ids : Array[String]
  max_observations : Int
  experiment : CapabilityRecordRefV1
  old_capability : CapabilityRecordRefV1
  new_capability : CapabilityRecordRefV1
  rollback : CapabilityRecordRefV1
  activation_review : CapabilityRecordRefV1
  activation_reviewer_id : String
  activation_reviewer_authority_ref : String
  requested_at : Int64
  adoption_authorized : Bool
  source_side_effects_applied : Bool
  activation_side_effects_applied : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilityObservationV1 {
  observation_id : String
  scope_id : String
  participant_id : String
  assignment : String
  capability : CapabilityRecordRefV1
  outcome : CapabilityRecordRefV1
  reward_evidence : CapabilityRecordRefV1
  accepted : Bool
  recorded_at : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilitySettlementRequestV1 {
  contract_version : String
  settlement_id : String
  scope_id : String
  decision : String
  experiment_outcome : CapabilityRecordRefV1
  reviewer_id : String
  reviewer_authority_ref : String
  review_evidence : CapabilityRecordRefV1
  settled_at : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilityActivationProjectionV1 {
  contract_version : String
  activation_id : String
  request : CapabilityRecordRefV1
  receipt : CapabilityRecordRefV1
  scope_id : String
  rollout_mode : String
  status : String
  challenger_participant_ids : Array[String]
  max_observations : Int
  experiment : CapabilityRecordRefV1
  old_capability : CapabilityRecordRefV1
  new_capability : CapabilityRecordRefV1
  rollback : CapabilityRecordRefV1
  activation_review : CapabilityRecordRefV1
  activation_reviewer_id : String
  activation_reviewer_authority_ref : String
  activated_at : Int64
  observations : Array[CapabilityObservationV1]
  settlement : CapabilitySettlementRequestV1?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilityResolutionV1 {
  contract_version : String
  scope_id : String
  participant_id : String
  assignment : String
  selected_capability : CapabilityRecordRefV1
  shadow_capability : CapabilityRecordRefV1?
  activation_id : String
  experiment : CapabilityRecordRefV1
  status : String
} derive(Debug, Eq, ToJson, FromJson)

///|
fn capability_ref_valid(reference : CapabilityRecordRefV1) -> Bool {
  !reference.record_id.is_blank() &&
  !reference.record_version.is_blank() &&
  !reference.record_digest.is_blank()
}

///|
fn valid_capability_scope_id(value : String) -> Bool {
  !value.is_blank() &&
  !value.contains("/") &&
  !value.contains("\\") &&
  !value.contains("..")
}

///|
fn validate_activation_request(
  request : CapabilityActivationRequestV1,
) -> Unit raise {
  guard request.contract_version ==
    "moonbook.bookkeeper.capability_activation_request.v1" else {
    fail("unsupported capability activation request contract")
  }
  guard valid_capability_scope_id(request.scope_id) else {
    fail("capability scope_id must be a safe non-empty identifier")
  }
  guard request.rollout_mode == "shadow" ||
    request.rollout_mode == "canary" ||
    request.rollout_mode == "full" else {
    fail("rollout_mode must be shadow, canary, or full")
  }
  guard request.rollout_mode != "canary" ||
    !request.challenger_participant_ids.is_empty() else {
    fail("canary rollout requires challenger participants")
  }
  let participants : Array[String] = []
  for participant in request.challenger_participant_ids {
    guard !participant.is_blank() && !participants.contains(participant) else {
      fail("challenger participants must be non-empty and unique")
    }
    participants.push(participant)
  }
  guard request.max_observations > 0 else {
    fail("max_observations must be positive")
  }
  guard request.requested_at >= 0 else {
    fail("requested_at must be non-negative")
  }
  guard request.adoption_authorized &&
    !request.source_side_effects_applied &&
    !request.activation_side_effects_applied else {
    fail("activation request must come from an authorized non-applying receipt")
  }
  guard capability_ref_valid(request.request) &&
    capability_ref_valid(request.receipt) &&
    capability_ref_valid(request.experiment) &&
    capability_ref_valid(request.old_capability) &&
    capability_ref_valid(request.new_capability) &&
    capability_ref_valid(request.rollback) &&
    capability_ref_valid(request.activation_review) else {
    fail("activation request contains an invalid versioned record reference")
  }
  guard request.old_capability != request.new_capability else {
    fail("old and new capability references must differ")
  }
  guard !request.activation_reviewer_id.is_blank() &&
    !request.activation_reviewer_authority_ref.is_blank() else {
    fail("activation requires a named human authority")
  }
}

///|
pub fn decode_capability_activation_request_v1(
  value : Json,
) -> CapabilityActivationRequestV1 raise {
  let request : CapabilityActivationRequestV1 = @json.from_json(value)
  validate_activation_request(request)
  request
}

///|
pub fn activate_capability_v1(
  request : CapabilityActivationRequestV1,
  activation_id~ : String,
  activated_at~ : Int64,
) -> CapabilityActivationProjectionV1 raise {
  validate_activation_request(request)
  guard !activation_id.is_blank() else { fail("activation_id is required") }
  guard activated_at >= request.requested_at else {
    fail("activation cannot precede its reviewed request")
  }
  {
    contract_version: capability_loop_contract_version(),
    activation_id,
    request: request.request,
    receipt: request.receipt,
    scope_id: request.scope_id,
    rollout_mode: request.rollout_mode,
    status: if request.rollout_mode == "full" {
      "promoted"
    } else {
      "active"
    },
    challenger_participant_ids: request.challenger_participant_ids.copy(),
    max_observations: request.max_observations,
    experiment: request.experiment,
    old_capability: request.old_capability,
    new_capability: request.new_capability,
    rollback: request.rollback,
    activation_review: request.activation_review,
    activation_reviewer_id: request.activation_reviewer_id,
    activation_reviewer_authority_ref: request.activation_reviewer_authority_ref,
    activated_at,
    observations: [],
    settlement: None,
  }
}

///|
pub fn decode_capability_activation_projection_v1(
  value : Json,
) -> CapabilityActivationProjectionV1 raise {
  let projection : CapabilityActivationProjectionV1 = @json.from_json(value)
  guard projection.contract_version == capability_loop_contract_version() else {
    fail("unsupported capability activation projection contract")
  }
  guard valid_capability_scope_id(projection.scope_id) else {
    fail("invalid capability activation scope")
  }
  projection
}

///|
pub fn resolve_capability_v1(
  projection : CapabilityActivationProjectionV1,
  scope_id~ : String,
  participant_id~ : String,
) -> CapabilityResolutionV1 raise {
  guard projection.scope_id == scope_id else {
    fail("capability activation scope mismatch")
  }
  guard !participant_id.is_blank() else { fail("participant_id is required") }
  let challenger = match projection.status {
    "promoted" => true
    "rolled_back" => false
    _ if projection.rollout_mode == "canary" =>
      projection.challenger_participant_ids.contains(participant_id)
    _ => false
  }
  let assignment = if challenger { "challenger" } else { "baseline" }
  {
    contract_version: capability_loop_contract_version(),
    scope_id,
    participant_id,
    assignment,
    selected_capability: if challenger {
      projection.new_capability
    } else {
      projection.old_capability
    },
    shadow_capability: if projection.status == "active" &&
      projection.rollout_mode == "shadow" {
      Some(projection.new_capability)
    } else {
      None
    },
    activation_id: projection.activation_id,
    experiment: projection.experiment,
    status: projection.status,
  }
}

///|
pub fn decode_capability_observation_v1(
  value : Json,
) -> CapabilityObservationV1 raise {
  let observation : CapabilityObservationV1 = @json.from_json(value)
  guard !observation.observation_id.is_blank() &&
    valid_capability_scope_id(observation.scope_id) &&
    !observation.participant_id.is_blank() &&
    (
      observation.assignment == "baseline" ||
      observation.assignment == "challenger"
    ) &&
    capability_ref_valid(observation.capability) &&
    capability_ref_valid(observation.outcome) &&
    capability_ref_valid(observation.reward_evidence) &&
    observation.recorded_at >= 0 else {
    fail("invalid capability observation")
  }
  observation
}

///|
pub fn CapabilityActivationProjectionV1::record_observation(
  self : CapabilityActivationProjectionV1,
  observation : CapabilityObservationV1,
) -> CapabilityActivationProjectionV1 raise {
  guard self.status == "active" || self.status == "promoted" else {
    fail("terminal capability activation cannot accept observations")
  }
  guard self.scope_id == observation.scope_id else {
    fail("capability observation scope mismatch")
  }
  guard !self.observations.any(fn(item) {
    item.observation_id == observation.observation_id
  }) else {
    fail("duplicate capability observation")
  }
  guard self.observations.length() < self.max_observations else {
    fail("capability observation budget is exhausted")
  }
  let resolution = resolve_capability_v1(
    self,
    scope_id=observation.scope_id,
    participant_id=observation.participant_id,
  )
  guard resolution.assignment == observation.assignment &&
    resolution.selected_capability == observation.capability else {
    fail("capability observation does not match its assigned version")
  }
  let observations = self.observations.copy()
  observations.push(observation)
  { ..self, observations, }
}

///|
pub fn decode_capability_settlement_request_v1(
  value : Json,
) -> CapabilitySettlementRequestV1 raise {
  let settlement : CapabilitySettlementRequestV1 = @json.from_json(value)
  guard settlement.contract_version == capability_loop_contract_version() &&
    !settlement.settlement_id.is_blank() &&
    valid_capability_scope_id(settlement.scope_id) &&
    (
      settlement.decision == "promote" ||
      settlement.decision == "rollback" ||
      settlement.decision == "hold"
    ) &&
    capability_ref_valid(settlement.experiment_outcome) &&
    capability_ref_valid(settlement.review_evidence) &&
    !settlement.reviewer_id.is_blank() &&
    !settlement.reviewer_authority_ref.is_blank() &&
    settlement.settled_at >= 0 else {
    fail("invalid capability settlement request")
  }
  settlement
}

///|
pub fn CapabilityActivationProjectionV1::settle(
  self : CapabilityActivationProjectionV1,
  settlement : CapabilitySettlementRequestV1,
) -> CapabilityActivationProjectionV1 raise {
  guard self.status == "active" || self.status == "promoted" else {
    fail("capability activation is already terminal")
  }
  guard self.scope_id == settlement.scope_id &&
    settlement.settled_at >= self.activated_at else {
    fail("capability settlement does not match the active projection")
  }
  let status = match settlement.decision {
    "promote" => "promoted"
    "rollback" => "rolled_back"
    _ => self.status
  }
  let rollout_mode = if settlement.decision == "promote" {
    "full"
  } else {
    self.rollout_mode
  }
  { ..self, status, rollout_mode, settlement: Some(settlement) }
}
