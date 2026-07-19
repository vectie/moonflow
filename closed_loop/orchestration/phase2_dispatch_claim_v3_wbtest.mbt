///|
fn phase2_leased_pending_fixture(
  suffix : String,
) -> (
  Phase1bPendingFixture,
  @storage.MemoryStore,
  @storage.ReplayResult,
  @storage.ReplayResult,
) raise {
  let fixture = phase1b_pending_fixture(suffix)
  let schedule = fixture.registration.schedule()
  let evidence = [ for value in schedule.evidence() => value ]
  let owner = phase1a_wb_ref(
    "owner",
    "phase2-dispatch-owner-" + suffix,
    @utf8.encode("phase2-dispatch-owner-" + suffix),
  )
  let claim = LeaseClaimV2::new(
    "phase2-dispatch-lease-claim-" + suffix,
    schedule,
    schedule.admission(),
    schedule.workflow(),
    owner,
    10L,
    fixture.current.work.orchestration().epoch_floor(),
    fixture.current.work.orchestration().fencing_floor(),
    1L,
    1L,
    "phase2-dispatch-lease-key-" + suffix,
    evidence,
    fixture.current.work.prefix_event().unwrap().event_ref(),
  )
  let claimed = LeaseClaimedV2::new(
    "phase2-dispatch-lease-claimed-" + suffix,
    fixture.registration,
    claim,
  )
  let open = fixture.current.open_work_authority()
  let authority = fixture.current.authorize_open_work_operation(
    open,
    "lease.claim",
    claimed.record_ref(),
  )
  let candidate = prepare_lifecycle_lease_claim_candidate_v2(
    fixture.current,
    open,
    authority,
    "phase2-dispatch-lease-event-" + suffix,
    claim.idempotency_key(),
    "phase2-dispatch-lease-command-" + suffix,
    claimed,
  )
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let store = phase1c_b_combined_memory_store(
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  let bound = phase1c_b_bound_memory_store(store, candidate)
  guard commit_lifecycle_candidate_v2(bound, candidate)
    is LifecycleCommittedV2(_) else {
    fail("phase2 lease claim did not commit")
  }
  let leased_work = store.replay(fixture.registration.workflow())
  let leased_governance = store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  (fixture, store, leased_work, leased_governance)
}

///|
fn phase2_active_pending_fixture(
  suffix : String,
) -> (
  Phase1bPendingFixture,
  @storage.MemoryStore,
  @storage.ReplayResult,
  @storage.ReplayResult,
) raise {
  let (fixture, store, leased_work, leased_governance) = phase2_leased_pending_fixture(
    suffix,
  )
  let recovery = fold_governed_recovery_v3(
    fixture.empty_effects,
    leased_work,
    leased_governance,
  )
  let profile = ProviderRecoveryProfileV3::new(
    "phase2-test-profile-" + suffix,
    true,
    true,
    true,
    true,
  )
  let activation_receipt = store.activate_guarded_workflow(
    fixture.registration.workflow(),
    [leased_governance.workflow()],
  )
  let recovery_store = @storage.GuardedMemoryStore::new(
    store, activation_receipt,
  )
  guard activate_recovery_protocol_v3(
      recovery_store,
      recovery,
      fixture.intent.intent_ref(),
      profile,
      "phase2-recovery-activation-" + suffix,
      "phase2-recovery-activation-event-" + suffix,
      "phase2-recovery-activation-command-" + suffix,
      10L,
    )
    is RecoveryProtocolActivationFreshV3 else {
    fail("phase2 recovery activation did not commit")
  }
  (
    fixture,
    store,
    store.replay(fixture.registration.workflow()),
    store.replay(fixture.current.root_binding.governance_stream_ref()),
  )
}

///|
fn phase2_bound_dispatch_store(
  store : @storage.MemoryStore,
  candidate : DispatchClaimCommitCandidateV3,
) -> @storage.GuardedMemoryStore raise {
  let guards = [
    for head_guard in candidate.guarded_request.guards() => {
      head_guard.workflow()
    }
  ]
  let activation = store.activate_guarded_workflow(
    candidate.request.workflow(),
    guards,
  )
  @storage.GuardedMemoryStore::new(store, activation)
}

///|
fn phase2_replay_head_guard(
  replay : @storage.ReplayResult,
) -> @storage.WorkflowHeadGuard raise {
  @storage.WorkflowHeadGuard::new(
    replay.workflow(),
    replay.head().revision(),
    replay.head().last_event_digest(),
    replay.replay_digest(),
  )
}

///|
test "Phase2 dispatch claim chooses one owner and classifies exact replay" {
  let (fixture, store, work, governance) = try
    phase2_active_pending_fixture("single-owner")
  catch {
    ReplayBindingViolation(field~) => fail("active fixture: " + field)
    error => fail("active fixture: \{to_repr(error)}")
  } noraise {
    value => value
  }
  let current = try
    fold_governed_recovery_v3(fixture.empty_effects, work, governance)
  catch {
    ReplayBindingViolation(field~) => fail("recovery fold: " + field)
    error => fail("recovery fold: \{to_repr(error)}")
  } noraise {
    value => value
  }
  assert_true(
    current.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryDispatchEligibleV3,
  )
  let evidence = [
    for value in fixture.registration.schedule().evidence() => value
  ]
  let first = try
    current.prepare_dispatch_claim_v3(
      fixture.intent.intent_ref(),
      "phase2-dispatch-claim-first",
      "phase2-dispatch-event-first",
      "phase2-dispatch-command-first",
      11L,
      12L,
      evidence,
    )
  catch {
    ReplayBindingViolation(field~) => fail("prepare first: " + field)
    error => fail("prepare first: \{to_repr(error)}")
  } noraise {
    value => value
  }
  let second = current.prepare_dispatch_claim_v3(
    fixture.intent.intent_ref(),
    "phase2-dispatch-claim-second",
    "phase2-dispatch-event-second",
    "phase2-dispatch-command-second",
    11L,
    12L,
    evidence,
  )
  let bound = phase2_bound_dispatch_store(store, first)
  let first_outcome = try commit_dispatch_claim_v3(bound, first) catch {
    RecoveryViolation(field~) => fail("commit first: " + field)
    ReplayBindingViolation(field~) => fail("commit first replay: " + field)
    error => fail("commit first: \{to_repr(error)}")
  } noraise {
    value => value
  }
  guard first_outcome is DispatchClaimFreshlyCommittedV3(first_receipt) else {
    fail("first dispatch claim was not freshly committed")
  }
  guard commit_dispatch_claim_v3(bound, first)
    is DispatchClaimAlreadyCommittedV3(duplicate_receipt) else {
    fail("exact dispatch claim replay was not classified already committed")
  }
  assert_true(
    first_receipt.canonical_bytes() == duplicate_receipt.canonical_bytes(),
  )
  guard commit_dispatch_claim_v3(bound, second) is DispatchClaimLostV3(loss) else {
    fail("second same-head worker did not lose")
  }
  assert_true(
    loss.winning_event_kinds() ==
    [dispatch_claim_event_kind_v3, invocation_started_event_kind_v3],
  )
  let claimed_work = store.replay(fixture.registration.workflow())
  let claimed_governance = store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  // The full root-bound V2 aggregate accounts for and strictly decodes the
  // claim even though the claim state itself is owned by the V3 projection.
  ignore(
    fold_governed_closed_loop_v2(
      fixture.empty_effects,
      claimed_work,
      claimed_governance,
    ),
  )
  let claimed = fold_governed_recovery_v3(
    fixture.empty_effects,
    claimed_work,
    claimed_governance,
  )
  assert_true(
    claimed.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryDispatchAttemptedV3,
  )
  first_receipt.validate_replay_binding(
    fixture.empty_effects,
    claimed_work,
    claimed_governance,
  )
  first_receipt.validate_current(claimed, 11L)
  try first_receipt.validate_current(claimed, 12L) catch {
    RecoveryViolation(field="dispatch_claim_v3_not_current") => ()
    error => fail("unexpected expired receipt error: \{to_repr(error)}")
  } noraise {
    _ => fail("expired dispatch claim receipt remained current")
  }
  try
    claimed.prepare_dispatch_claim_v3(
      fixture.intent.intent_ref(),
      "phase2-dispatch-claim-third",
      "phase2-dispatch-event-third",
      "phase2-dispatch-command-third",
      11L,
      12L,
      evidence,
    )
  catch {
    RecoveryViolation(field="dispatch_claim_v3_existing_claim") => ()
    error => fail("unexpected existing-claim error: \{to_repr(error)}")
  } noraise {
    _ => fail("prepared a second claim from claimed recovery state")
  }
}

///|
fn phase2_claim_tampered_event(
  source : @storage.WorkflowEvent,
  kind : String,
  payload_bytes : Bytes,
  suffix : String,
) -> @storage.WorkflowEvent raise {
  let envelope = source.payload()
  let changed = @contracts.WireEnvelope::new(
    envelope.contract_id(),
    envelope.contract_version().text(),
    "phase2-tampered-envelope-" + suffix,
    kind,
    envelope.subject(),
    phase1b_effect_schema_v22(kind),
    payload_bytes,
    envelope.producer_id(),
    envelope.producer_version().text(),
    [],
    [
      for value in envelope.evidence() => value
    ],
    run_ref=envelope.run_ref().unwrap(),
    attempt_ref=envelope.attempt_ref().unwrap(),
    correlation_ref=envelope.correlation_ref().unwrap(),
    causation_ref=envelope.causation_ref().unwrap(),
    idempotency_ref=envelope.idempotency_ref().unwrap(),
    previous_digest=envelope.previous_digest().unwrap(),
  )
  @storage.WorkflowEvent::new(
    source.record_version().text(),
    source.schema_version().text(),
    source.workflow(),
    "phase2-tampered-event-" + suffix,
    source.sequence(),
    source.revision(),
    source.idempotency_key(),
    changed,
    [
      for value in source.evidence() => value
    ],
    previous_event_digest=source.previous_event_digest().unwrap(),
  )
}

///|
priv enum Phase2ClaimTransportSubstitutionV3 {
  ClaimEnvelopeIdSubstitutionV3
  ClaimContractIdSubstitutionV3
  ClaimContractVersionSubstitutionV3
  ClaimProducerIdSubstitutionV3
  ClaimProducerVersionSubstitutionV3
  ClaimStageSubstitutionV3
  ClaimArtifactSubstitutionV3
  ClaimExtensionSubstitutionV3
}

///|
fn Phase2ClaimTransportSubstitutionV3::label(
  self : Phase2ClaimTransportSubstitutionV3,
) -> String {
  match self {
    ClaimEnvelopeIdSubstitutionV3 => "envelope-id"
    ClaimContractIdSubstitutionV3 => "contract-id"
    ClaimContractVersionSubstitutionV3 => "contract-version"
    ClaimProducerIdSubstitutionV3 => "producer-id"
    ClaimProducerVersionSubstitutionV3 => "producer-version"
    ClaimStageSubstitutionV3 => "stage"
    ClaimArtifactSubstitutionV3 => "artifact"
    ClaimExtensionSubstitutionV3 => "extension"
  }
}

///|
fn phase2_claim_transport_substituted_event_v3(
  source : @storage.WorkflowEvent,
  substitution : Phase2ClaimTransportSubstitutionV3,
) -> @storage.WorkflowEvent raise {
  let envelope = source.payload()
  let label = substitution.label()
  let contract_id = match substitution {
    ClaimContractIdSubstitutionV3 => "closed-loop.effects.substituted"
    _ => envelope.contract_id()
  }
  let contract_version = match substitution {
    ClaimContractVersionSubstitutionV3 => "1.0.1"
    _ => envelope.contract_version().text()
  }
  let schema = if contract_id != envelope.contract_id() ||
    contract_version != envelope.contract_version().text() {
    @contracts.SchemaRef::new(
      contract_id,
      contract_version,
      envelope.schema().schema_id(),
      envelope.schema().schema_version().text(),
      envelope.schema().schema_digest().text(),
    )
  } else {
    envelope.schema()
  }
  let artifacts : Array[@contracts.ArtifactRef] = match substitution {
    ClaimArtifactSubstitutionV3 =>
      [
        @contracts.ArtifactRef::new(
          envelope.subject(),
          "artifacts/phase2-claim-" + label + ".bin",
          "application/octet-stream",
          source.workflow(),
          envelope.payload_digest().text(),
        ),
      ]
    _ => [ for value in envelope.artifacts() => value ]
  }
  let extensions : Array[@contracts.OpaqueExtension] = match substitution {
    ClaimExtensionSubstitutionV3 =>
      [
        @contracts.OpaqueExtension::new(
          "org.moonflow.phase2",
          "claim-transport-substitution",
          @utf8.encode(label),
        ),
      ]
    _ => [ for value in envelope.extensions() => value ]
  }
  let stage_ref = match substitution {
    ClaimStageSubstitutionV3 => Some(source.workflow())
    _ => envelope.stage_ref()
  }
  let changed = @contracts.WireEnvelope::new(
    contract_id,
    contract_version,
    match substitution {
      ClaimEnvelopeIdSubstitutionV3 => source.event_ref().id() + "-substituted"
      _ => envelope.envelope_id()
    },
    envelope.envelope_kind(),
    envelope.subject(),
    schema,
    envelope.payload(),
    match substitution {
      ClaimProducerIdSubstitutionV3 => "effects-protocol-substituted"
      _ => envelope.producer_id()
    },
    match substitution {
      ClaimProducerVersionSubstitutionV3 => "1.0.1"
      _ => envelope.producer_version().text()
    },
    artifacts,
    [
      for value in envelope.evidence() => value
    ],
    run_ref?=envelope.run_ref(),
    stage_ref?,
    attempt_ref?=envelope.attempt_ref(),
    correlation_ref?=envelope.correlation_ref(),
    causation_ref?=envelope.causation_ref(),
    idempotency_ref?=envelope.idempotency_ref(),
    previous_digest?=envelope.previous_digest(),
    extensions~,
  )
  @storage.WorkflowEvent::new(
    source.record_version().text(),
    source.schema_version().text(),
    source.workflow(),
    source.event_ref().id(),
    source.sequence(),
    source.revision(),
    source.idempotency_key(),
    changed,
    [
      for value in source.evidence() => value
    ],
    previous_event_digest?=source.previous_event_digest(),
  )
}

///|
fn phase2_require_claim_transport_rejected_by_every_fold_v3(
  fixture : Phase1bPendingFixture,
  work : @storage.ReplayResult,
  governance : @storage.ReplayResult,
  label : String,
) -> Unit raise {
  try fold_closed_loop_v2(fixture.empty_effects, work) catch {
    ReplayBindingViolation(field="dispatch_claim_v3_event_binding") => ()
    error => fail("unexpected legacy V2 " + label + " error: \{to_repr(error)}")
  } noraise {
    _ => fail("legacy V2 accepted substituted claim transport: " + label)
  }
  try
    fold_governed_closed_loop_v2(fixture.empty_effects, work, governance)
  catch {
    ReplayBindingViolation(field="dispatch_claim_v3_event_binding") => ()
    error => fail("unexpected root V2 " + label + " error: \{to_repr(error)}")
  } noraise {
    _ => fail("root V2 accepted substituted claim transport: " + label)
  }
  try fold_governed_recovery_v3(fixture.empty_effects, work, governance) catch {
    ReplayBindingViolation(field="dispatch_claim_v3_event_binding") => ()
    error => fail("unexpected V3 " + label + " error: \{to_repr(error)}")
  } noraise {
    _ => fail("V3 accepted substituted claim transport: " + label)
  }
}

///|
test "Phase2 claim closed replay rejects every substitutable transport class" {
  let substitutions : Array[Phase2ClaimTransportSubstitutionV3] = [
    ClaimEnvelopeIdSubstitutionV3,
    ClaimContractIdSubstitutionV3,
    ClaimContractVersionSubstitutionV3,
    ClaimProducerIdSubstitutionV3,
    ClaimProducerVersionSubstitutionV3,
    ClaimStageSubstitutionV3,
    ClaimArtifactSubstitutionV3,
    ClaimExtensionSubstitutionV3,
  ]
  for substitution in substitutions {
    let label = substitution.label()
    let (fixture, store, work, governance) = phase2_active_pending_fixture(
      "transport-" + label,
    )
    let current = fold_governed_recovery_v3(
      fixture.empty_effects,
      work,
      governance,
    )
    let candidate = current.prepare_dispatch_claim_v3(
      fixture.intent.intent_ref(),
      "phase2-transport-claim-" + label,
      "phase2-transport-event-" + label,
      "phase2-transport-command-" + label,
      11L,
      12L,
      [
        for value in fixture.registration.schedule().evidence() => value
      ],
    )
    let changed_event = phase2_claim_transport_substituted_event_v3(
      candidate.request.events()[0],
      substitution,
    )
    let request = @storage.CommitRequest::new(
      candidate.request.record_version().text(),
      candidate.request.schema_version().text(),
      candidate.request.workflow(),
      candidate.request.expected_revision(),
      candidate.claim.command_idempotency_key,
      [changed_event],
      [],
    )
    let guarded = @storage.GuardedCommitRequest::new(
      request,
      [
        for value in candidate.guarded_request.guards() => value
      ],
    )
    let bound = phase2_bound_dispatch_store(store, candidate)
    guard bound.guarded_commit(guarded) is @storage.GuardedCommitSucceeded(_) else {
      fail("registered storage rejected transport fixture: " + label)
    }
    phase2_require_claim_transport_rejected_by_every_fold_v3(
      fixture,
      bound.replay(candidate.request.workflow()),
      governance,
      label,
    )
  }
}

///|
test "Phase2 claim event versions cannot bypass the shared transport binding" {
  let (fixture, _, work, governance) = phase2_active_pending_fixture(
    "transport-event-versions",
  )
  let current = fold_governed_recovery_v3(
    fixture.empty_effects,
    work,
    governance,
  )
  let candidate = current.prepare_dispatch_claim_v3(
    fixture.intent.intent_ref(),
    "phase2-transport-version-claim",
    "phase2-transport-version-event",
    "phase2-transport-version-command",
    11L,
    12L,
    [
      for value in fixture.registration.schedule().evidence() => value
    ],
  )
  let source = candidate.request.events()[0]
  for
    version_case in [
      ("1.0.1", orchestration_schema_version, "workflow_event"),
      (orchestration_record_version, "1.0.1", "workflow_event_schema"),
    ] {
    let (record_version, schema_version, expected_kind) = version_case
    try
      @storage.WorkflowEvent::new(
        record_version,
        schema_version,
        source.workflow(),
        source.event_ref().id(),
        source.sequence(),
        source.revision(),
        source.idempotency_key(),
        source.payload(),
        [
          for value in source.evidence() => value
        ],
        previous_event_digest?=source.previous_event_digest(),
      )
    catch {
      @storage.UnsupportedVersion(record_kind~, version="1.0.1") =>
        assert_eq(record_kind, expected_kind)
      error => fail("unexpected event-version error: \{to_repr(error)}")
    } noraise {
      _ => fail("storage admitted a substituted claim event version")
    }
  }
  // The replay validator repeats the exact-version checks even though current
  // storage constructors already reject these two substitutions at admission.
  require_dispatch_claim_event_binding_v3(candidate.claim, source)
}

///|
test "Phase2 full aggregate rejects malformed known claim and wrong wrapper" {
  for wrong_wrapper in [false, true] {
    let suffix = if wrong_wrapper { "wrong-wrapper" } else { "malformed" }
    let (fixture, store, work, governance) = try
      phase2_active_pending_fixture(suffix)
    catch {
      ReplayBindingViolation(field~) => fail("active fixture: " + field)
      error => fail("active fixture: \{to_repr(error)}")
    } noraise {
      value => value
    }
    let current = try
      fold_governed_recovery_v3(fixture.empty_effects, work, governance)
    catch {
      ReplayBindingViolation(field~) => fail("recovery fold: " + field)
      error => fail("recovery fold: \{to_repr(error)}")
    } noraise {
      value => value
    }
    let candidate = try
      current.prepare_dispatch_claim_v3(
        fixture.intent.intent_ref(),
        "phase2-tamper-claim-" + suffix,
        "phase2-tamper-source-event-" + suffix,
        "phase2-tamper-source-command-" + suffix,
        11L,
        12L,
        [
          for value in fixture.registration.schedule().evidence() => value
        ],
      )
    catch {
      ReplayBindingViolation(field~) => fail("prepare tamper: " + field)
      error => fail("prepare tamper: \{to_repr(error)}")
    } noraise {
      value => value
    }
    let source = candidate.request.events()[0]
    let payload = if wrong_wrapper {
      source.payload().payload()
    } else {
      let changed : Array[Byte] = [
        for value in source.payload().payload() => value
      ]
      changed.push(0)
      Bytes::from_array(changed)
    }
    let kind = if wrong_wrapper {
      "effect.dispatch.claimed-wrong.v3"
    } else {
      dispatch_claim_event_kind_v3
    }
    let event = phase2_claim_tampered_event(source, kind, payload, suffix)
    let tampered_request = @storage.CommitRequest::new(
      "1.0.0",
      "1.0.0",
      event.workflow(),
      work.head().revision(),
      "phase2-tamper-command-" + suffix,
      [event],
      [],
    )
    let tampered_guarded = @storage.GuardedCommitRequest::new(
      tampered_request,
      [
        for head_guard in candidate.guarded_request.guards() => head_guard
      ],
    )
    let bound = phase2_bound_dispatch_store(store, candidate)
    guard bound.guarded_commit(tampered_guarded)
      is @storage.GuardedCommitSucceeded(_) else {
      fail("generic guarded storage rejected opaque tampered fixture")
    }
    try
      fold_governed_closed_loop_v2(
        fixture.empty_effects,
        store.replay(fixture.registration.workflow()),
        governance,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("full governed aggregate accepted tampered claim: " + suffix)
    }
  }
}

///|
test "Phase2 recovery fold rejects raw unguarded claim publication" {
  let (fixture, _, work, governance) = phase2_active_pending_fixture(
    "raw-origin",
  )
  let current = fold_governed_recovery_v3(
    fixture.empty_effects,
    work,
    governance,
  )
  let candidate = current.prepare_dispatch_claim_v3(
    fixture.intent.intent_ref(),
    "phase2-raw-origin-claim",
    "phase2-raw-origin-event",
    "phase2-raw-origin-command",
    11L,
    12L,
    [
      for value in fixture.registration.schedule().evidence() => value
    ],
  )
  let unregistered = phase1c_b_combined_memory_store(work, governance)
  ignore(unregistered.commit(candidate.request))
  try
    fold_governed_recovery_v3(
      fixture.empty_effects,
      unregistered.replay(fixture.registration.workflow()),
      governance,
    )
  catch {
    ReplayBindingViolation(field="dispatch_claim_v3_commit_guards")
    | ReplayBindingViolation(field="recovery_activation_v3_commit_shape") => ()
    error => fail("unexpected raw-origin error: \{to_repr(error)}")
  } noraise {
    _ => fail("raw unguarded claim publication entered recovery state")
  }
}

///|
test "Phase2 recovery fold rejects old claim replayed under current governance" {
  for substitute_command in [false, true] {
    let suffix = if substitute_command { "command-and-guard" } else { "guard" }
    let (fixture, store, work, governance) = phase2_active_pending_fixture(
      "origin-" + suffix,
    )
    let current = fold_governed_recovery_v3(
      fixture.empty_effects,
      work,
      governance,
    )
    let candidate = current.prepare_dispatch_claim_v3(
      fixture.intent.intent_ref(),
      "phase2-origin-claim-" + suffix,
      "phase2-origin-event-" + suffix,
      "phase2-origin-command-" + suffix,
      11L,
      12L,
      [
        for value in fixture.registration.schedule().evidence() => value
      ],
    )
    let advanced = phase1c_b_append_governance_advance(
      store,
      governance,
      "phase2-origin-" + suffix,
    )
    let command_key = if substitute_command {
      "phase2-origin-substituted-command"
    } else {
      candidate.claim.command_idempotency_key
    }
    let substituted_request = @storage.CommitRequest::new(
      candidate.request.record_version().text(),
      candidate.request.schema_version().text(),
      candidate.request.workflow(),
      candidate.request.expected_revision(),
      command_key,
      [
        for event in candidate.request.events() => event
      ],
      [],
    )
    let substituted_guarded = @storage.GuardedCommitRequest::new(
      substituted_request,
      [phase2_replay_head_guard(advanced)],
    )
    let activation = store.activate_guarded_workflow(
      candidate.request.workflow(),
      [advanced.workflow()],
    )
    let bound = @storage.GuardedMemoryStore::new(store, activation)
    guard bound.guarded_commit(substituted_guarded)
      is @storage.GuardedCommitSucceeded(result) else {
      fail("generic registered storage rejected substituted replay fixture")
    }
    let claimed_work = bound.replay(fixture.registration.workflow())
    try
      fold_governed_recovery_v3(fixture.empty_effects, claimed_work, advanced)
    catch {
      ReplayBindingViolation(field="dispatch_claim_v3_commit_shape")
      | ReplayBindingViolation(field="dispatch_claim_v3_commit_guard_binding") =>
        ()
      error => fail("unexpected substituted-origin error: \{to_repr(error)}")
    } noraise {
      _ => fail("substituted governance transaction entered recovery state")
    }
    try
      mint_committed_dispatch_claim_receipt_v3(bound, candidate, result)
    catch {
      RecoveryViolation(field="dispatch_claim_v3_commit_result")
      | ReplayBindingViolation(field="dispatch_claim_v3_commit_shape")
      | ReplayBindingViolation(field="dispatch_claim_v3_commit_guard_binding") =>
        ()
      error => fail("unexpected substituted receipt error: \{to_repr(error)}")
    } noraise {
      _ => fail("substituted governance transaction minted a claim receipt")
    }
  }
}

///|
test "Phase2 dispatch claim loses atomically when governance head advances" {
  let (fixture, store, work, governance) = phase2_active_pending_fixture(
    "stale-governance",
  )
  let current = fold_governed_recovery_v3(
    fixture.empty_effects,
    work,
    governance,
  )
  let candidate = current.prepare_dispatch_claim_v3(
    fixture.intent.intent_ref(),
    "phase2-stale-governance-claim",
    "phase2-stale-governance-event",
    "phase2-stale-governance-command",
    11L,
    12L,
    [
      for value in fixture.registration.schedule().evidence() => value
    ],
  )
  let before = store.replay(fixture.registration.workflow())
  ignore(
    phase1c_b_append_governance_advance(
      store, governance, "phase2-dispatch-stale-governance",
    ),
  )
  let bound = phase2_bound_dispatch_store(store, candidate)
  guard commit_dispatch_claim_v3(bound, candidate)
    is DispatchClaimStaleGovernanceV3(_) else {
    fail("governance-only advance did not reject dispatch claim")
  }
  let after = store.replay(fixture.registration.workflow())
  assert_true(before.replay_digest() == after.replay_digest())
  assert_true(before.head() == after.head())
}
