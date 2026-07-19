///|
fn wb_ref(kind : String, id : String) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode(id)).text(),
  )
}

///|
fn wb_evidence(id : String) -> @contracts.EvidenceRef {
  try! @contracts.EvidenceRef::new(
    wb_ref("evidence", id),
    wb_ref("provenance", "wb-source"),
    @contracts.sha256_digest(@utf8.encode("observed-\{id}")).text(),
  )
}

///|
fn wb_forged_event(
  event_kind : String,
  mutation : Int,
) -> (
  @storage.WorkflowEvent,
  @contracts.RecordRef,
  @contracts.RecordRef,
  String,
  String,
  @contracts.ContentDigest,
  Array[@contracts.EvidenceRef],
) raise {
  let workflow = wb_ref("workflow", "wb-workflow")
  let subject = wb_ref("subject", "wb-subject")
  let attempt = wb_ref("effect-attempt", "wb-attempt")
  let event_id = "wb-event"
  let event_key = "wb-event-key"
  let envelope_key = "wb-envelope-key"
  let causation = "wb-causation"
  let previous = @contracts.sha256_digest(b"wb-previous")
  let evidence = [wb_evidence("wb-evidence")]
  let foreign_evidence = [wb_evidence("wb-foreign-evidence")]
  let envelope_kind = if mutation == 9 {
    "foreign.event.kind"
  } else {
    event_kind
  }
  let contract_id = if mutation == 6 {
    "foreign.effects"
  } else {
    effects_contract_id
  }
  let contract_version = if mutation == 7 {
    "2.0.0"
  } else {
    effects_record_version
  }
  let schema = if mutation == 8 {
    @contracts.SchemaRef::new(
      contract_id,
      contract_version,
      "foreign-schema",
      "1.0.0",
      @contracts.sha256_digest(b"foreign-schema").text(),
    )
  } else if mutation == 6 || mutation == 7 {
    @contracts.SchemaRef::new(
      contract_id,
      contract_version,
      event_kind,
      "1.0.0",
      @contracts.sha256_digest(b"foreign-contract-schema").text(),
    )
  } else {
    effects_schema(event_kind)
  }
  let envelope = @contracts.WireEnvelope::new(
    contract_id,
    contract_version,
    if mutation == 13 {
      "foreign-envelope-id"
    } else {
      event_id
    },
    envelope_kind,
    if mutation == 0 {
      wb_ref("subject", "foreign-subject")
    } else {
      subject
    },
    schema,
    b"unchanged-canonical-record",
    if mutation == 10 {
      "foreign-producer"
    } else {
      effects_producer_id
    },
    if mutation == 11 {
      "2.0.0"
    } else {
      effects_record_version
    },
    [],
    if mutation == 12 {
      foreign_evidence
    } else {
      evidence
    },
    run_ref=if mutation == 1 {
      wb_ref("workflow", "foreign-run")
    } else {
      workflow
    },
    attempt_ref=if mutation == 4 {
      wb_ref("effect-attempt", "foreign-attempt")
    } else {
      attempt
    },
    correlation_ref=if mutation == 2 {
      "foreign-correlation"
    } else {
      workflow.id()
    },
    causation_ref=if mutation == 3 { "foreign-causation" } else { causation },
    idempotency_ref=if mutation == 5 {
      "foreign-envelope-key"
    } else {
      envelope_key
    },
    previous_digest=if mutation == 14 {
      @contracts.sha256_digest(b"foreign-previous")
    } else {
      previous
    },
    extensions=if mutation == 15 {
      [@contracts.OpaqueExtension::new("foreign", "extra", b"x")]
    } else {
      []
    },
  )
  let event = @storage.WorkflowEvent::new(
    effects_record_version,
    effects_schema_version,
    workflow,
    event_id,
    2L,
    2L,
    if mutation == 16 {
      "foreign-event-key"
    } else {
      event_key
    },
    envelope,
    if mutation == 17 {
      foreign_evidence
    } else {
      evidence
    },
    previous_event_digest=previous,
  )
  (event, subject, attempt, event_key, envelope_key, previous, evidence)
}

///|
fn wb_expect_wrapper_rejected(
  event_kind : String,
  mutation : Int,
) -> Unit raise {
  try {
    let (event, subject, attempt, event_key, envelope_key, previous, evidence) = wb_forged_event(
      event_kind, mutation,
    )
    require_event_binding(
      event, event_kind, subject, attempt, event_key, envelope_key, "wb-causation",
      previous, evidence,
    )
  } catch {
    _ => ()
  } noraise {
    _ => fail("forged FLOW-6 wrapper was accepted")
  }
}

///|
test "FLOW-6B every known event kind rejects every wrapper mutation class" {
  let kinds = [
    "attempt.registered.v1", "effect.intent.requested.v1", "effect.dispatch.observed.v1",
    "effect.receipt.recorded.v1", "effect.outcome.unknown.v1", "effect.reconciliation.requested.v1",
    "effect.reconciliation.resolved.v1",
  ]
  for kind in kinds {
    for mutation in 0..<18 {
      wb_expect_wrapper_rejected(kind, mutation)
    }
  }
}

///|
test "FLOW-6 strict binding rejects a raw split previous chain" {
  let (event, subject, attempt, event_key, envelope_key, previous, evidence) = wb_forged_event(
    "effect.intent.requested.v1", 14,
  )
  try
    require_event_binding(
      event, "effect.intent.requested.v1", subject, attempt, event_key, envelope_key,
      "wb-causation", previous, evidence,
    )
  catch {
    DigestMismatch(field="event_payload_previous_digest") => ()
    _ => fail("expected exact split-chain rejection")
  } noraise {
    _ => fail("raw split previous chain was accepted")
  }
}

///|
fn wb_governance_record(
  kind : String,
  id : String,
) -> (@contracts.RecordRef, Bytes) {
  let signing = @utf8.encode("governance-signing-" + id)
  let digest = @contracts.sha256_digest(signing)
  let record_ref = try! @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    digest.text(),
  )
  let writer = EffectsWriter::new()
  try! writer.bytes(signing)
  try! writer.string(digest.text())
  (record_ref, writer.finish())
}

///|
fn wb_strict_decoder_fixture() -> (String, Bytes, DecodedAttemptRecord, Bytes) raise {
  let workflow = wb_ref("workflow", "strict-decoder-workflow")
  let policy = wb_ref("policy", "strict-decoder-policy")
  let subject = wb_ref("subject", "strict-decoder-subject")
  let (authority_request, authority_request_bytes) = wb_governance_record(
    "authority-request", "strict-authority-request",
  )
  let (authority_grant, authority_grant_bytes) = wb_governance_record(
    "authority-decision", "strict-authority-grant",
  )
  let (review_request, review_request_bytes) = wb_governance_record(
    "review-request", "strict-review-request",
  )
  let (review_decision, review_decision_bytes) = wb_governance_record(
    "review-decision", "strict-review-decision",
  )
  let (review_receipt, review_receipt_bytes) = wb_governance_record(
    "review-receipt", "strict-review-receipt",
  )
  let governance_writer = EffectsWriter::new()
  governance_writer.bytes(b"MF6AGOV1")
  governance_writer.string(effects_record_version)
  write_ref(governance_writer, workflow)
  write_ref(governance_writer, policy)
  write_ref(governance_writer, authority_request)
  write_ref(governance_writer, authority_grant)
  write_ref(governance_writer, wb_ref("authority", "strict-authority"))
  governance_writer.optional_int64(None)
  write_ref(governance_writer, review_request)
  write_ref(governance_writer, review_decision)
  write_ref(governance_writer, wb_ref("reviewer", "strict-reviewer"))
  write_ref(governance_writer, review_receipt)
  write_ref(governance_writer, subject)
  governance_writer.string(@contracts.sha256_digest(b"strict-subject").text())
  governance_writer.string(
    @contracts.sha256_digest(b"strict-projection").text(),
  )
  governance_writer.string(@contracts.sha256_digest(b"strict-replay").text())
  governance_writer.bytes(authority_request_bytes)
  governance_writer.bytes(authority_grant_bytes)
  governance_writer.bytes(review_request_bytes)
  governance_writer.bytes(review_decision_bytes)
  governance_writer.bytes(review_receipt_bytes)
  let governance = governance_writer.finish()
  let requested = try! @contracts.WireEnvelope::new(
    "neutral.fixture",
    "1.0.0",
    "strict-requested-work",
    "requested-work",
    subject,
    try! @contracts.SchemaRef::new(
      "neutral.fixture",
      "1.0.0",
      "requested-work",
      "1.0.0",
      @contracts.sha256_digest(b"strict-requested-schema").text(),
    ),
    b"strict-request",
    "neutral-fixture",
    "1.0.0",
    [],
    [],
  )
  let requested_bytes = @contracts.encode_wire_envelope(requested)
  let causal = wb_ref("workflow-event", "strict-causal-event")
  let attempt_id = "strict-decoder-attempt"
  let attempt_writer = EffectsWriter::new()
  attempt_writer.bytes(b"MF6AATT1")
  attempt_writer.string(effects_record_version)
  attempt_writer.string(effects_schema_version)
  attempt_writer.string(attempt_id)
  write_ref(attempt_writer, workflow)
  write_ref(attempt_writer, causal)
  attempt_writer.int64(1L)
  attempt_writer.bytes(requested_bytes)
  attempt_writer.string(requested.envelope_digest().text())
  write_evidence(attempt_writer, [])
  attempt_writer.string(ordered_evidence_digest(b"MF6AATE1", []).text())
  attempt_writer.bytes(governance)
  attempt_writer.int64(1L)
  attempt_writer.string("strict-attempt-key")
  write_optional_ref(attempt_writer, None)
  write_optional_ref(attempt_writer, None)
  attempt_writer.string(causal.digest().text())
  let attempt_bytes = attempt_writer.finish()
  let attempt = decode_attempt_record_strict(attempt_id, attempt_bytes)
  let effect_request = try! @contracts.WireEnvelope::new(
    "neutral.fixture",
    "1.0.0",
    "strict-effect-request",
    "effect-request",
    subject,
    try! @contracts.SchemaRef::new(
      "neutral.fixture",
      "1.0.0",
      "effect-request",
      "1.0.0",
      @contracts.sha256_digest(b"strict-effect-schema").text(),
    ),
    b"strict-effect",
    "neutral-fixture",
    "1.0.0",
    [],
    [],
  )
  let intent_writer = EffectsWriter::new()
  intent_writer.bytes(b"MF6AINT1")
  intent_writer.string(effects_record_version)
  intent_writer.string(effects_schema_version)
  intent_writer.string("strict-decoder-intent")
  write_ref(intent_writer, attempt.attempt_ref)
  intent_writer.string(attempt.attempt_ref.digest().text())
  write_ref(intent_writer, workflow)
  write_ref(intent_writer, subject)
  intent_writer.bytes(governance)
  intent_writer.bytes(@contracts.encode_wire_envelope(effect_request))
  write_evidence(intent_writer, [])
  intent_writer.string(ordered_evidence_digest(b"MF6AINE1", []).text())
  intent_writer.string("strict-external-key")
  write_ref(intent_writer, wb_ref("capability", "strict-capability"))
  intent_writer.string("strict-capability-kind")
  intent_writer.byte(0)
  intent_writer.int64(2L)
  write_ref(intent_writer, attempt.attempt_ref)
  intent_writer.string(attempt.attempt_ref.digest().text())
  (attempt_id, attempt_bytes, attempt, intent_writer.finish())
}

///|
test "FLOW-6 strict decoders reject wrong id truncation and trailing bytes" {
  let (attempt_id, attempt_bytes, attempt, intent_bytes) = wb_strict_decoder_fixture()
  ignore(decode_attempt_record_strict(attempt_id, attempt_bytes))
  ignore(decode_intent_record_strict(intent_bytes, attempt))
  try decode_attempt_record_strict("wrong-attempt-id", attempt_bytes) catch {
    IdentityMismatch(field="attempt_expected_id") => ()
    _ => fail("expected strict wrong-id rejection")
  } noraise {
    _ => fail("strict decoder accepted wrong id")
  }
  for pair in [(attempt_bytes, true), (intent_bytes, false)] {
    let (bytes, is_attempt) = pair
    for damaged in [bytes[0:bytes.length() - 1].to_owned(), bytes + b"x"] {
      try {
        if is_attempt {
          ignore(decode_attempt_record_strict(attempt_id, damaged))
        } else {
          ignore(decode_intent_record_strict(damaged, attempt))
        }
      } catch {
        _ => ()
      } noraise {
        _ => fail("strict decoder accepted truncated or trailing bytes")
      }
    }
  }
}
