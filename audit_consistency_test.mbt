///|
fn audit_consistency_request(
  url : String,
  headers : Array[Header],
  body : Body,
) -> Request {
  { method: "GET", url, headers, body, }
}

///|
test "independent diagnostic exactness agrees with replay across raw imports and matching policies" {
  let requests : Array[Request] = [
    audit_consistency_request("https://test.invalid", [], Empty),
    audit_consistency_request("https://test.invalid/?x=1", [], Empty),
    audit_consistency_request("https://test.invalid/?x=1&x=2", [], Empty),
    audit_consistency_request("https://test.invalid/?x=2&x=1", [], Empty),
    audit_consistency_request("https://test.invalid/?y=3&x=1&x=2", [], Empty),
    audit_consistency_request("https://test.invalid/?x=1&y=3&x=2", [], Empty),
    audit_consistency_request("https://test.invalid/?x=1&%78=2", [], Empty),
    audit_consistency_request("https://test.invalid/?%78=2&x=1", [], Empty),
    audit_consistency_request(
      "https://test.invalid/?token=audit-query-secret",
      [],
      Empty,
    ),
    audit_consistency_request(
      "https://test.invalid/?token=[REDACTED]",
      [],
      Empty,
    ),
    audit_consistency_request(
      "https://test.invalid",
      [{ name: "Authorization", value: "audit-header-secret", }],
      Empty,
    ),
    audit_consistency_request(
      "https://test.invalid",
      [{ name: "a", value: "x&b=y", }],
      Empty,
    ),
    audit_consistency_request(
      "https://test.invalid",
      [{ name: "a", value: "x", }, { name: "b", value: "y", }],
      Empty,
    ),
    audit_consistency_request(
      "https://test.invalid",
      [{ name: "X-Mode", value: "first", }, { name: "x-mode", value: "last", }],
      Empty,
    ),
    audit_consistency_request(
      "https://test.invalid",
      [{ name: "x-mode", value: "last", }, { name: "X-Mode", value: "first", }],
      Empty,
    ),
    audit_consistency_request(
      "https://test.invalid",
      [],
      Text("{\"token\":\"audit-body-secret\"}"),
    ),
    audit_consistency_request(
      "https://test.invalid",
      [],
      Text("{\"token\":\"[REDACTED]\"}"),
    ),
    audit_consistency_request("https://test.invalid", [], Text("{}")),
    audit_consistency_request(
      "https://test.invalid",
      [],
      Base64("YW5vdGhlci1zZWNyZXQ="),
    ),
    audit_consistency_request(
      "https://test.invalid/?audit-name-secret=public",
      [{ name: "audit-name-secret", value: "ordinary", }],
      Empty,
    ),
  ]
  let ignore_body : MatchConfig = {
    include_headers: [],
    ignore_headers: [],
    body_mode: Ignore,
  }
  let ignore_header : MatchConfig = {
    include_headers: [],
    ignore_headers: ["authorization", "x-mode"],
    body_mode: Exact,
  }
  let required = RedactionConfig::default()
  required.json_paths.push("/token")
  let optional = RedactionConfig::default()
  optional.optional_json_paths.push("/token")
  let secrets = [
    "audit-query-secret", "audit-header-secret", "audit-body-secret", "audit-name-secret",
  ]
  let mut checked = 0
  for expected in requests {
    for actual in requests {
      for config in [MatchConfig::default(), ignore_body, ignore_header] {
        for rules in [RedactionConfig::default(), required, optional] {
          let cassette : Cassette = {
            format_version: CURRENT_FORMAT_VERSION,
            interactions: [
              {
                request: expected,
                response: { status: 200, headers: [], body: Empty, },
              },
            ],
          }
          let session = Session::new_with_redaction(
            cassette,
            StrictOffline,
            config,
            rules,
          )
          let report = session.diagnose(actual)
          let replayed = session.replay(actual) is Ok(_)
          assert_eq(report.differences.length() == 0, replayed)
          for secret in secrets {
            assert_true(!report.summary().contains(secret))
            assert_true(!@debug.to_string(report).contains(secret))
          }
          checked += 1
        }
      }
    }
  }
  assert_eq(checked, 3600)
}

///|
test "independent same-name order is preserved across query aliases and Unicode groups" {
  for
    (left, right) in [
      ("?x=first&x=last", "?x=last&x=first"),
      ("?x=first&%78=last", "?%78=last&x=first"),
      ("?a+b=first&a%20b=last", "?a%20b=last&a+b=first"),
      ("?%E4%B8%AD=first&中=last", "?中=last&%E4%B8%AD=first"),
    ] {
    assert_true(
      normalize_url("https://test.invalid/" + left) !=
      normalize_url("https://test.invalid/" + right),
    )
  }
}
