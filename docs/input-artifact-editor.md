# Edit MoonFlow input artifacts in the graph explorer

MoonFlow is the declared-work orchestration engine. This adds operator editing of each work item's input artifact list to its existing offline graph explorer. Existing prerequisite/timeouts editing stays available.

1. Render a source-backed page with `python3 -B scripts/graph_explorer.py WORKSPACE/source-graph.json explorer.html --author --cli /absolute/path/to/moonflow`.
2. Open the page locally. Select a work item, enter one workspace-relative artifact path per line, and choose **Preview input artifacts**. Blank lines are omitted. At least one unique path is required.
3. Choose **Apply** to retain the proposal locally. Cancel, Undo, and Reset are available. The changes list shows previous and new paths. Download the plan form after applying or cancelling pending edits.
4. Place the form in your chosen workspace and run `moonflow plan from-form WORKSPACE form.json input-study TIMESTAMP`, then `moonflow plan inspect WORKSPACE input-study`.
5. Use the existing `plan prepare WORKSPACE input-study catalog.json TIMESTAMP` workflow. Referenced files must actually exist; native preparation refuses missing inputs. The UI changes only declarations, never copies files or grants execution authority.

Original source JSON is embedded verbatim, including unknown fields and exact numeric spelling. Only the edited input arrays, dependencies and timeouts enter the plan-form edits. No dispatch occurs. Native schema/path/capability checks remain authoritative.

## Focused verification
`node scripts/test_input_artifact_editor.mjs emitted.html downloaded-form.json` exercises actual page handlers and Blob bytes using a DOM adapter. Existing dependency and timeout test scripts and the Python graph-renderer suite also pass. The retained R700 native CLI accepted the actual downloaded form, reopened it, refused missing edited input files, then prepared the child graph after synthetic fixtures were supplied. No native code changed or native binary rebuilt. This is not graphical-browser/accessibility or full-release qualification.
