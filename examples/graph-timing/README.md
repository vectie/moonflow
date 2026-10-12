# Timing worksheet example

Use this directory as the workspace. The declared request files intentionally
are absent: timing analysis needs only topology and explicit duration estimates.

```sh
moonflow graph-timing /absolute/path/to/examples/graph-timing graph.json estimates.json --json
moonflow graph-timing /absolute/path/to/examples/graph-timing graph.json estimates.json --csv
```

Expected lower bound: 33 seconds. Critical IDs: join, left, root (source order).
Right has 15 seconds slack; isolated has 25 seconds. Change right's duration
from 5 to 40 to obtain a 53-second bound and join, right, root as critical IDs.
Graph labels include punctuation, quotes, Unicode and a newline to demonstrate
portable CSV handling. See docs/GRAPH_TIMING.md for interpretation and limits.
