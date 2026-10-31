///|
test "audit duplicate query order stays significant after name grouping" {
  for
    (left, right) in [
      (
        "https://test.invalid/?role=user&role=admin", "https://test.invalid/?role=admin&role=user",
      ),
      (
        "https://test.invalid/?role=user&%72ole=admin", "https://test.invalid/?%72ole=admin&role=user",
      ),
      (
        "https://test.invalid/?role=user&role=user&role=admin", "https://test.invalid/?role=user&role=admin&role=user",
      ),
    ] {
    let expected : Request = {
      method: "GET",
      url: left,
      headers: [],
      body: Empty,
    }
    let actual : Request = {
      method: "GET",
      url: right,
      headers: [],
      body: Empty,
    }
    let recorder = Session::with_defaults(Cassette::empty(), Record)
    assert_true(
      recorder.record_response(expected, {
        status: 200,
        headers: [],
        body: Empty,
      })
      is Ok(_),
    )
    let replay = Session::with_defaults(recorder.cassette(), StrictOffline)
    assert_true(replay.replay(actual) is Err(ReplayMiss(_)))
    assert_eq(replay.remaining_interactions(), 1)
    assert_true(replay.diagnose(actual).differences.length() > 0)
  }
}

///|
test "audit independent query names reorder without reordering duplicate values" {
  assert_eq(
    normalize_url("https://test.invalid/?b=3&a=2&a=1"),
    normalize_url("https://test.invalid/?a=2&b=3&a=1"),
  )
  assert_true(
    normalize_url("https://test.invalid/?a=x ") !=
    normalize_url("https://test.invalid/?a=x"),
  )
}

///|
test "audit duplicate header groups preserve case insensitive value order" {
  let first : Request = {
    method: "GET",
    url: "https://test.invalid",
    body: Empty,
    headers: [
      { name: "X-Mode", value: "user", },
      { name: "Other", value: "x", },
      { name: "x-mode", value: "admin", },
    ],
  }
  let reordered : Request = {
    method: "GET",
    url: first.url,
    body: Empty,
    headers: [
      { name: "other", value: "x", },
      { name: "x-mode", value: "user", },
      { name: "X-MODE", value: "admin", },
    ],
  }
  let changed : Request = {
    method: "GET",
    url: first.url,
    body: Empty,
    headers: [
      { name: "x-mode", value: "admin", },
      { name: "X-Mode", value: "user", },
      { name: "other", value: "x", },
    ],
  }
  let config = MatchConfig::default()
  assert_eq(
    request_match_key(first, config),
    request_match_key(reordered, config),
  )
  assert_true(
    request_match_key(first, config) != request_match_key(changed, config),
  )
  let cassette : Cassette = {
    format_version: 1,
    interactions: [
      { request: first, response: { status: 200, headers: [], body: Empty, }, },
    ],
  }
  let session = Session::with_defaults(cassette, StrictOffline)
  assert_true(session.replay(changed) is Err(ReplayMiss(_)))
  assert_true(session.diagnose(changed).differences.length() > 0)
}

///|
test "audit raw cassette diagnosis uses actual replay comparison without leaking" {
  let cases : Array[(Request, RedactionConfig)] = [
    (
      {
        method: "GET",
        url: "https://test.invalid/?token=raw-import-secret",
        headers: [],
        body: Empty,
      },
      RedactionConfig::default(),
    ),
    (
      {
        method: "GET",
        url: "https://test.invalid",
        headers: [{ name: "Authorization", value: "raw-import-secret", }],
        body: Empty,
      },
      RedactionConfig::default(),
    ),
  ]
  for (request, rules) in cases {
    let cassette : Cassette = {
      format_version: 1,
      interactions: [
        { request, response: { status: 200, headers: [], body: Empty, }, },
      ],
    }
    let session = Session::new_with_redaction(
      cassette,
      StrictOffline,
      MatchConfig::default(),
      rules,
    )
    assert_true(session.replay(request) is Err(ReplayMiss(_)))
    let report = session.diagnose(request)
    assert_true(report.differences.length() > 0)
    assert_true(
      !(@debug.to_string(report) + report.summary()).contains(
        "raw-import-secret",
      ),
    )
    assert_eq(session.remaining_interactions(), 1)
  }
}

///|
test "audit redaction failure cannot diagnose as an exact match" {
  let rules = RedactionConfig::default()
  rules.json_paths.push("/required")
  let request : Request = {
    method: "POST",
    url: "https://test.invalid",
    headers: [],
    body: Text("{}"),
  }
  let cassette : Cassette = {
    format_version: 1,
    interactions: [
      { request, response: { status: 200, headers: [], body: Empty, }, },
    ],
  }
  let session = Session::new_with_redaction(
    cassette,
    StrictOffline,
    MatchConfig::default(),
    rules,
  )
  assert_true(session.replay(request) is Err(RedactionFailed(_)))
  assert_true(session.diagnose(request).differences.length() > 0)
}

///|
test "audit contract treats invalid array indices differently from absent optional fields" {
  let response : Response = {
    status: 200,
    headers: [],
    body: Text("{\"items\":[{\"id\":1},{\"id\":2}],\"object\":{\"01\":3}}"),
  }
  for
    path in [
      "/items/01/id", "/items/-/id", "/items/+1/id", "/items/2147483648/id",
    ] {
    let contract = ResponseContract::permissive()
    contract.optional_json_fields.push({ path, expected_kind: JsonNumber, })
    let report = response.validate_contract(contract)
    assert_true(!report.is_valid())
    assert_eq(report.violations[0].kind, InvalidJsonPathViolation)
  }
  let valid = ResponseContract::permissive()
  valid.json_fields.push({ path: "/object/01", expected_kind: JsonNumber, })
  valid.optional_json_fields.push({
    path: "/items/3/id",
    expected_kind: JsonNumber,
  })
  assert_true(response.validate_contract(valid).is_valid())
}
