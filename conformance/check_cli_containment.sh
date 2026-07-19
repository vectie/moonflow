#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/moonflow-flow2-paths.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

workspace="$tmp/workspace"
outside="$tmp/outside"
mkdir -p "$workspace/artifacts" "$outside"
printf '%s\n' "safe evidence" >"$workspace/artifacts/safe.txt"
printf '%s\n' "outside evidence" >"$outside/evidence.txt"
ln -s "$outside/evidence.txt" "$workspace/artifacts/symlink-file"
ln -s "$outside" "$workspace/artifacts/symlink-directory"

cd "$root"
moon run --frozen --target native cmd/main -- \
  import-graph "$workspace" conformance/golden/v2/work-graph.json >/dev/null
moon run --frozen --target native cmd/main -- \
  transition "$workspace" flow2-golden-v2 work-observe artifact \
  2026-07-16T00:01:00Z artifacts/safe.txt >/dev/null

expect_rejected() {
  label=$1
  artifact=$2
  reason=$3
  output="$tmp/$label.log"
  if moon run --frozen --target native cmd/main -- \
    transition "$workspace" flow2-golden-v2 work-observe artifact \
    2026-07-16T00:01:01Z "$artifact" >"$output" 2>&1
  then
    printf '%s\n' "PATH-RUNTIME: $label unexpectedly succeeded" >&2
    return 1
  fi
  if ! grep -F "$reason" "$output" >/dev/null
  then
    printf '%s\n' "PATH-RUNTIME: $label failed for an unexpected reason" >&2
    sed -n '1,20p' "$output" >&2
    return 1
  fi
}

expect_rejected absolute-path "$outside/evidence.txt" "workspace-relative path"
expect_rejected traversal-path ../outside/evidence.txt "workspace-relative path"
expect_rejected symlink-file artifacts/symlink-file "resolves outside workspace"
expect_rejected realpath-directory-escape \
  artifacts/symlink-directory/evidence.txt "resolves outside workspace"

printf '%s\n' \
  "FLOW-2 CLI containment: PASS (relative success; absolute, traversal, symlink, and realpath escape rejected)"
