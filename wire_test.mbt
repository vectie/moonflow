///|
test "Work graph import registers all items before readiness" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-generic-r1",
    "book_id": "generic",
    "declaration_revision": "r1",
    "source_digest": "sha256:generic-r1",
    "items": [
      {
        "work_item_id": "research",
        "declaration_id": "research",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["reviewed evidence is attached"],
        "depends_on": [],
      },
      {
        "work_item_id": "validate",
        "declaration_id": "validate",
        "product_id": "moonmoon",
        "requested_authority": "sandbox-execution",
        "acceptance_criteria": ["simulation gate passes"],
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
  assert_eq(projection.book_id, "generic")
  assert_eq(projection.declaration_revision, "r1")
  assert_eq(projection.items[0].declaration_id, "research")
  assert_eq(projection.items[1].requested_authority, "sandbox-execution")
}

///|
test "Work graph import fails closed on missing source linkage" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-invalid-r1",
    "book_id": "invalid",
    "declaration_revision": "r1",
    "source_digest": "sha256:invalid-r1",
    "items": [
      {
        "work_item_id": "research",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["evidence is reviewed"],
        "depends_on": [],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  try @moonflow.events_from_work_graph(graph) catch {
    error => assert_true("\{error}".contains("declaration_id"))
  } noraise {
    _ => fail("expected missing declaration linkage to fail")
  }
}

///|
test "Work graph import fails closed on unknown dependencies" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-invalid-dependency-r1",
    "book_id": "invalid",
    "declaration_revision": "r1",
    "source_digest": "sha256:invalid-dependency-r1",
    "items": [
      {
        "work_item_id": "validate",
        "declaration_id": "validate",
        "product_id": "moonmoon",
        "requested_authority": "sandbox-execution",
        "acceptance_criteria": ["simulation gate passes"],
        "depends_on": ["missing-research"],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  try @moonflow.events_from_work_graph(graph) catch {
    error => assert_true("\{error}".contains("unknown dependency"))
  } noraise {
    _ => fail("expected unknown dependency to fail")
  }
}

///|
test "Work graph import fails closed on cycles" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-cycle-r1",
    "book_id": "cycle",
    "declaration_revision": "r1",
    "source_digest": "sha256:cycle-r1",
    "items": [
      {
        "work_item_id": "a",
        "declaration_id": "a",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["a passes"],
        "depends_on": ["b"],
      },
      {
        "work_item_id": "b",
        "declaration_id": "b",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["b passes"],
        "depends_on": ["a"],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  try @moonflow.events_from_work_graph(graph) catch {
    error => assert_true("\{error}".contains("dependency cycle"))
  } noraise {
    _ => fail("expected dependency cycle to fail")
  }
}

///|
test "Work graph import rejects unknown authority" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-authority-r1",
    "book_id": "authority",
    "declaration_revision": "r1",
    "source_digest": "sha256:authority-r1",
    "items": [
      {
        "work_item_id": "publish",
        "declaration_id": "publish",
        "product_id": "mooncode",
        "requested_authority": "unbounded",
        "acceptance_criteria": ["published"],
        "depends_on": [],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  try @moonflow.events_from_work_graph(graph) catch {
    error => {
      assert_true("\{error}".contains("requested_authority"))
      assert_true("\{error}".contains("unbounded"))
    }
  } noraise {
    _ => fail("expected unknown authority to fail")
  }
}

///|
test "ready event generation advances only accepted dependencies" {
  let events = [
    event(0, "event-run", RunCreated),
    event(
      1,
      "register-a",
      ItemRegistered,
      work_item_id="a",
      product_id="moonwiki",
    ),
    event(
      2,
      "register-b",
      ItemRegistered,
      work_item_id="b",
      product_id="moonmoon",
      depends_on=["a"],
    ),
    event(3, "ready-a", ItemReady, work_item_id="a"),
    event(4, "start-a", ItemStarted, work_item_id="a"),
    event(
      5,
      "accept-a",
      ItemAccepted,
      work_item_id="a",
      detail="review://a-acceptance",
    ),
  ]
  let projection = @moonflow.replay("flow-selene-r1", events)
  let ready = @moonflow.ready_events(projection, "2026-07-11T00:01:00Z")
  assert_eq(ready.length(), 1)
  assert_eq(ready[0].work_item_id, "b")
}
