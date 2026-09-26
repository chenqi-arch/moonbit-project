///|
fn reliability_request(url : String) -> Request {
  {
    method: "GET",
    url,
    headers: [{ name: "accept", value: "application/json", }],
    body: Empty,
  }
}

///|
fn reliability_response(status : Int, body : String) -> Response {
  {
    status,
    headers: [{ name: "content-type", value: "application/json", }],
    body: Text(body),
  }
}

///|
fn reliability_cassette(request : Request, response : Response) -> Cassette {
  {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [{ request, response, }],
  }
}

///|
test "reliability: replay hit never invokes the supplied transport" {
  let request = reliability_request("https://example.test/v1/items?page=1")
  let cassette = reliability_cassette(
    request,
    reliability_response(200, "{\"items\":[]}"),
  )
  let network_probe = ScriptedTransport::new([
    reliability_response(599, "{\"unexpected\":true}"),
  ])
  let session = Session::with_defaults(cassette, Replay)
  match session.send(request, request => network_probe.send(request)) {
    Ok(response) => assert_eq(response.status, 200)
    Err(_) => assert_true(false)
  }
  assert_eq(network_probe.remaining(), 1)
}

///|
test "reliability: replay miss fails closed without transport fallback" {
  let recorded = reliability_request("https://example.test/v1/items?page=1")
  let actual = reliability_request("https://example.test/v1/items?page=2")
  let cassette = reliability_cassette(
    recorded,
    reliability_response(200, "{\"items\":[]}"),
  )
  let network_probe = ScriptedTransport::new([
    reliability_response(599, "{\"unexpected\":true}"),
  ])
  let session = Session::with_defaults(cassette, StrictOffline)
  match session.send(actual, request => network_probe.send(request)) {
    Err(ReplayMiss(_)) => ()
    _ => assert_true(false)
  }
  assert_eq(network_probe.remaining(), 1)
}

///|
test "reliability: cassette encoding stays byte stable across 100 round trips" {
  let expected = example_cassette().encode()
  let mut current = expected
  for _ in 0..<100 {
    current = Cassette::decode(current).encode()
    assert_eq(current, expected)
  }
}

///|
test "reliability: record encode decode replay and contract validation form one closed loop" {
  let request = reliability_request("https://example.test/v1/items?page=1")
  let source = ScriptedTransport::new([
    reliability_response(200, "{\"items\":[],\"request_id\":\"req-001\"}"),
  ])
  let recorder = Session::with_defaults(Cassette::empty(), Record)
  match recorder.send(request, request => source.send(request)) {
    Ok(response) => assert_eq(response.status, 200)
    Err(_) => assert_true(false)
  }
  assert_eq(source.remaining(), 0)
  assert_eq(recorder.cassette().interactions.length(), 1)

  let encoded = recorder.cassette().encode()
  let restored = Cassette::decode(encoded)
  assert_eq(restored.encode(), encoded)
  let network_probe = ScriptedTransport::new([
    reliability_response(599, "{\"unexpected\":true}"),
  ])
  let replay = Session::with_defaults(restored, StrictOffline)
  match replay.send(request, request => network_probe.send(request)) {
    Err(_) => assert_true(false)
    Ok(response) => {
      let contract : ResponseContract = {
        allowed_statuses: [200],
        required_headers: ["content-type"],
        required_header_values: [],
        body_kind: Some(ExpectTextBody),
        json_fields: [
          { path: "/items", expected_kind: JsonArray, },
          { path: "/request_id", expected_kind: JsonString, },
        ],
        optional_json_fields: [],
        json_array_elements: [],
      }
      let report = response.validate_contract(contract)
      assert_true(report.is_valid())
      assert_eq(report.summary(), "contract valid")
    }
  }
  assert_eq(network_probe.remaining(), 1)
}

///|
test "reliability: recorded cassette excludes configured credentials" {
  let request : Request = {
    method: "POST",
    url: "https://example.test/v1/items?token=query-secret&page=1",
    headers: [{ name: "Authorization", value: "Bearer header-secret", }],
    body: Text("{\"credentials\":{\"token\":\"request-secret\"}}"),
  }
  let response : Response = {
    status: 201,
    headers: [{ name: "Set-Cookie", value: "session=response-cookie", }],
    body: Text("{\"credentials\":{\"token\":\"response-secret\"}}"),
  }
  let redaction : RedactionConfig = {
    headers: [],
    query_parameters: [],
    json_paths: ["/credentials/token"],
    optional_json_paths: [],
  }
  let recorder = Session::new_with_redaction(
    Cassette::empty(),
    Record,
    MatchConfig::default(),
    redaction,
  )
  let source = ScriptedTransport::new([response])
  match recorder.send(request, request => source.send(request)) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  let encoded = recorder.cassette().encode()
  assert_true(encoded.contains(REDACTION_MARKER))
  assert_true(!encoded.contains("query-secret"))
  assert_true(!encoded.contains("header-secret"))
  assert_true(!encoded.contains("request-secret"))
  assert_true(!encoded.contains("response-cookie"))
  assert_true(!encoded.contains("response-secret"))
}

///|
test "reliability: mismatch diagnostics are stable and redact request secrets" {
  let expected = reliability_request("https://example.test/v1/items?page=1")
  let cassette = reliability_cassette(
    expected,
    reliability_response(200, "{\"items\":[]}"),
  )
  let actual : Request = {
    method: "POST",
    url: "https://example.test/v1/items?page=2&token=diagnostic-secret",
    headers: [{ name: "Authorization", value: "Bearer header-secret", }],
    body: Text("body-secret"),
  }
  let session = Session::with_defaults(cassette, StrictOffline)
  let first = session.diagnose(actual).summary()
  let second = session.diagnose(actual).summary()
  assert_eq(first, second)
  assert_true(!first.contains("diagnostic-secret"))
  assert_true(!first.contains("header-secret"))
  assert_true(!first.contains("body-secret"))
}

///|
test "reliability: contract reports remain deterministic and never expose values" {
  let response : Response = {
    status: 503,
    headers: [{ name: "x-secret", value: "header-value-secret", }],
    body: Text("{\"token\":\"body-value-secret\"}"),
  }
  let contract : ResponseContract = {
    allowed_statuses: [200],
    required_headers: ["content-type"],
    required_header_values: [],
    body_kind: Some(ExpectTextBody),
    json_fields: [{ path: "/token", expected_kind: JsonNumber, }],
    optional_json_fields: [],
    json_array_elements: [],
  }
  let first = response.validate_contract(contract).summary()
  let second = response.validate_contract(contract).summary()
  assert_eq(first, second)
  assert_true(!first.contains("header-value-secret"))
  assert_true(!first.contains("body-value-secret"))
  assert_true(first.contains("status status: expected 200, actual 503"))
  assert_true(
    first.contains("json-type /token: expected number, actual string"),
  )
}
