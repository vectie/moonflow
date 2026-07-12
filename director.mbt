///|
pub fn claim_class_rank(claim : String) -> Int? {
  match claim {
    "observation" => Some(0)
    "research-evidence" => Some(1)
    "execution-result" => Some(2)
    "accepted-knowledge" => Some(3)
    "digital-artifact" => Some(4)
    "simulation-evidence" => Some(5)
    "scenario-qualified" => Some(6)
    "calibrated-digital-twin" => Some(7)
    "hardware-in-loop-qualified" => Some(8)
    "engineering-unit-qualified" => Some(9)
    "physical-readiness" => Some(10)
    "physical-effect-claim" => Some(11)
    _ => None
  }
}

///|
pub(all) struct DirectorRequirement {
  requirement_id : String
  product_id : String
  operation : String
  requested_authority : String
  input_contracts : Array[String]
  output_contracts : Array[String]
  required_claim : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct DirectorCandidateReview {
  adapter_id : String
  accepted : Bool
  reasons : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct DirectorDecision {
  contract_id : String
  requirement_id : String
  selected_adapter_id : String
  accepted : Bool
  reviews : Array[DirectorCandidateReview]
} derive(Debug, Eq, ToJson)

///|
pub fn decode_director_requirement(value : Json) -> DirectorRequirement raise {
  let fields = wire_object(value, "MoonFlow director requirement")
  {
    requirement_id: wire_string(fields, "requirement_id"),
    product_id: wire_string(fields, "product_id"),
    operation: wire_string(fields, "operation"),
    requested_authority: wire_string(fields, "requested_authority"),
    input_contracts: wire_strings(fields, "input_contracts"),
    output_contracts: wire_strings(fields, "output_contracts"),
    required_claim: wire_string(fields, "required_claim"),
  }
}

///|
pub fn decode_adapter_capabilities(
  value : Json,
) -> Array[AdapterCapability] raise {
  match value {
    Array(values) => values.map(value => validate_adapter_capability(value))
    _ => fail("MoonFlow capabilities must be a JSON array")
  }
}

///|
fn candidate_reasons(
  capability : AdapterCapability,
  requirement : DirectorRequirement,
) -> Array[String] {
  let reasons : Array[String] = []
  if capability.product_id != requirement.product_id {
    reasons.push("product owner mismatch")
  }
  if !capability.operations.contains(requirement.operation) {
    reasons.push("operation unsupported")
  }
  if !capability.authority_classes.contains(requirement.requested_authority) {
    reasons.push("authority unsupported")
  }
  if !capability.supports_reconcile {
    reasons.push("reconciliation unsupported")
  }
  if !capability.healthy {
    reasons.push("adapter unhealthy")
  }
  for contract in requirement.input_contracts {
    if !capability.input_contracts.contains(contract) {
      reasons.push("input contract unsupported: \{contract}")
    }
  }
  for contract in requirement.output_contracts {
    if !capability.output_contracts.contains(contract) {
      reasons.push("output contract unsupported: \{contract}")
    }
  }
  match
    (
      claim_class_rank(capability.claim_ceiling),
      claim_class_rank(requirement.required_claim),
    ) {
    (Some(ceiling), Some(required)) =>
      if ceiling < required {
        reasons.push("required claim exceeds adapter ceiling")
      }
    (_, None) => reasons.push("required claim is unsupported")
    (None, _) => reasons.push("adapter claim ceiling is unsupported")
  }
  reasons
}

///|
pub fn select_adapter(
  capabilities : Array[AdapterCapability],
  requirement : DirectorRequirement,
) -> DirectorDecision {
  let reviews : Array[DirectorCandidateReview] = []
  let mut selected_adapter_id = ""
  for capability in capabilities {
    let reasons = candidate_reasons(capability, requirement)
    let accepted = reasons.is_empty()
    reviews.push({ adapter_id: capability.adapter_id, accepted, reasons })
    if accepted && selected_adapter_id.is_empty() {
      selected_adapter_id = capability.adapter_id
    }
  }
  {
    contract_id: "moonflow.director-decision.v1",
    requirement_id: requirement.requirement_id,
    selected_adapter_id,
    accepted: !selected_adapter_id.is_empty(),
    reviews,
  }
}

///|
pub(all) enum DirectorFailureClass {
  TransientFailure
  QualityRejection
  AuthorityDenial
  PermanentIncompatibility
  UnknownOutcome
} derive(Debug, Eq, Compare, Hash, ToJson)

///|
pub fn DirectorFailureClass::id(self : DirectorFailureClass) -> String {
  match self {
    TransientFailure => "transient-failure"
    QualityRejection => "quality-rejection"
    AuthorityDenial => "authority-denial"
    PermanentIncompatibility => "permanent-incompatibility"
    UnknownOutcome => "unknown-outcome"
  }
}

///|
pub(all) struct DirectorRetryDecision {
  failure_class : DirectorFailureClass
  action : String
  preserves_attempt_evidence : Bool
  reuses_idempotency_lineage : Bool
  requires_reconciliation : Bool
} derive(Debug, Eq, ToJson)

///|
pub fn director_retry_decision(
  failure_class : DirectorFailureClass,
) -> DirectorRetryDecision {
  {
    failure_class,
    action: match failure_class {
      TransientFailure => "retry-with-backoff"
      QualityRejection => "revise-input-or-procedure"
      AuthorityDenial => "request-scoped-authority-or-stop"
      PermanentIncompatibility => "select-another-compatible-adapter-or-block"
      UnknownOutcome => "reconcile-before-any-retry"
    },
    preserves_attempt_evidence: true,
    reuses_idempotency_lineage: true,
    requires_reconciliation: failure_class == UnknownOutcome,
  }
}
