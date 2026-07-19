#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
orchestration="$root/closed_loop/orchestration/pkg.generated.mbti"
effects="$root/closed_loop/effects/pkg.generated.mbti"
storage="$root/closed_loop/storage/pkg.generated.mbti"

for forbidden in \
  'prepare_attempt_registration_event' \
  'prepare_effect_commit' \
  'prepare_dispatch_observation_commit' \
  'prepare_effect_receipt_commit' \
  'prepare_reconciliation_request_commit' \
  'prepare_reconciliation_resolution_commit' \
  'dispatch_eligible_intents' \
  'AttemptAdapterPort' \
  'EffectDispatcherPort'
do
  if grep -F "$forbidden" "$effects" >/dev/null 2>&1; then
    echo "PHASE1B_SURFACE: raw effects symbol leaked: $forbidden" >&2
    exit 1
  fi
done

for forbidden in \
  'PreparedCancellationV2::lifecycle_candidate' \
  'PreparedWorkTerminalV2::lifecycle_candidate' \
  'GuardedAtomicRetryV2::lifecycle_candidate' \
  'seal_lifecycle_candidate_v2'
do
  if grep -F "pub fn $forbidden" "$orchestration" >/dev/null 2>&1; then
    echo "PHASE1B_SURFACE: lifecycle provenance bypass leaked: $forbidden" >&2
    exit 1
  fi
done

for forbidden in \
  'mint_effect_terminal_source_v2' \
  'mint_retry_eligibility_receipt_v2' \
  'decode_committed_retry_eligibility_receipt_v2'
do
  if grep -F "pub fn $forbidden" "$effects" >/dev/null 2>&1; then
    echo "PHASE1B_SURFACE: raw terminal-proof symbol leaked: $forbidden" >&2
    exit 1
  fi
done

for forbidden in \
  'prepare_retry_schedule_request_v2' \
  'prepare_atomic_retry_v2' \
  'prepare_lease_claimed_v2' \
  'prepare_lease_renewed_v2' \
  'prepare_lease_released_v2' \
  'prepare_lease_expired_v2' \
  'prepare_lease_reclaimed_v2' \
  'commit_orchestration_v2' \
  'prepare_schedule_event' \
  'prepare_clock_event' \
  'prepare_claim_event' \
  'prepare_renewal_event' \
  'prepare_release_event' \
  'prepare_expiry_event' \
  'prepare_cancellation_event' \
  'prepare_retry_event'
do
  if grep -F "pub fn $forbidden" "$orchestration" >/dev/null 2>&1; then
    echo "PHASE1B_SURFACE: raw orchestration symbol leaked: $forbidden" >&2
    exit 1
  fi
done


for forbidden in \
  'seal_work_terminal_v22' \
  'decode_work_terminal_record_v22' \
  'classify_effect_failure_terminal_v22' \
  'prepare_effect_work_terminal_v22' \
  'require_no_event_after_work_terminal_v22'
do
  if grep -F "pub fn $forbidden" "$orchestration" >/dev/null 2>&1; then
    echo "PHASE1B_SURFACE: raw work-terminal symbol leaked: $forbidden" >&2
    exit 1
  fi
done

for required in \
  'OpenWorkAuthorityV2' \
  'OpenWorkOperationAuthorizationV2' \
  'InFlightResolutionAuthorityV2' \
  'GuardedDispatchAuthorizationV2' \
  'GuardedDispatchObservationV2' \
  'GuardedAttemptAuthorizationV2' \
  'LeaseSettlementAuthorizationV2' \
  'WorkTerminalRecordV2' \
  'PreparedWorkTerminalV2' \
  'CommittedWorkTerminalReceiptV2' \
  'CommittedEffectTerminalSourceV2' \
  'CommittedRetryEligibilityReceiptV2' \
  'strict_dispatch_target_v2' \
  'dispatch_guarded_effect_v2' \
  'observe_guarded_attempt_v2' \
  'prepare_guarded_attempt_registration_v2' \
  'prepare_guarded_effect_intent_v2' \
  'prepare_guarded_dispatch_observation_v2' \
  'prepare_guarded_effect_receipt_v2' \
  'prepare_guarded_reconciliation_request_v2' \
  'prepare_guarded_reconciliation_resolution_v2' \
  'prepare_guarded_lease_claimed_v2' \
  'prepare_guarded_lease_renewed_v2' \
  'prepare_guarded_lease_reclaimed_v2' \
  'prepare_guarded_lease_released_v2' \
  'prepare_guarded_lease_expired_v2' \
  'prepare_guarded_retry_schedule_request_v2' \
  'prepare_guarded_atomic_retry_v2' \
  'prepare_cancellation_v2' \
  'prepare_succeeded_work_terminal_v2' \
  'prepare_cancelled_after_reconciled_not_applied_work_terminal_v2' \
  'prepare_failed_work_terminal_v2' \
  'prepare_retry_proven_failure_work_terminal_v2' \
  'prepare_retry_exhausted_work_terminal_v2'
do
  if ! grep -F "$required" "$orchestration" "$effects" >/dev/null 2>&1; then
    echo "PHASE1B_SURFACE: required guarded symbol missing: $required" >&2
    exit 1
  fi
done

for required in \
  'prepare_lifecycle_cancellation_candidate_v2' \
  'prepare_lifecycle_succeeded_work_terminal_candidate_v2' \
  'prepare_lifecycle_cancelled_after_reconciled_not_applied_work_terminal_candidate_v2' \
  'prepare_lifecycle_failed_work_terminal_candidate_v2' \
  'prepare_lifecycle_retry_proven_failure_work_terminal_candidate_v2' \
  'prepare_lifecycle_retry_exhausted_work_terminal_candidate_v2' \
  'prepare_lifecycle_atomic_retry_candidate_v2' \
  'prepare_lifecycle_lease_claim_candidate_v2' \
  'prepare_lifecycle_reconciliation_request_candidate_v2' \
  'prepare_lifecycle_reconciliation_resolution_candidate_v2' \
  'prepare_lifecycle_lease_expiry_candidate_v2' \
  'prepare_lifecycle_lease_reclaim_candidate_v2'
do
  signature=$(grep -F "pub fn $required" "$orchestration" || true)
  if [ -z "$signature" ]; then
    echo "PHASE1B_SURFACE: governed lifecycle factory missing: $required" >&2
    exit 1
  fi
  case "$signature" in
    *'PreparedCancellationV2'*|*'PreparedWorkTerminalV2'*|*'GuardedAtomicRetryV2'*|*'GuardedCommitRequest'*|*'WorkflowHeadGuard'*|*'LifecycleCandidateCategoryV2'*)
      echo "PHASE1B_SURFACE: unsafe lifecycle factory input: $required" >&2
      exit 1
      ;;
  esac
done

for opaque in \
  'OpenWorkAuthorityV2' \
  'OpenWorkOperationAuthorizationV2' \
  'InFlightResolutionAuthorityV2' \
  'GuardedDispatchAuthorizationV2' \
  'GuardedDispatchObservationV2' \
  'GuardedAttemptAuthorizationV2' \
  'LeaseSettlementAuthorizationV2' \
  'WorkTerminalRecordV2' \
  'PreparedWorkTerminalV2' \
  'CommittedWorkTerminalReceiptV2'
do
  if grep -E "${opaque}::(new|decode)" "$orchestration" >/dev/null 2>&1; then
    echo "PHASE1B_SURFACE: opaque authority constructor/decoder leaked: $opaque" >&2
    exit 1
  fi
done

for opaque in \
  'WorkflowHeadGuard' \
  'GuardedCommitRequest' \
  'GuardConflictReceipt'
do
  if grep -F "pub(all) struct $opaque" "$storage" >/dev/null 2>&1 ||
    grep -F "$opaque::decode" "$storage" >/dev/null 2>&1; then
    echo "PHASE1B_SURFACE: opaque guarded-storage value leaked: $opaque" >&2
    exit 1
  fi
done

if grep -F 'pub(all) struct StaleGovernanceLifecycleReceiptV2' "$orchestration" >/dev/null 2>&1 ||
  grep -F 'StaleGovernanceLifecycleReceiptV2::decode' "$orchestration" >/dev/null 2>&1; then
  echo 'PHASE1B_SURFACE: stale-governance lifecycle receipt is not opaque' >&2
  exit 1
fi


for opaque in \
  'CommittedEffectTerminalSourceV2' \
  'CommittedRetryEligibilityReceiptV2'
do
  if grep -E "${opaque}::(new|decode)" "$effects" >/dev/null 2>&1; then
    echo "PHASE1B_SURFACE: opaque terminal proof constructor/decoder leaked: $opaque" >&2
    exit 1
  fi
done

echo 'PHASE1B_SURFACE: PASS'
