///|
fn matcher_request(url : String) -> Request {
  {
    method: "GET",
    url,
    headers: [{ name: "Accept", value: "application/json", }],
    body: Empty,
  }
}

///|
fn matcher_response(status : Int) -> Response {
  { status, headers: [], body: Empty, }
}

///|
test "matcher finds the first unconsumed equivalent request" {
  let cassette : Cassette = {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [
      {
        request: matcher_request("https://example.test/items?a=1&b=2"),
        response: matcher_response(200),
      },
      {
        request: matcher_request("https://example.test/items?a=1&b=2"),
        response: matcher_response(201),
      },
    ],
  }
  let config = MatchConfig::default()
  match
    match_request(
      matcher_request("https://example.test/items?b=2&a=1#trace"),
      cassette,
      config,
      [false, false],
    ) {
    Matched(index) => assert_eq(index, 0)
    NoMatch(_) => assert_true(false)
  }
  match
    match_request(
      matcher_request("https://example.test/items?b=2&a=1#trace"),
      cassette,
      config,
      [true, false],
    ) {
    Matched(index) => assert_eq(index, 1)
    NoMatch(_) => assert_true(false)
  }
}

///|
/// A miss carries stable candidate information for future mismatch reports.
test "matcher reports unconsumed candidates on miss" {
  let cassette : Cassette = {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [
      {
        request: matcher_request("https://example.test/items?page=1"),
        response: matcher_response(200),
      },
      {
        request: matcher_request("https://example.test/items?page=2"),
        response: matcher_response(200),
      },
    ],
  }
  match
    match_request(
      matcher_request("https://example.test/items?page=3"),
      cassette,
      MatchConfig::default(),
      [false, true],
    ) {
    Matched(_) => assert_true(false)
    NoMatch(candidates) => {
      assert_eq(candidates.length(), 1)
      assert_eq(candidates[0].index, 0)
      assert_true(candidates[0].key.contains("page=1"))
    }
  }
}

///|
test "matcher honors body ignore policy" {
  let expected = matcher_request("https://example.test/items")
  let expected = { ..expected, body: Text("expected"), }
  let actual = { ..expected, body: Text("actual"), }
  let cassette : Cassette = {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [{ request: expected, response: matcher_response(200), }],
  }
  let ignore_body : MatchConfig = {
    include_headers: [],
    ignore_headers: [],
    body_mode: Ignore,
  }
  match match_request(actual, cassette, ignore_body, [false]) {
    Matched(index) => assert_eq(index, 0)
    NoMatch(_) => assert_true(false)
  }
  match match_request(actual, cassette, MatchConfig::default(), [false]) {
    Matched(_) => assert_true(false)
    NoMatch(_) => assert_true(true)
  }
}

///|
test "matcher honors included and ignored headers" {
  let expected = matcher_request("https://example.test/items")
  let expected = {
    ..expected,
    headers: [
      { name: "Accept", value: "application/json", },
      { name: "X-Trace", value: "expected", },
    ],
  }
  let actual = {
    ..expected,
    headers: [
      { name: "accept", value: "application/json", },
      { name: "x-trace", value: "actual", },
    ],
  }
  let cassette : Cassette = {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [{ request: expected, response: matcher_response(200), }],
  }
  let config : MatchConfig = {
    include_headers: ["accept", "x-trace"],
    ignore_headers: ["x-trace"],
    body_mode: Exact,
  }
  match match_request(actual, cassette, config, [false]) {
    Matched(index) => assert_eq(index, 0)
    NoMatch(_) => assert_true(false)
  }
}
