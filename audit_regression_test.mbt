///|
fn audit_request(url : String, body : Body) -> Request {
  { method: "POST", url, headers: [], body, }
}

///|
test "audit Unicode non BMP JSON pointer redacts exactly the configured key" {
  let config = RedactionConfig::default()
  config.json_paths.push("/🔑")
  let request = audit_request(
    "https://example.test/",
    Text("{\"🔑\":\"audit-secret\",\"public\":true}"),
  )
  match redact_request(request, config) {
    Err(_) => assert_true(false)
    Ok(safe) =>
      match safe.body {
        Text(value) => assert_true(!value.contains("audit-secret"))
        _ => assert_true(false)
      }
  }
}

///|
test "audit optional JSON pointer preserves Unicode correctness" {
  let config = RedactionConfig::default()
  config.optional_json_paths.push("/🔑")
  let request = audit_request(
    "https://example.test/",
    Text("{\"🔑\":\"audit-secret\"}"),
  )
  let session = Session::new_with_redaction(
    Cassette::empty(),
    Record,
    MatchConfig::default(),
    config,
  )
  assert_true(
    session.record_response(request, {
      status: 200,
      headers: [],
      body: Text("{}"),
    })
    is Ok(_),
  )
  assert_true(!session.cassette().encode().contains("audit-secret"))
}

///|
test "audit duplicate query order must not hide a changed first value" {
  let request1 = audit_request(
    "https://example.test/?role=user&role=admin",
    Empty,
  )
  let request2 = audit_request(
    "https://example.test/?role=admin&role=user",
    Empty,
  )
  assert_true(
    request_match_key(request1, MatchConfig::default()) !=
    request_match_key(request2, MatchConfig::default()),
  )
}

///|
test "audit duplicate header order must not hide a changed first value" {
  let request1 : Request = {
    method: "GET",
    url: "https://example.test/",
    headers: [
      { name: "x-mode", value: "user", },
      { name: "x-mode", value: "admin", },
    ],
    body: Empty,
  }
  let request2 : Request = {
    method: "GET",
    url: "https://example.test/",
    headers: [
      { name: "x-mode", value: "admin", },
      { name: "x-mode", value: "user", },
    ],
    body: Empty,
  }
  assert_true(
    request_match_key(request1, MatchConfig::default()) !=
    request_match_key(request2, MatchConfig::default()),
  )
}

///|
test "audit raw imported cassette replay miss must have a nonempty diagnosis" {
  let request = audit_request("https://example.test/?token=audit-secret", Empty)
  let cassette : Cassette = {
    format_version: 1,
    interactions: [
      { request, response: { status: 200, headers: [], body: Empty, }, },
    ],
  }
  let session = Session::with_defaults(cassette, StrictOffline)
  assert_true(session.replay(request) is Err(_))
  assert_true(session.diagnose(request).summary() != "no mismatch")
}

///|
test "audit overlapping JSON paths should have an order independent outcome" {
  let config = RedactionConfig::default()
  config.json_paths.push("/credentials")
  config.json_paths.push("/credentials/token")
  let request = audit_request(
    "https://example.test/",
    Text("{\"credentials\":{\"token\":\"audit-secret\"}}"),
  )
  let reversed = RedactionConfig::default()
  reversed.json_paths.push("/credentials/token")
  reversed.json_paths.push("/credentials")
  assert_eq(
    redact_request(request, config) is Ok(_),
    redact_request(request, reversed) is Ok(_),
  )
}

///|
test "audit JSON pointer leading zero array index is rejected" {
  let config = RedactionConfig::default()
  config.json_paths.push("/items/01/token")
  let request = audit_request(
    "https://example.test/",
    Text("{\"items\":[{\"token\":\"one\"},{\"token\":\"two\"}]}"),
  )
  assert_true(redact_request(request, config) is Err(_))
}

///|
test "audit required JSON pointer preserves trailing whitespace in key" {
  let config = RedactionConfig::default()
  config.json_paths.push("/token ")
  let request = audit_request(
    "https://example.test/",
    Text("{\"token \":\"audit-secret\",\"token\":\"public-value\"}"),
  )
  let policy : RedactionPolicy = {
    request: config,
    response: RedactionConfig::default(),
  }
  let session = Session::new_with_redaction_policy(
    Cassette::empty(),
    Record,
    MatchConfig::default(),
    policy,
  )
  assert_true(
    session.record_response(request, { status: 200, headers: [], body: Empty, })
    is Ok(_),
  )
  assert_true(!session.cassette().encode().contains("audit-secret"))
}

///|
test "audit contract must inspect exact JSON pointer key including whitespace" {
  let contract = ResponseContract::permissive()
  contract.json_fields.push({ path: "/id ", expected_kind: JsonNumber, })
  let response : Response = {
    status: 200,
    headers: [],
    body: Text("{\"id \":\"wrong-type\",\"id\":123}"),
  }
  assert_true(!response.validate_contract(contract).is_valid())
}

///|
test "audit optional JSON pointer preserves trailing whitespace in key" {
  let config = RedactionConfig::default()
  config.optional_json_paths.push("/token ")
  let request = audit_request(
    "https://example.test/",
    Text("{\"token \":\"audit-secret\"}"),
  )
  let policy : RedactionPolicy = {
    request: config,
    response: RedactionConfig::default(),
  }
  let session = Session::new_with_redaction_policy(
    Cassette::empty(),
    Record,
    MatchConfig::default(),
    policy,
  )
  assert_true(
    session.record_response(request, { status: 200, headers: [], body: Empty, })
    is Ok(_),
  )
  assert_true(!session.cassette().encode().contains("audit-secret"))
}
