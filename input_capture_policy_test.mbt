///|
test "capture policies are versioned owner-bound and reject unsupported rebinding" {
  let source = conformance_source_bundle()
  let catalog = @moonflow.compile_capability_catalog_json_v1(source)
  assert_eq(@moonflow.decode_input_capture_policies_v1(catalog).length(), 1)
  for
    (field, value) in [
      ("mode", Json::string("eval")),
      ("product_id", Json::string("other")),
      ("input_schema_ref", Json::string("other/input@1.0.0")),
      ("reference_array_field", Json::string("../escape")),
    ] {
    guard @json.parse(catalog.stringify()) is Object(fields) &&
      fields.get("input_capture_policies") is Some(Array([Object(policy)])) else {
      fail("catalog fixture")
    }
    policy[field] = value
    try @moonflow.decode_input_capture_policies_v1(Json::object(fields)) catch {
      _ => ()
    } noraise {
      _ => fail("unsupported owner capture policy must be refused")
    }
  }
  try
    @moonflow.decode_input_capture_policies_v1(
      @moonflow.compile_capability_catalog_v1(source).to_json(),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("old catalog must request explicit recompilation")
  }
}
