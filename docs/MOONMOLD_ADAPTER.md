# MoonMold dispatch and attestation

MoonFlow routes MoonMold through a typed capability with semantic/live-building
operations, observe-to-workspace-mutation authority, cancellation and
reconciliation. Its claim ceiling is always `digital-artifact`.

A dispatch binds the ordinary MoonFlow adapter request to declaration revision,
source digest, accepted parent digest and representation, expected child
representation/lineage, and authority envelope.

Attestation accepts output only when request, attempt, idempotency, parent,
representation, lineage, authority, artifact digest, workspace-relative
evidence, and digital claim all match. Styled geometry cannot enter engineering;
simulation models remain digital inputs; manufacturing remains a candidate.
Physical effects and premature simulation-evidence claims fail closed.

Checkpoint reuse ignores a revision number alone but revalidates the semantic
identity. A changed source, spatial input, accepted parent, representation,
lineage, or authority invalidates all prior MoonMold artifact/evidence refs.
Exact evidence can be reused with its original identities.

## Input, output, quality

Input: capability, typed dispatch, and attributable MoonClaw/MoonMold result.

Output: `MoonMoldEvidenceMapping` plus explicit reused/invalidated checkpoint
decision.

Quality: exact digest/lineage/claim matching, no physical authority, no
simulation-evidence overclaim, stale-parent rejection, and revision-safe
invalidation.

