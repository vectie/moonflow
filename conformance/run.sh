#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

python3 conformance/boundary_scan.py self-test
python3 conformance/boundary_scan.py scan
python3 conformance/check_phase1c_package_graph.py
./conformance/check_cli_containment.sh
./conformance/check_phase1a_surface.sh
./conformance/check_phase1b_surface.sh
./conformance/check_phase1b_compile_fail.sh
moon test --frozen --target all closed_loop/contracts
moon test --frozen --target wasm closed_loop/storage
moon test --frozen --target wasm-gc closed_loop/storage
moon test --frozen --target js closed_loop/storage
moon test --frozen --target native closed_loop/storage
moon test --frozen --target wasm closed_loop/governance
moon test --frozen --target wasm-gc closed_loop/governance
moon test --frozen --target js closed_loop/governance
moon test --frozen --target native closed_loop/governance
moon test --frozen --target wasm closed_loop/effects
moon test --frozen --target wasm-gc closed_loop/effects
moon test --frozen --target js closed_loop/effects
moon test --frozen --target native closed_loop/effects
moon test --frozen --target wasm closed_loop/orchestration
moon test --frozen --target wasm-gc closed_loop/orchestration
moon test --frozen --target js closed_loop/orchestration
moon test --frozen --target native closed_loop/orchestration
moon test --frozen --target native conformance/v2
moon test --frozen --target wasm
moon test --frozen --target wasm-gc
moon test --frozen --target js
moon test --frozen --target native
moon check --frozen --target all --warn-list +73
