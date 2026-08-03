#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

python3 conformance/boundary_scan.py fixture-test
./conformance/check_current_isolation.sh
moon test --target all closed_loop/contracts
moon test --target wasm closed_loop/storage
moon test --target native closed_loop/storage
moon test --target wasm closed_loop/governance
moon test --target native closed_loop/governance
moon test --target wasm closed_loop/effects
moon test --target native closed_loop/effects
moon test --target native --release closed_loop/orchestration
moon test --target native conformance/v2
moon check --target all --warn-list +73
git diff --check
