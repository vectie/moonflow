#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_root="$root/conformance/compile_fail"
work=$(mktemp -d "$root/conformance/.phase1b-compile-fail.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cp "$fixture_root/moon.pkg.fixture" "$work/moon.pkg"

for fixture in \
  current_governed_construct \
  current_governed_decode \
  current_governed_mutate \
  receipt_construct \
  receipt_decode \
  open_authority_construct \
  open_authority_decode \
  open_operation_construct \
  open_operation_decode \
  inflight_authority_construct \
  inflight_authority_decode \
  dispatch_authorization_construct \
  dispatch_authorization_decode \
  dispatch_observation_construct \
  dispatch_observation_decode \
  guarded_dispatch_call_construct \
  guarded_dispatch_call_decode \
  attempt_authorization_construct \
  attempt_authorization_decode \
  guarded_attempt_call_construct \
  guarded_attempt_call_decode \
  lease_settlement_construct \
  lease_settlement_decode \
  terminal_receipt_construct \
  terminal_receipt_decode \
  work_terminal_record_construct \
  work_terminal_record_decode \
  effect_terminal_source_construct \
  effect_terminal_source_decode \
  retry_eligibility_receipt_construct \
  retry_eligibility_receipt_decode \
  prepared_work_terminal_construct \
  prepared_work_terminal_decode \
  generic_work_terminal_prepare \
  guarded_retry_request_construct \
  guarded_retry_request_decode \
  guarded_atomic_retry_construct \
  guarded_atomic_retry_decode \
  prepared_cancellation_construct \
  prepared_cancellation_decode \
  workflow_head_guard_construct \
  workflow_head_guard_decode \
  guarded_commit_request_construct \
  guarded_commit_request_decode \
  guarded_workflow_binding_construct \
  guarded_workflow_binding_decode \
  guarded_activation_receipt_construct \
  guarded_activation_receipt_decode \
  guard_conflict_receipt_construct \
  guard_conflict_receipt_decode \
  stale_governance_lifecycle_receipt_construct \
  stale_governance_lifecycle_receipt_decode \
  prepared_cancellation_lifecycle_conversion \
  prepared_work_terminal_lifecycle_conversion \
  guarded_atomic_retry_lifecycle_conversion \
  lifecycle_candidate_construct \
  lifecycle_candidate_decode \
  lifecycle_committed_receipt_construct \
  lifecycle_committed_receipt_decode \
  lifecycle_loss_receipt_construct \
  lifecycle_loss_receipt_decode \
  retry_currentness_construct \
  retry_currentness_decode \
  raw_lifecycle_seal \
  unbound_guarded_lifecycle_capability \
  inflight_dispatch_misuse \
  inflight_new_work_misuse \
  open_fact_commit_misuse \
  raw_effect_prepare \
  raw_dispatch_listing \
  raw_lease_prepare \
  raw_retry_prepare \
  raw_v1_prepare \
  unrestricted_commit
do
  cp "$fixture_root/$fixture.mbt.fixture" "$work/$fixture.mbt"
  if moon check --frozen --target native "$work" >"$work/$fixture.log" 2>&1; then
    echo "PHASE1B_COMPILE_FAIL: fixture unexpectedly compiled: $fixture" >&2
    exit 1
  fi
  case "$fixture" in
    current_governed_construct)
      grep -F 'CurrentGovernedClosedLoopProjectionV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    current_governed_decode)
      grep -F 'CurrentGovernedClosedLoopProjectionV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    current_governed_mutate)
      grep -F 'cancellation_authoritative' "$work/$fixture.log" >/dev/null
      ;;
    receipt_construct)
      grep -F 'CommittedCancellationGovernanceReceiptV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    receipt_decode)
      grep -F 'CommittedCancellationGovernanceReceiptV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    open_authority_construct)
      grep -F 'OpenWorkAuthorityV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    open_authority_decode)
      grep -F 'OpenWorkAuthorityV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    open_operation_construct)
      grep -F 'OpenWorkOperationAuthorizationV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    open_operation_decode)
      grep -F 'OpenWorkOperationAuthorizationV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    inflight_authority_construct)
      grep -F 'InFlightResolutionAuthorityV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    inflight_authority_decode)
      grep -F 'InFlightResolutionAuthorityV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    dispatch_authorization_construct)
      grep -F 'GuardedDispatchAuthorizationV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    dispatch_authorization_decode)
      grep -F 'GuardedDispatchAuthorizationV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    dispatch_observation_construct)
      grep -F 'GuardedDispatchObservationV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    dispatch_observation_decode)
      grep -F 'GuardedDispatchObservationV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    guarded_dispatch_call_construct)
      grep -F 'GuardedDispatchCallV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    guarded_dispatch_call_decode)
      grep -F 'GuardedDispatchCallV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    attempt_authorization_construct)
      grep -F 'GuardedAttemptAuthorizationV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    attempt_authorization_decode)
      grep -F 'GuardedAttemptAuthorizationV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    guarded_attempt_call_construct)
      grep -F 'GuardedAttemptCallV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    guarded_attempt_call_decode)
      grep -F 'GuardedAttemptCallV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    lease_settlement_construct)
      grep -F 'LeaseSettlementAuthorizationV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    lease_settlement_decode)
      grep -F 'LeaseSettlementAuthorizationV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    terminal_receipt_construct)
      grep -F 'CommittedWorkTerminalReceiptV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    terminal_receipt_decode)
      grep -F 'CommittedWorkTerminalReceiptV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    work_terminal_record_construct)
      grep -F 'WorkTerminalRecordV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    work_terminal_record_decode)
      grep -F 'WorkTerminalRecordV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    effect_terminal_source_construct)
      grep -F 'CommittedEffectTerminalSourceV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    effect_terminal_source_decode)
      grep -F 'CommittedEffectTerminalSourceV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    retry_eligibility_receipt_construct)
      grep -F 'CommittedRetryEligibilityReceiptV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    retry_eligibility_receipt_decode)
      grep -F 'CommittedRetryEligibilityReceiptV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    prepared_work_terminal_construct)
      grep -F 'PreparedWorkTerminalV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    prepared_work_terminal_decode)
      grep -F 'PreparedWorkTerminalV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    generic_work_terminal_prepare)
      grep -F 'Value prepare_effect_work_terminal_v22 not found in package `orchestration`' "$work/$fixture.log" >/dev/null
      ;;
    guarded_retry_request_construct)
      grep -F 'GuardedRetryScheduleRequestV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    guarded_retry_request_decode)
      grep -F 'GuardedRetryScheduleRequestV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    guarded_atomic_retry_construct)
      grep -F 'GuardedAtomicRetryV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    guarded_atomic_retry_decode)
      grep -F 'GuardedAtomicRetryV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    prepared_cancellation_construct)
      grep -F 'PreparedCancellationV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    prepared_cancellation_decode)
      grep -F 'PreparedCancellationV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    workflow_head_guard_construct)
      grep -F 'WorkflowHeadGuard' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    workflow_head_guard_decode)
      grep -F 'WorkflowHeadGuard has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    guarded_commit_request_construct)
      grep -F 'GuardedCommitRequest' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    guarded_commit_request_decode)
      grep -F 'GuardedCommitRequest has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    guarded_workflow_binding_construct)
      grep -F 'GuardedWorkflowBinding' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    guarded_workflow_binding_decode)
      grep -F 'GuardedWorkflowBinding has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    guarded_activation_receipt_construct)
      grep -F 'GuardedWorkflowActivationReceipt' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    guarded_activation_receipt_decode)
      grep -F 'GuardedWorkflowActivationReceipt has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    guard_conflict_receipt_construct)
      grep -F 'GuardConflictReceipt' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    guard_conflict_receipt_decode)
      grep -F 'GuardConflictReceipt has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    stale_governance_lifecycle_receipt_construct)
      grep -F 'StaleGovernanceLifecycleReceiptV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    stale_governance_lifecycle_receipt_decode)
      grep -F 'StaleGovernanceLifecycleReceiptV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    prepared_cancellation_lifecycle_conversion)
      grep -F 'PreparedCancellationV2 has no method lifecycle_candidate' "$work/$fixture.log" >/dev/null
      ;;
    prepared_work_terminal_lifecycle_conversion)
      grep -F 'PreparedWorkTerminalV2 has no method lifecycle_candidate' "$work/$fixture.log" >/dev/null
      ;;
    guarded_atomic_retry_lifecycle_conversion)
      grep -F 'GuardedAtomicRetryV2 has no method lifecycle_candidate' "$work/$fixture.log" >/dev/null
      ;;
    lifecycle_candidate_construct)
      grep -F 'LifecycleCommitCandidateV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    lifecycle_candidate_decode)
      grep -F 'LifecycleCommitCandidateV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    lifecycle_committed_receipt_construct)
      grep -F 'CommittedLifecycleCandidateReceiptV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    lifecycle_committed_receipt_decode)
      grep -F 'CommittedLifecycleCandidateReceiptV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    lifecycle_loss_receipt_construct)
      grep -F 'LifecycleRaceLossReceiptV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    lifecycle_loss_receipt_decode)
      grep -F 'LifecycleRaceLossReceiptV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    retry_currentness_construct)
      grep -F 'RetryPreparationCurrentnessV2' "$work/$fixture.log" >/dev/null
      grep -F 'Cannot create values of the read-only type' "$work/$fixture.log" >/dev/null
      ;;
    retry_currentness_decode)
      grep -F 'RetryPreparationCurrentnessV2 has no method decode' "$work/$fixture.log" >/dev/null
      ;;
    raw_lifecycle_seal)
      grep -F 'Value seal_lifecycle_candidate_v2 not found in package `orchestration`' "$work/$fixture.log" >/dev/null
      ;;
    unbound_guarded_lifecycle_capability)
      grep -F 'RegistryBoundGuardedStoragePort' "$work/$fixture.log" >/dev/null
      ;;
    inflight_dispatch_misuse)
      grep -F 'GuardedDispatchAuthorizationV2' "$work/$fixture.log" >/dev/null
      grep -F 'InFlightResolutionAuthorityV2' "$work/$fixture.log" >/dev/null
      ;;
    inflight_new_work_misuse)
      grep -F 'OpenWorkAuthorityV2' "$work/$fixture.log" >/dev/null
      grep -F 'InFlightResolutionAuthorityV2' "$work/$fixture.log" >/dev/null
      ;;
    open_fact_commit_misuse)
      grep -F 'InFlightResolutionAuthorityV2' "$work/$fixture.log" >/dev/null
      grep -F 'OpenWorkAuthorityV2' "$work/$fixture.log" >/dev/null
      ;;
    raw_effect_prepare)
      grep -F 'Value prepare_effect_commit not found in package `effects`' "$work/$fixture.log" >/dev/null
      ;;
    raw_dispatch_listing)
      grep -F 'EffectsProjection has no method dispatch_eligible_intents' "$work/$fixture.log" >/dev/null
      ;;
    raw_lease_prepare)
      grep -F 'Value prepare_lease_claimed_v2 not found in package `orchestration`' "$work/$fixture.log" >/dev/null
      ;;
    raw_retry_prepare)
      grep -F 'Value prepare_atomic_retry_v2 not found in package `orchestration`' "$work/$fixture.log" >/dev/null
      ;;
    raw_v1_prepare)
      grep -F 'Value prepare_schedule_event not found in package `orchestration`' "$work/$fixture.log" >/dev/null
      ;;
    unrestricted_commit)
      grep -F 'Value commit_orchestration_v2 not found in package `orchestration`' "$work/$fixture.log" >/dev/null
      ;;
  esac
  if grep -E 'package .*not found|unbound package|module .*not found' \
    "$work/$fixture.log" >/dev/null 2>&1; then
    echo "PHASE1B_COMPILE_FAIL: fixture failed before privacy check: $fixture" >&2
    exit 1
  fi
  rm -f "$work/$fixture.mbt"
done

if python3 "$root/conformance/check_phase1c_package_graph.py" \
  --probe-private-import-manifest \
  "$fixture_root/private_internal_import.moon.pkg.fixture" \
  >"$work/private_internal_import.log" 2>&1
then
  echo "PHASE1B_COMPILE_FAIL: fixture unexpectedly passed: private_internal_import" >&2
  exit 1
fi
grep -F 'first-party package vectie/moonflow/conformance/compile_fail_probe imports private vectie/moonflow/closed_loop/orchestration/internal/decision' \
  "$work/private_internal_import.log" >/dev/null

echo 'PHASE1B_COMPILE_FAIL: opaque construction, decoding, raw sealing, unbound guarded capabilities, private imports, and mutation surfaces rejected'
