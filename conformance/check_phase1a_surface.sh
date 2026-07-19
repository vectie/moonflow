#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
interface="$root/closed_loop/orchestration/pkg.generated.mbti"

work_terminal_pattern='^pub(\(all\))? (struct|enum|typealias|trait) WorkTerminalV2([[:space:]{]|$)'
if printf '%s\n' 'pub struct PreparedWorkTerminalV2 {' | \
  grep -E "$work_terminal_pattern" >/dev/null 2>&1; then
  echo 'PHASE1A_SURFACE: exact-symbol checker regression' >&2
  exit 1
fi

for forbidden in \
  'WorkTerminalV2' \
  'new_cancellation_authorization_v22' \
  'new_cancellation_request_v22' \
  'decode_retry_policy_binding_v22' \
  'decode_cancellation_governance_binding_v22' \
  'decode_initial_work_authorization_v22' \
  'prepare_schedule_registered_v2' \
  'prepare_initial_admission_v22' \
  'fold_initial_admission_bindings_v22' \
  'InitialAdmissionBindingsV2'
do
  case "$forbidden" in
    WorkTerminalV2)
      pattern=$work_terminal_pattern
      ;;
    InitialAdmissionBindingsV2)
      pattern='^pub(\(all\))? (struct|enum|typealias|trait) InitialAdmissionBindingsV2([[:space:]{]|$)'
      ;;
    *)
      pattern="^pub fn $forbidden\\("
      ;;
  esac
  if grep -E "$pattern" "$interface" >/dev/null 2>&1; then
    echo "PHASE1A_SURFACE: forbidden public symbol: $forbidden" >&2
    exit 1
  fi
done

for required in \
  'CommittedRetryPolicyBindingV2' \
  'CommittedCancellationGovernanceBindingV2' \
  'InitialWorkAuthorizationV2' \
  'CommittedCancellationGovernanceBindingReceiptV2' \
  'fold_empty_closed_loop_v22' \
  'authorize_initial_work_v22' \
  'prepare_initial_work_v22' \
  'fold_initial_work_receipt_v22' \
  'fold_root_bound_orchestration_v22' \
  'CommittedCancellationGovernanceBindingReceiptV2::validate_current' \
  'CurrentGovernedClosedLoopProjectionV2' \
  'CancellationProposalV2' \
  'CommittedCancellationGovernanceReceiptV2' \
  'CancellationAuthorizationV2' \
  'CancellationRequestV2' \
  'fold_governed_closed_loop_v2' \
  'CancellationProposalV2::new' \
  'CancellationProposalV2::source_attempt_ref' \
  'CancellationProposalV2::source_intent_ref' \
  'CancellationProposalV2::validate_current' \
  'CurrentGovernedClosedLoopProjectionV2::committed_cancellation_governance_receipt' \
  'CommittedCancellationGovernanceReceiptV2::validate_current' \
  'CancellationAuthorizationV2::from_committed_governance' \
  'CancellationRequestV2::new'
do
  if ! grep -F "$required" "$interface" >/dev/null 2>&1; then
    echo "PHASE1A_SURFACE: missing approved public symbol: $required" >&2
    exit 1
  fi
done

for forbidden_constructor in \
  'InitialWorkAuthorizationV2::new' \
  'InitialWorkAuthorizationV2::decode' \
  'CommittedCancellationGovernanceBindingReceiptV2::new' \
  'CommittedCancellationGovernanceBindingReceiptV2::decode' \
  'CurrentGovernedClosedLoopProjectionV2::new' \
  'CurrentGovernedClosedLoopProjectionV2::decode' \
  'CommittedCancellationGovernanceReceiptV2::new' \
  'CommittedCancellationGovernanceReceiptV2::decode' \
  'CancellationAuthorizationV2::new' \
  'CancellationAuthorizationV2::decode'
do
  if grep -F "$forbidden_constructor" "$interface" >/dev/null 2>&1; then
    echo "PHASE1A_SURFACE: opaque authority/receipt constructor leaked: $forbidden_constructor" >&2
    exit 1
  fi
done

prepare_signature=$(grep -F 'pub fn prepare_initial_work_v22' "$interface")
case "$prepare_signature" in
  *'InitialWorkAuthorizationV2, ScheduleRegisteredV2)'*) ;;
  *)
    echo 'PHASE1A_SURFACE: unsafe initial-work prepare signature' >&2
    exit 1
    ;;
esac

authorization_signature=$(grep -F 'pub fn CancellationAuthorizationV2::from_committed_governance' "$interface")
case "$authorization_signature" in
  *'(String, CommittedCancellationGovernanceReceiptV2, CancellationProposalV2, CurrentGovernedClosedLoopProjectionV2)'*) ;;
  *)
    echo 'PHASE1B_SURFACE: unsafe cancellation authorization signature' >&2
    exit 1
    ;;
esac

proposal_signature=$(grep -F 'pub fn CancellationProposalV2::new' "$interface")
case "$proposal_signature" in
  *'CommittedCancellationGovernanceBindingReceiptV2, ClosedLoopProjectionV2'*) ;;
  *)
    echo 'PHASE1B_SURFACE: proposal is not root-receipt and replay-projection bound' >&2
    exit 1
    ;;
esac
case "$proposal_signature" in
  *'GovernancePolicy'*|*'governance_stream'*|*'valid_until_inclusive'*)
    echo 'PHASE1B_SURFACE: raw governance policy, stream, or cutoff mint path leaked' >&2
    exit 1
    ;;
esac

governed_fold_signature=$(grep -F 'pub fn fold_governed_closed_loop_v2' "$interface")
case "$governed_fold_signature" in
  *'(@effects.EffectsProjection, @storage.ReplayResult, @storage.ReplayResult)'*) ;;
  *)
    echo 'PHASE1B_SURFACE: governed fold accepts something other than exact replay inputs' >&2
    exit 1
    ;;
esac

if grep -F 'pub fn decode_cancellation_' "$interface" >/dev/null 2>&1; then
  echo 'PHASE1B_SURFACE: raw cancellation decoder leaked' >&2
  exit 1
fi

if grep -R -F 'prepare_schedule_registered_v2' \
  "$root/closed_loop/orchestration" --include='*.mbt' >/dev/null 2>&1; then
  echo 'PHASE1A_SURFACE: legacy component-only schedule preparer or call returned' >&2
  exit 1
fi

echo 'PHASE1A_SURFACE: PASS'
