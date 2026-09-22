///|
fn contract_response(
  status : Int,
  headers : Array[Header],
  body : Body,
) -> Response {
  { status, headers, body, }
}

///|
test "response contract accepts status headers body and JSON field kinds" {
  let response = contract_response(
    200,
    [
      { name: "content-type", value: "application/json", },
      { name: "X-Request-Id", value: "request-secret", },
    ],
    Text("{\"user\":{\"id\":7,\"name\":\"Ada\",\"active\":true},\"items\":[]}"),
  )
  let contract : ResponseContract = {
    allowed_statuses: [200, 201],
    required_headers: ["Content-Type", "x-request-id"],
    required_header_values: [
      { name: "content-type", expected_value: "application/json", },
    ],
    body_kind: Some(ExpectTextBody),
    json_fields: [
      { path: "/user/id", expected_kind: JsonNumber, },
      { path: "user.name", expected_kind: JsonString, },
      { path: "/user/active", expected_kind: JsonBoolean, },
      { path: "/items", expected_kind: JsonArray, },
    ],
    optional_json_fields: [],
    json_array_elements: [],
  }
  let report = response.validate_contract(contract)
  assert_true(report.is_valid())
  assert_eq(report.summary(), "contract valid")
}

///|
test "response contract reports an unexpected status" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    allowed_statuses: [200, 201],
  }
  let report = contract_response(503, [], Empty).validate_contract(contract)
  assert_eq(report.violations.length(), 1)
  assert_eq(report.violations[0].kind, StatusViolation)
  assert_eq(report.violations[0].expected, "200|201")
  assert_eq(report.violations[0].actual, "503")
}

///|
test "response contract requires headers case insensitively" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    required_headers: ["Content-Type", "X-Trace"],
  }
  let response = contract_response(
    200,
    [{ name: "CONTENT-TYPE", value: "application/json", }],
    Empty,
  )
  let report = response.validate_contract(contract)
  assert_eq(report.violations.length(), 1)
  assert_eq(report.violations[0].kind, MissingHeaderViolation)
  assert_eq(report.violations[0].path, "header:x-trace")
}

///|
test "response contract checks header values without exposing them" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    required_header_values: [
      { name: "Content-Type", expected_value: "application/json", },
      { name: "X-Token", expected_value: "expected-secret", },
    ],
  }
  let report = contract_response(
    200,
    [
      { name: "content-type", value: "text/plain", },
      { name: "x-token", value: "actual-secret", },
    ],
    Empty,
  ).validate_contract(contract)
  assert_eq(report.violations.length(), 2)
  assert_eq(report.violations[0].kind, HeaderValueViolation)
  assert_eq(report.violations[0].path, "header:content-type")
  assert_true(!report.summary().contains("expected-secret"))
  assert_true(!report.summary().contains("actual-secret"))
  assert_true(report.summary().contains("header-value"))
}

///|
test "response contract reports body representation mismatch" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    body_kind: Some(ExpectBase64Body),
  }
  let report = contract_response(200, [], Text("hello")).validate_contract(
    contract,
  )
  assert_eq(report.violations.length(), 1)
  assert_eq(report.violations[0].kind, BodyKindViolation)
  assert_eq(report.violations[0].expected, "base64")
  assert_eq(report.violations[0].actual, "text")
}

///|
test "response contract reports malformed JSON without exposing the body" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    json_fields: [{ path: "/token", expected_kind: JsonString, }],
  }
  let report = contract_response(200, [], Text("{\"token\":\"private-token\"")).validate_contract(
    contract,
  )
  assert_eq(report.violations.length(), 1)
  assert_eq(report.violations[0].kind, InvalidJsonViolation)
  assert_true(!report.summary().contains("private-token"))
}

///|
test "response contract distinguishes missing JSON fields" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    json_fields: [{ path: "/user/id", expected_kind: JsonNumber, }],
  }
  let report = contract_response(200, [], Text("{\"user\":{\"name\":\"Ada\"}}")).validate_contract(
    contract,
  )
  assert_eq(report.violations.length(), 1)
  assert_eq(report.violations[0].kind, MissingJsonFieldViolation)
  assert_eq(report.violations[0].path, "/user/id")
  assert_eq(report.violations[0].actual, "missing")
}

///|
test "response contract reports JSON field types without field values" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    json_fields: [{ path: "/token", expected_kind: JsonNumber, }],
  }
  let report = contract_response(
    200,
    [{ name: "authorization", value: "Bearer private-header", }],
    Text("{\"token\":\"private-body-value\"}"),
  ).validate_contract(contract)
  assert_eq(report.violations.length(), 1)
  assert_eq(report.violations[0].kind, JsonTypeViolation)
  assert_eq(report.violations[0].actual, "string")
  let summary = report.summary()
  assert_true(!summary.contains("private-header"))
  assert_true(!summary.contains("private-body-value"))
}

///|
test "response contract supports pointer array indexes and dot shorthand" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    json_fields: [
      { path: "/items/0/id", expected_kind: JsonNumber, },
      { path: "meta.ready", expected_kind: JsonBoolean, },
      { path: "/meta", expected_kind: JsonObject, },
    ],
  }
  let report = contract_response(
    200,
    [],
    Text("{\"items\":[{\"id\":1}],\"meta\":{\"ready\":false}}"),
  ).validate_contract(contract)
  assert_true(report.is_valid())
}

///|
test "response contract permits absent optional fields but checks them when present" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    optional_json_fields: [
      { path: "/next_page", expected_kind: JsonString, },
      { path: "/debug", expected_kind: JsonBoolean, },
    ],
  }
  let absent = contract_response(200, [], Text("{\"items\":[]}")).validate_contract(
    contract,
  )
  assert_true(absent.is_valid())
  let wrong = contract_response(200, [], Text("{\"next_page\":17}")).validate_contract(
    contract,
  )
  assert_eq(wrong.violations.length(), 1)
  assert_eq(wrong.violations[0].kind, JsonTypeViolation)
  assert_eq(wrong.violations[0].path, "/next_page")
}

///|
test "response contract validates direct array element kinds" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    json_array_elements: [{ path: "/items", expected_kind: JsonObject, }],
  }
  let valid = contract_response(
    200,
    [],
    Text("{\"items\":[{\"id\":1},{\"id\":2}]}"),
  ).validate_contract(contract)
  assert_true(valid.is_valid())
  let invalid = contract_response(
    200,
    [],
    Text("{\"items\":[{\"id\":1},\"bad\"]}"),
  ).validate_contract(contract)
  assert_eq(invalid.violations.length(), 1)
  assert_eq(invalid.violations[0].kind, JsonTypeViolation)
  assert_eq(invalid.violations[0].path, "/items/1")
  assert_eq(invalid.violations[0].actual, "string")
}

///|
test "response contract reports invalid rule paths as data" {
  let contract : ResponseContract = {
    ..ResponseContract::permissive(),
    json_fields: [{ path: "$.bad//path", expected_kind: JsonString, }],
  }
  let report = contract_response(200, [], Text("{\"bad\":\"value\"}")).validate_contract(
    contract,
  )
  assert_eq(report.violations.length(), 1)
  assert_eq(report.violations[0].kind, InvalidJsonPathViolation)
}

///|
test "response contract emits violations in a stable review order" {
  let contract : ResponseContract = {
    allowed_statuses: [200],
    required_headers: ["content-type"],
    required_header_values: [],
    body_kind: Some(ExpectEmptyBody),
    json_fields: [{ path: "/id", expected_kind: JsonNumber, }],
    optional_json_fields: [],
    json_array_elements: [],
  }
  let report = contract_response(500, [], Text("not-json")).validate_contract(
    contract,
  )
  assert_eq(
    report.summary(),
    "contract violations: 4\n" +
    "status status: expected 200, actual 500\n" +
    "missing-header header:content-type: expected present, actual missing\n" +
    "body-kind body: expected empty, actual text\n" +
    "invalid-json body: expected valid JSON text, actual invalid JSON",
  )
}
