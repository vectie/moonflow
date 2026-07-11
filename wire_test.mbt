///|
test "Work graph import registers all items before readiness" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-generic-r1",
    "book_id": "generic",
    "declaration_revision": "r1",
    "items": [
      {
        "work_item_id": "research",
        "product_id": "moonwiki",
        "depends_on": [],
      },
      {
        "work_item_id": "validate",
        "product_id": "moonmoon",
        "depends_on": ["research"],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  let events = @moonflow.events_from_work_graph(graph)
  assert_eq(events.length(), 4)
  assert_true(events[1].kind is ItemRegistered)
  assert_true(events[2].kind is ItemRegistered)
  assert_true(events[3].kind is ItemReady)
  let projection = @moonflow.replay("flow-generic-r1", events)
  json_inspect(projection.runnable_item_ids(), content=["research"])
}

///|
test "ready event generation advances only accepted dependencies" {
  let events = [
    event(0, "event-run", RunCreated),
    event(1, "register-a", ItemRegistered, work_item_id="a", product_id="moonwiki"),
    event(2, "register-b", ItemRegistered, work_item_id="b", product_id="moonmoon", depends_on=["a"]),
    event(3, "ready-a", ItemReady, work_item_id="a"),
    event(4, "start-a", ItemStarted, work_item_id="a"),
    event(5, "accept-a", ItemAccepted, work_item_id="a"),
  ]
  let projection = @moonflow.replay("flow-selene-r1", events)
  let ready = @moonflow.ready_events(projection, "2026-07-11T00:01:00Z")
  assert_eq(ready.length(), 1)
  assert_eq(ready[0].work_item_id, "b")
}
