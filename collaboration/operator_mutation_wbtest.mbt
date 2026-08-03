///|
fn collab_test_digest(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
fn collab_test_human(id : String) -> @capability.PrincipalRefV1 raise {
  @capability.principal_ref_v1(id, @capability.Human, "local", id)
}

///|
fn collab_test_start(owner : @capability.PrincipalRefV1) -> Json raise {
  {
    "contract_id": "moonflow.collaboration-operator-mutation.v1",
    "workspace_id": "workspace-test",
    "action": "start",
    "mutation_id": "mutation-start",
    "actor": @capability.encode_principal_ref_v1(owner),
    "recorded_at": "2026-07-31T01:00:00Z",
    "workspace_ref": @capability.encode_workspace_ref_v1(
      @capability.workspace_ref_v1(
        "workspace-test",
        "revision-1",
        collab_test_digest("a"),
      ),
    ),
    "payload": { "owner_membership_id": "membership-owner" },
  }
}

///|
test "operator mutations replay idempotently and snapshot restart verifies" {
  let owner = collab_test_human("owner")
  guard apply_collaboration_operator_mutation_v1(None, collab_test_start(owner))
    is OperatorApplied(started, _) else {
    fail("start mutation was not applied")
  }
  let added_principal = collab_test_human("member")
  let add : Json = {
    "contract_id": "moonflow.collaboration-operator-mutation.v1",
    "workspace_id": "workspace-test",
    "action": "add-member",
    "mutation_id": "mutation-add-member",
    "actor": @capability.encode_principal_ref_v1(owner),
    "expected_head": started.head_digest().text(),
    "recorded_at": "2026-07-31T01:01:00Z",
    "payload": {
      "membership_id": "membership-member",
      "principal": @capability.encode_principal_ref_v1(added_principal),
      "roles": ["contributor"],
    },
  }
  guard apply_collaboration_operator_mutation_v1(Some(started), add)
    is OperatorApplied(updated, _) else {
    fail("member mutation was not applied")
  }
  guard apply_collaboration_operator_mutation_v1(Some(updated), add)
    is OperatorIdempotent(_, receipt) else {
    fail("exact retry did not become idempotent")
  }
  assert_true(receipt.idempotent())
  let restarted = decode_collaboration_snapshot_v1(
    encode_collaboration_snapshot_v1(updated),
  )
  assert_eq(restarted.head_digest(), updated.head_digest())
}

///|
test "backdated mutations and non-member comments fail closed" {
  let owner = collab_test_human("owner-two")
  guard apply_collaboration_operator_mutation_v1(None, collab_test_start(owner))
    is OperatorApplied(started, _) else {
    fail("start mutation was not applied")
  }
  let outsider = collab_test_human("outsider")
  let comment : Json = {
    "contract_id": "moonflow.collaboration-operator-mutation.v1",
    "workspace_id": "workspace-test",
    "action": "comment",
    "mutation_id": "mutation-comment",
    "actor": @capability.encode_principal_ref_v1(outsider),
    "expected_head": started.head_digest().text(),
    "recorded_at": "2026-07-31T01:01:00Z",
    "payload": {
      "comment_id": "comment-one",
      "subject_digest": collab_test_digest("b"),
      "anchor_ref": "artifacts/result.json",
      "body_ref": "evidence/comment.json",
      "body_digest": collab_test_digest("c"),
      "mentions": [],
    },
  }
  guard apply_collaboration_operator_mutation_v1(Some(started), comment)
    is OperatorDenied(_) else {
    fail("non-member comment was accepted")
  }
  let backdated : Json = {
    "contract_id": "moonflow.collaboration-operator-mutation.v1",
    "workspace_id": "workspace-test",
    "action": "add-member",
    "mutation_id": "mutation-backdated",
    "actor": @capability.encode_principal_ref_v1(owner),
    "expected_head": started.head_digest().text(),
    "recorded_at": "2026-07-31T00:59:00Z",
    "payload": {
      "membership_id": "membership-late",
      "principal": @capability.encode_principal_ref_v1(outsider),
      "roles": ["viewer"],
    },
  }
  guard apply_collaboration_operator_mutation_v1(Some(started), backdated)
    is OperatorDenied(_) else {
    fail("backdated mutation was accepted")
  }
}
