# Revised company task return qualification

MoonProj's `docs/FLOW_REVISED_TASKS.md` defines the owner-facing CLI and existing
authenticated gateway path. It captures a canonical task revision, separately
approves the complete Flow request, preserves immutable adapter attempt evidence,
and returns the saved exact report with its original idempotency key. A changed
task needs a new binding and fresh approval. Report retry never executes work.

MoonFlow does not import company policy or add a scheduler. The native serialized
fixture in `integration/company_return` reads the actual Proj request/result,
constructs declared work, replays submission and reconciliation, refuses altered
result/review identities, and creates an exact synthetic review receipt. A second
gateway wire replay returns that receipt as content-addressed report evidence.
Internal Flow acceptance and company/customer/cash outcomes remain separate.

The fixture uses `MOONPROJ_FLOW_V2_FIXTURE_POINTER` only when explicitly configured.
The reproducible sequence is Proj adapter fixtures, Proj gateway HTTP fixture,
this native Flow fixture, Proj gateway HTTP fixture again with the exact review,
then Proj company service normalizer fixtures. Each process rereads serialized
workspace files; no live object sharing or product source dependency is added.

This qualifies deterministic local interoperability and replay. The HTTP company
store and identity are synthetic. Actual PostgreSQL persistence/restart,
configured signing identity, deployed gateway, providers and customer acceptance
are separate release qualifications.
