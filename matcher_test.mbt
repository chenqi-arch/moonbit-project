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
