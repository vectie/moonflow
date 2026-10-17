# Explore shared-resource capacity before running work

Use `graph-capacity` to ask: how would this declared graph overlap if several
operations needed the same bounded resource? Import a graph and an explicit
scenario, inspect start/finish offsets and queue waits, then change capacities
or estimates and compare the exported allocation. No adapter is invoked.

```sh
moonflow graph-capacity /absolute/workspace source-graph.json capacity-one.json --json
moonflow graph-capacity /absolute/workspace source-graph.json capacity-two.json --json
moonflow graph-capacity /absolute/workspace source-graph.json capacity-one.json --csv
```

The [complete sample](../examples/graph-capacity/README.md) compares one shared
design slot with two slots. The same diamond takes 65 versus 45 hypothetical
seconds. The unlimited-capacity dependency lower bound is 45 seconds in both
scenarios. This is not a performance measurement or an expected completion time.

## Explicit scenario

```json
{
  "contract_id": "moonflow.capacity-scenario.v1",
  "graph_id": "your-exact-source-graph-id",
  "capacities": {"design": 2, "review": 1},
  "items": {
    "your-item-id": {
      "duration_seconds": 30,
      "demands": {"design": 1, "review": 1}
    }
  }
}
```

Provide exactly one `items` entry for every source item. A duration is an integer
in 1..604800 seconds. Zero-duration milestones are not supported. `demands` must
be an object; `{}` explicitly means no constrained resources. Omitted resources
have zero demand. Every specified demand is an integer in 1..256 and must not
exceed its pool's capacity. There is no implicit pool for product names, operation
names, authority, hardware, or payload contents.

The scenario declares 1..32 resource pools, each with capacity 1..256. Resource
IDs are 1..128 ASCII letters, digits, dots, hyphens, or underscores. A pool can
be unused. Units are fungible whole units of that named pool. A task may require
multiple pools, acquired together and held for its entire duration.

Unknown top-level or item fields, unknown resources/items, missing entries,
wrong types, fractional values, and demands exceeding capacity fail the whole
request. Nothing is returned as a feasible partial schedule. The complete source
graph must pass the existing declared-topology reader, including nonempty items,
known dependencies, unique item IDs, canonical authority and acyclic edges.
The source is bounded to 256 items. Duplicate dependency references have the same
one-edge structural meaning as the existing graph map. Input order need not be
topological; disconnected components are included.

## Deterministic simulation policy

1. Begin at relative second zero. At each event, complete every item finishing
   at that second and release all its resource units.
2. Scan all unscheduled items in source graph order. Start an item if every
   prerequisite has finished and all its demands fit the remaining capacities.
3. Earlier items that cannot fit reserve nothing. A later fitting item may start.
   All eligible starts at this event happen before moving to the next finish.
4. Advance to the next finish event and repeat until every item is complete.

The policy is greedy and non-preemptive. Source order is the explicit priority;
changing source order can change allocations and total duration. The policy does
not optimize makespan, choose a best capacity, guarantee monotonic improvement
when a capacity changes, reserve future slots, or enumerate alternative schedules.
There are no calendar windows, release times, transfer delays, setup costs,
failures, retries, or costs. Durations and capacities are fixed caller estimates.
Dependency completion in this simulation means the estimated duration finished;
it does not model actual review, authority or acceptance gates.

## Read the output

- `items` retains source order; `start_order` lists the chronological allocation
  order, with source-order ties.
- `dependency_ready_seconds` is the latest simulated prerequisite finish, or
  zero for roots. `resource_wait_seconds` is start minus that value. This local
  wait excludes delays already inherited from prerequisites.
- `start_seconds` and `finish_seconds` are relative offsets. Occupancy uses the
  half-open interval `[start, finish)`, so finish ties release before new starts.
- `resources` is sorted by resource ID and includes capacity and observed peak
  whole units. Each item's `demands` uses the same sorted order.
- `scenario_duration_seconds` is this policy's feasible hypothetical makespan.
  `unlimited_capacity_lower_bound_seconds` uses the existing critical-path timing
  analysis. `additional_seconds` is their difference, not a proof of avoidable
  waste or a lower bound on required extra time.
- `source_graph_digest` and `scenario_digest` bind the exact canonical JSON
  inputs. They are identities, not origin/authority proofs. Retain the input JSON
  with exported reports because the result is not a reusable live scenario store.

CSV has one quoted row per source item and a JSON-array cell for its resource
demands. The hypothetical scenario duration and unlimited lower bound are repeated
on every row. CSV escaping does not disable spreadsheet formulas; import graph
and item identifiers as text when working with untrusted graphs. The JSON report
also contains pool peaks, policy and input digests that the CSV does not repeat.

## Boundaries and API

`declared_graph_capacity_v1(graph, scenario)` returns `GraphCapacityV1`;
`graph_capacity_csv_v1(report)` exports CSV. Neither mutates the inputs. All
returned arrays are detached from the inputs. Positive durations and the 256-item
limit bound the worst-case serial horizon to 154828800 seconds without Int overflow.

The CLI uses the existing contained, regular-file artifact reader and 16 MiB
per-file read limit. Input references are relative to the selected workspace.
The command checks graph/scenario JSON only; payload files, catalog health,
resource availability, operation executability and domain schemas are not read
or qualified. It writes no graph, plan, events, run, attempts, grants or artifacts.
Errors follow the existing CLI behavior of printing to stdout with nonzero exit;
check the exit status before treating redirected output as JSON/CSV, and redirect
only to fresh output filenames.

This complements critical-path timing (unlimited capacity) and wave plans
(explicit barrier edits). It does not add a runtime scheduler or independently
advance declared work. Editing, preparation, authorization, import and actual
adapter execution remain separate existing workflows. Focused local tests and
the CLI fixture do not qualify a complete external adapter journey, installed
lifecycle, restart recovery, host canvas, company-task return, or release. The
historical broad aggregate remains incomplete and all required unrun/failed gates
remain blocking.
