# FLOW-2/FLOW-3/FLOW-4A/FLOW-5A conformance

Run every repository-local FLOW-2 compatibility, FLOW-3 isolation, FLOW-4A
storage, and FLOW-5A pure-governance gate with:

```sh
./conformance/run.sh
```

The command is offline (`moon --frozen`), runs scanner self-tests and the real
repository scan, executes the isolated contract tests, executes portable
storage tests on wasm, wasm-gc, JavaScript, and native (including native
filesystem/C-stub tests), executes FLOW-5A governance tests on all four targets,
executes native golden and CLI containment checks, then runs the full suite on
each backend and target-complete warning checks.
It also compiles external negative fixtures and requires construction of the
opaque governed aggregate and construction/decoding of committed cancellation
governance receipts to fail at the package boundary.
Scanner diagnostics are sorted and use `path:line: RULE reason`.

The scanner approves FLOW-3 symbols only in the exact enumerated production
files and generated interface under `closed_loop/contracts`. It still scans
that package for dependencies, domain terms, secret-shaped material, durable
versioning, later-work-order symbols, and state-changing public methods.

The versioned `moonflow.flow4a-storage-surface.v2` rule approves only the exact
hashed sources, C stub, tests, manifest, and generated interface under
`closed_loop/storage`. It derives public types and qualified methods from that
interface, confines each one to the exact storage surface, and rejects
FLOW-4B-or-later effect, coordination, authority, publication, activation, and
UI/browser capability declarations.

The guarded registry extension keeps lifecycle transaction-domain authority in
that storage surface. Compile-fail fixtures require registry bindings and
activation receipts to remain opaque and undecodable, and require the official
lifecycle commit to reject caller-composed guarded stores that do not implement
the sealed registry-bound capability. Runtime tests require both memory and
filesystem stores to reject raw commits after activation and to fail closed on
missing, corrupt, stale, shadow, forked, or relocated registry state. See
`closed_loop/storage/GUARDED_REGISTRY.md` for the first-activation trust and TCB
contract.

The versioned `moonflow.flow5a-governance-surface.v1` rule approves only the
exact hashed pure-governance sources, tests, conformance fixtures, manifest,
and generated interface under `closed_loop/governance`. Its public-symbol set
is derived mechanically from the generated interface, proven clean at the
approved path, and proven exact-once outside it. FLOW-5A-specific negative
fixtures reject effect/coordination declarations, bypasses, domain vocabulary,
and contract or storage duplication while preserving all prior rules.

## Domain rule inventory

- `DOM001` rejects external product/domain identifiers.
- `DOM002` rejects pack-owned contract identifiers.
- `DOM003` rejects branches on product/pack identity.
- `DOM004` rejects representative finance and AIGC/media-production tokens or
  identifier components. Neutral runtime-contract vocabulary remains allowed.
