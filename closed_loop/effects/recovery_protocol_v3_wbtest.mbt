///|
test "phase2 recovery protocol v3 codecs round trip every closed value" {
  let outcomes = [
    RecoveryKnownSucceededV3,
    RecoveryKnownFailedV3,
    RecoveryConfirmedNotAppliedV3,
    RecoveryStillUnknownV3,
  ]
  for value in outcomes {
    assert_true(
      decode_external_recovery_outcome_v3(
        encode_external_recovery_outcome_v3(value),
      ) ==
      value,
    )
  }
  let states = [
    RecoveryDispatchEligibleV3,
    RecoveryDispatchClaimedV3,
    RecoveryDispatchAttemptedV3,
    RecoveryKnownSuccessV3,
    RecoveryKnownFailureV3,
    RecoveryUnknownRequiresReconciliationV3,
    RecoveryReconciliationClaimedV3,
    RecoveryReconciledSuccessV3,
    RecoveryReconciledFailureV3,
    RecoveryConfirmedNotAppliedRetryEligibleV3,
    RecoveryBackoffPendingV3,
    RecoveryExhaustedV3,
    RecoveryManualInterventionV3,
  ]
  for value in states {
    assert_true(
      decode_effect_recovery_state_v3(encode_effect_recovery_state_v3(value)) ==
      value,
    )
  }
}

///|
test "phase2 recovery protocol v3 codecs reject trailing bytes" {
  let bytes = encode_effect_recovery_state_v3(RecoveryDispatchClaimedV3)
  let changed : Array[Byte] = [ for value in bytes => value ]
  changed.push(0)
  try decode_effect_recovery_state_v3(Bytes::from_array(changed)) catch {
    MalformedRecord(field="trailing_bytes") => ()
    _ => fail("expected strict trailing-byte rejection")
  } noraise {
    _ => fail("expected strict trailing-byte rejection")
  }
}
