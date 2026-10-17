# Source-backed timeout editing

Requirement evidence: MF-W01 / MF-W05. This is a bounded development workflow, not closure of either full requirement.

Generate the shipped offline editor from an original full graph:

    python -B scripts/graph_explorer.py graph.json editor.html --author --cli /path/to/pinned/moonflow

Open editor.html locally. Select a work item, enter milliseconds (1–86400000), click Preview timeout, inspect the pending value, and Apply pending changes. The changes list compares original and applied timeout. Cancel discards pending edits; switching selection discards them too. Undo reverses the entire applied edit, including simultaneous prerequisite changes. Reset restores the original declarations and can itself be undone. Download uses the existing plan-form contract and preserves original full source JSON verbatim. The page writes no workspace files and invokes no services.

Use the actual downloaded JSON with native commands:

    moonflow plan from-form WORKSPACE downloaded.json timeout-study RECORDED_AT
    moonflow plan inspect WORKSPACE timeout-study
    moonflow plan prepare WORKSPACE timeout-study catalog.json RECORDED_AT

Preparation requires valid capability catalog health and authority, and creates declarations/proposals without dispatch. This is declared timeout editing, not measured runtime timing. The source file remains unchanged. Reopening the HTML starts from its original source snapshot; save the downloaded form to retain edits.

## Evidence

    python -B scripts/verify_timeout_editor.py --cli /path/to/pinned/moonflow --workspace-parent /existing/evidence

The verifier invokes the shipped renderer, executes its actual emitted event handlers using an explicit Node DOM adapter, captures actual Blob bytes, and feeds those bytes through the retained native planner. It checks save/reopen/idempotence/prepare, unchanged inputs, frozen non-timeout fields, no runs/events, and native rejection of invalid timeouts, topology and catalog cases. Tests cover minimum/maximum, malformed numbers, preview/cancel, selection changes, combined edits, undo/reset, and original-page reload. No live-browser or rendering qualification is claimed.

The native pin is rebound to the successfully built retained R700 CLI. Every repository MoonBit/interface/C/header/module/package input is hashed against unchanged R700 inputs before reuse. No compilation, dependency rebuild, or independent binary attestation occurs. Full release, installed lifecycle, browser and external-adapter gates remain unrun and blocking.
