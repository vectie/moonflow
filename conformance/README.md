# MoonFlow conformance

Run the release-relevant MoonFlow architecture gates with:

```sh
./conformance/run.sh
```

The workflow resolves the pinned module graph before this command runs. The
command proves the frozen scanner's own negative fixtures still work, rejects
pack-owned finance, media-production, or
MoonMold vocabulary and dependencies from production code, and runs the typed
contracts, storage, governance, effects, orchestration, and golden-v2 suites on
their release-relevant targets. Native orchestration runs in release mode to
match the shipped runtime and avoid a known debug-codegen-only toolchain stall.
It finishes with target-complete declaration and warning checks, then rejects
malformed or whitespace-damaged patches before release.

The historical FLOW-2 snapshot remains reviewable and can still be audited
explicitly with `python3 conformance/boundary_scan.py scan`; its scanner and
negative fixtures can be checked independently with
`python3 conformance/boundary_scan.py fixture-test`. It is not the
current release gate: that snapshot intentionally rejects every capability
added after FLOW-2, so treating it as a current-source allowlist would make any
architectural upgrade impossible. New isolation policy belongs in
`check_current_isolation.sh`; frozen evidence is never silently rewritten.

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
