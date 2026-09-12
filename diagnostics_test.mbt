///|
fn diagnostic_request(
  method : String,
  url : String,
  headers : Array[Header],
  body : Body,
) -> Request {
  { method, url, headers, body, }
}

///|
fn diagnostic_cassette(request : Request) -> Cassette {
  {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [
      { request, response: { status: 200, headers: [], body: Text("ok"), }, },
    ],
  }
}

///|
test "diagnoses method, URL, and query differences" {
  let expected = diagnostic_request(
    "GET",
    "https://example.test/items?page=1",
    [],
    Empty,
  )
  let actual = diagnostic_request(
    "POST",
    "https://other.test/items?page=2",
    [],
    Empty,
  )
  let report = diagnose_mismatch(
    actual,
    diagnostic_cassette(expected),
    MatchConfig::default(),
    [false],
  )
  assert_eq(report.differences.length(), 3)
  assert_eq(report.differences[0].kind, Method)
  assert_eq(report.differences[1].kind, Url)
  assert_eq(report.differences[2].kind, Query)
}

///|
test "diagnoses headers without exposing their values" {
  let expected = diagnostic_request(
    "GET",
    "https://example.test",
    [{ name: "X-Trace", value: "expected-secret", }],
    Empty,
  )
  let actual = diagnostic_request(
    "GET",
    "https://example.test",
    [{ name: "X-Trace", value: "actual-secret", }],
    Empty,
  )
  let report = diagnose_mismatch(
    actual,
    diagnostic_cassette(expected),
    MatchConfig::default(),
    [false],
  )
  assert_eq(report.differences.length(), 1)
  assert_eq(report.differences[0].kind, Headers)
  assert_true(!report.summary().contains("expected-secret"))
  assert_true(!report.summary().contains("actual-secret"))
}

///|
test "diagnoses body length without exposing body values" {
  let expected = diagnostic_request(
    "POST",
    "https://example.test",
    [],
    Text("expected-secret"),
  )
  let actual = diagnostic_request(
    "POST",
    "https://example.test",
    [],
    Text("actual-secret-with-a-different-length"),
  )
  let report = diagnose_mismatch(
    actual,
    diagnostic_cassette(expected),
    MatchConfig::default(),
    [false],
  )
  assert_eq(report.differences.length(), 1)
  assert_eq(report.differences[0].kind, Body)
  assert_true(!report.summary().contains("expected-secret"))
  assert_true(!report.summary().contains("actual-secret"))
}

///|
test "reports a consumed exact entry as a sequence mismatch" {
  let request = diagnostic_request(
    "GET",
    "https://example.test/items",
    [],
    Empty,
  )
  let report = diagnose_mismatch(
    request,
    diagnostic_cassette(request),
    MatchConfig::default(),
    [true],
  )
  assert_eq(report.differences.length(), 1)
  assert_eq(report.differences[0].kind, Sequence)
  assert_eq(report.differences[0].candidate_index, 0)
}

///|
test "reports an empty cassette without leaking request data" {
  let request = diagnostic_request(
    "GET",
    "https://example.test/items?token=private-secret",
    [],
    Text("private-body-secret"),
  )
  let report = diagnose_mismatch(
    request,
    Cassette::empty(),
    MatchConfig::default(),
    [],
  )
  assert_eq(report.differences[0].kind, NoCandidate)
  assert_true(!report.summary().contains("private-secret"))
}

///|
test "session exposes the same structured diagnostics" {
  let request = diagnostic_request(
    "GET",
    "https://example.test/items",
    [],
    Empty,
  )
  let session = Session::with_defaults(diagnostic_cassette(request), Replay)
  let report = session.diagnose(
    diagnostic_request("POST", "https://example.test/items", [], Empty),
  )
  assert_eq(report.differences[0].kind, Method)
}

///|
test "diagnostics reuse ignored header and body matching rules" {
  let expected = diagnostic_request(
    "POST",
    "https://example.test/items",
    [{ name: "X-Trace", value: "expected", }],
    Text("expected body"),
  )
  let actual = diagnostic_request(
    "POST",
    "https://example.test/items",
    [{ name: "x-trace", value: "actual", }],
    Text("actual body"),
  )
  let config : MatchConfig = {
    include_headers: [],
    ignore_headers: ["x-trace"],
    body_mode: Ignore,
  }
  let report = diagnose_mismatch(
    actual,
    diagnostic_cassette(expected),
    config,
    [false],
  )
  assert_eq(report.differences.length(), 0)
}

///|
test "diagnostics reuse configured JSON redaction paths" {
  let expected = diagnostic_request(
    "POST",
    "https://example.test/items",
    [],
    Text(
      "{\u{22}credentials\u{22}:{\u{22}token\u{22}:\u{22}expected\u{22},\u{22}ok\u{22}:true}",
    ),
  )
  let actual = diagnostic_request(
    "POST",
    "https://example.test/items",
    [],
    Text(
      "{\u{22}credentials\u{22}:{\u{22}token\u{22}:\u{22}actual\u{22},\u{22}ok\u{22}:true}",
    ),
  )
  let redaction : RedactionConfig = {
    headers: [],
    query_parameters: [],
    json_paths: ["/credentials/token"],
  }
  let report = diagnose_mismatch_with_redaction(
    actual,
    diagnostic_cassette(expected),
    MatchConfig::default(),
    [false],
    redaction,
  )
  assert_eq(report.differences.length(), 0)
  assert_true(!report.summary().contains("expected"))
  assert_true(!report.summary().contains("actual"))
}
