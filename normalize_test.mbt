///|
/// Query order and fragments must not create separate cassette keys.
test "normalizes url query and fragment" {
  assert_eq(
    normalize_url("https://example.test/items?b=2&a=1#debug"),
    "https://example.test/items?a=1&b=2",
  )
  assert_eq(
    normalize_url("https://example.test/items?"),
    "https://example.test/items",
  )
}

///|
/// Header names are case-insensitive and selected values are sorted.
test "normalizes selected headers" {
  let request : Request = {
    method: " get ",
    url: "https://example.test/items",
    headers: [
      { name: "X-Trace", value: " ignored ", },
      { name: "ACCEPT", value: " application/json ", },
    ],
    body: Empty,
  }
  let config : MatchConfig = {
    include_headers: ["accept", "x-trace"],
    ignore_headers: ["x-trace"],
    body_mode: Exact,
  }
  let key = normalize_request(request, config)
  assert_true(key.contains("method=3:GET"))
  assert_true(key.contains("headers=6:accept=16:application/json"))
  assert_true(!key.contains("x-trace"))
}

///|
/// Ignoring the body makes otherwise different payloads share a key.
test "can ignore request body" {
  let request : Request = {
    method: "POST",
    url: "https://example.test/items",
    headers: [],
    body: Text("first payload"),
  }
  let config : MatchConfig = {
    include_headers: [],
    ignore_headers: [],
    body_mode: Ignore,
  }
  assert_true(normalize_request(request, config).has_suffix("\nbody="))
}

///|
test "normalizes bare and duplicate query pairs deterministically" {
  assert_eq(
    normalize_url("https://example.test/items?b&a=2&a=1"),
    "https://example.test/items?b=&a=1&a=2",
  )
}

///|
test "keeps base64 body kind in exact matching keys" {
  let request : Request = {
    method: "POST",
    url: "https://example.test/upload",
    headers: [],
    body: Base64("AAEC"),
  }
  let key = normalize_request(request, MatchConfig::default())
  assert_true(key.contains("body=base64:4:AAEC"))
}

///|
/// Delimiters inside header values must not collide with multiple headers.
test "structured request keys distinguish header boundaries" {
  let one : Request = {
    method: "GET",
    url: "https://example.test/items",
    headers: [{ name: "a", value: "b&c=d", }],
    body: Empty,
  }
  let two : Request = {
    method: "GET",
    url: "https://example.test/items",
    headers: [{ name: "a", value: "b", }, { name: "c", value: "d", }],
    body: Empty,
  }
  assert_true(
    normalize_request(one, MatchConfig::default()) !=
    normalize_request(two, MatchConfig::default()),
  )
}
