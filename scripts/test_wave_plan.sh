#!/usr/bin/env bash
set -euo pipefail
SOURCE="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
export WORKER_ROOT="${WORKER_ROOT:-$(dirname "$SOURCE")/worker}"
source "${MOON_ENVIRONMENT:-/workspace/scratch/665adc5202cf/.moonsuite-background/build-readiness-20261011T131950/environment.sh}"
# The private cache pins exactly the source manifest's restored dependency graph.
if [[ -d "$WORKER_ROOT/moon/registry" ]]; then export MOON_HOME="$WORKER_ROOT/moon"; fi
TARGET="$WORKER_ROOT/build"
mkdir -p "$TARGET"
[[ $(df --output=avail -B1 "$TARGET" | tail -1) -ge 4294967296 ]] || { echo '4 GiB reserve required' >&2; exit 2; }
cd "$SOURCE"
moon check --frozen --target native --target-dir "$TARGET"
flock "$MOON_NATIVE_LOCK" moon test wave_plan_test.mbt --frozen --target native --strip -j 1 --target-dir "$TARGET"
flock "$MOON_NATIVE_LOCK" moon build cmd/main --frozen --target native --strip -j 1 --target-dir "$TARGET"
python3 "$SOURCE/scripts/verify_wave_plan.py" --cli "$TARGET/native/debug/build/cmd/main/main.exe" --workspace-parent "$WORKER_ROOT/fixtures"
