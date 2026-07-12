///|
test "unattended manifest requires independent reviewer and scoped outputs" {
  let invalid : UnattendedManifest = {
    contract_id: "moonflow.unattended-manifest.v1",
    gate_executable: "moongate",
    gate_arguments: ["suite", "autonomy-check"],
    max_cycles: 10,
    observer_executable: "",
    observer_arguments: [],
    drivers: [
      {
        adapter_id: "builder",
        executable: "moonrobo",
        arguments: [],
        expected_output_artifacts: ["../escape"],
        reviewer_id: "builder",
        reviewer_executable: "moonrobo",
        reviewer_arguments: [],
        review_authority_id: "reviewer",
        budget_request: {
          model_tokens: 0,
          tool_calls: 1,
          storage_bytes: 1,
          attempts: 1,
          concurrency: 1,
        },
      },
    ],
  }
  let issues = invalid.quality_issues()
  assert_true(issues.contains("reviewer identity must be independent: builder"))
  assert_true(issues.contains("invalid expected output artifact: ../escape"))
}

///|
test "unattended arguments use argv placeholders without a shell" {
  assert_true(
    render_unattended_arguments(
      ["run", "{workspace}", "{request}", "{result}", "{receipt}", "{review}"],
      "/tmp/work",
      "request.json",
      "result.json",
      "receipt.json",
      "review.json",
    ) ==
    [
      "run", "/tmp/work", "request.json", "result.json", "receipt.json", "review.json",
    ],
  )
}
