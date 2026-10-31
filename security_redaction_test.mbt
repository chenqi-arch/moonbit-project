///|
fn security_request(url : String, body : Body) -> Request {
  { method: "POST", url, headers: [], body, }
}

///|
fn security_rules(optional : Bool) -> RedactionConfig {
  let rules = RedactionConfig::default()
  if optional {
    rules.optional_json_paths.push("/token")
  } else {
    rules.json_paths.push("/token")
  }
  rules
}

///|
test "security JSON rules reject non Text bodies on request and response" {
  for optional in [false, true] {
    let rules = security_rules(optional)
    for
      body in [
        Body::Empty,
        Body::Base64("eyJ0b2tlbiI6InN5bnRoZXRpYy1zZWNyZXQifQ=="),
      ] {
      assert_true(
        redact_request(security_request("https://test.invalid", body), rules)
        is Err(_),
      )
      let response : Response = { status: 200, headers: [], body, }
      assert_true(redact_response(response, rules) is Err(_))
    }
  }
}

///|
test "security failed JSON record preserves existing cassette on both sides" {
  for optional in [false, true] {
    for response_side in [false, true] {
      let rules = security_rules(optional)
      let defaults = RedactionConfig::default()
      let policy : RedactionPolicy = if response_side {
        { request: defaults, response: rules, }
      } else {
        { request: rules, response: defaults, }
      }
      for
        body in [
          Body::Empty,
          Body::Base64("eyJ0b2tlbiI6InN5bnRoZXRpYy1zZWNyZXQifQ=="),
          Body::Text("not-json"),
        ] {
        let session = Session::new_with_redaction_policy(
          example_cassette(),
          Record,
          MatchConfig::default(),
          policy,
        )
        let before = session.cassette().encode()
        let request = security_request(
          "https://test.invalid",
          if response_side {
            Empty
          } else {
            body
          },
        )
        let response : Response = {
          status: 200,
          headers: [],
          body: if response_side {
            body
          } else {
            Empty
          },
        }
        assert_true(
          session.record_response(request, response) is Err(RedactionFailed(_)),
        )
        assert_eq(session.cassette().encode(), before)
      }
    }
  }
}

///|
test "security default rules preserve binary body when JSON is not configured" {
  let body : Body = Base64("AQID")
  match
    redact_request(
      security_request("https://test.invalid", body),
      RedactionConfig::default(),
    ) {
    Ok(safe) => assert_eq(safe.body, body)
    Err(_) => assert_true(false)
  }
}

///|
test "security percent encoded sensitive names compare after decoding" {
  let names = [
    "%54oken", "%74oken", "ToKeN", "%54%4f%4b%45%4e", "access%5F%54oken", "%41PI%5fKEY",
    "%63lient%5F%53ecret",
  ]
  for name in names {
    let request = security_request(
      "https://test.invalid/?" +
      name +
      "=query-secret&" +
      name +
      "=another-secret&safe=yes",
      Empty,
    )
    match redact_request(request, RedactionConfig::default()) {
      Ok(safe) => {
        assert_true(!safe.url.contains("query-secret"))
        assert_true(!safe.url.contains("another-secret"))
        assert_true(safe.url.contains("safe=yes"))
      }
      Err(_) => assert_true(false)
    }
  }
}

///|
test "security custom query names support decoded UTF8 and encoded configuration" {
  let config = RedactionConfig::default()
  config.query_parameters.push("%54enant%5F%53ecret")
  config.query_parameters.push("令牌")
  for name in ["TENANT_SECRET", "%54enant_secret", "%E4%BB%A4%E7%89%8C"] {
    match
      redact_request(
        security_request(
          "https://test.invalid/?" + name + "=custom-secret",
          Empty,
        ),
        config,
      ) {
      Ok(safe) => assert_true(!safe.url.contains("custom-secret"))
      Err(_) => assert_true(false)
    }
  }
}

///|
test "security fragments are never persisted and userinfo is fully removed" {
  for
    url in [
      "https://test.invalid/#token=fragment-secret", "https://test.invalid?x=1#access_token=fragment-secret",
      "https://user:password@test.invalid?token=query-secret/part#fragment-secret",
      "https://first:password@second:password@test.invalid/path#fragment-secret",
    ] {
    match
      redact_request(security_request(url, Empty), RedactionConfig::default()) {
      Ok(safe) => {
        assert_true(!safe.url.contains("fragment-secret"))
        assert_true(!safe.url.contains("password"))
        assert_true(!safe.url.contains("query-secret"))
      }
      Err(_) => assert_true(false)
    }
  }
}

///|
test "security replay JSON failure leaves consumption unchanged" {
  for optional in [false, true] {
    let session = Session::new_with_redaction(
      example_cassette(),
      StrictOffline,
      MatchConfig::default(),
      security_rules(optional),
    )
    let before = session.remaining_interactions()
    for body in [Body::Empty, Body::Base64("AQID")] {
      assert_true(
        session.replay(security_request("https://test.invalid", body))
        is Err(RedactionFailed(_)),
      )
      assert_eq(session.remaining_interactions(), before)
    }
  }
}

///|
test "security transport error returned by session has no raw secret in Debug" {
  let session = Session::with_defaults(Cassette::empty(), Record)
  let request = security_request("https://test.invalid", Empty)
  let transport = (_ : Request) => {
    Err(TransportError::Failed("transport-secret"))
  }
  match session.send(request, transport) {
    Err(error) => {
      assert_eq(error.summary(), "transport failed")
      assert_true(!@debug.to_string(error).contains("transport-secret"))
    }
    Ok(_) => assert_true(false)
  }
  assert_eq(session.cassette().interactions.length(), 0)
}

///|
test "security token case and encoding matrix covers all 1024 combinations" {
  let plain = ["t", "o", "k", "e", "n"]
  let lower_encoded = ["%74", "%6f", "%6b", "%65", "%6e"]
  let upper_encoded = ["%54", "%4F", "%4B", "%45", "%4E"]
  for combination in 0..<1024 {
    let mut choices = combination
    let mut name = ""
    for index in 0..<5 {
      name += match choices % 4 {
        0 => plain[index]
        1 => plain[index].to_upper()
        2 => lower_encoded[index]
        _ => upper_encoded[index]
      }
      choices /= 4
    }
    match
      redact_request(
        security_request(
          "https://test.invalid/?" + name + "=matrix-secret",
          Empty,
        ),
        RedactionConfig::default(),
      ) {
      Ok(safe) => assert_true(!safe.url.contains("matrix-secret"))
      Err(_) => assert_true(false)
    }
  }
}

///|
test "security query form plus and escaped plus have distinct semantics" {
  let space_config = RedactionConfig::default()
  space_config.query_parameters.push("access token")
  let plus_config = RedactionConfig::default()
  plus_config.query_parameters.push("access+token")
  for
    (name, config) in [
      ("access+token", space_config),
      ("access%20token", space_config),
      ("access%2Btoken", plus_config),
    ] {
    match
      redact_request(
        security_request(
          "https://test.invalid/?" + name + "=plus-secret",
          Empty,
        ),
        config,
      ) {
      Ok(safe) => assert_true(!safe.url.contains("plus-secret"))
      Err(_) => assert_true(false)
    }
  }
  match
    redact_request(
      security_request("https://test.invalid/?access%2Btoken=visible", Empty),
      space_config,
    ) {
    Ok(safe) => assert_true(safe.url.contains("visible"))
    Err(_) => assert_true(false)
  }
  match
    redact_request(
      security_request("https://test.invalid/?%2554oken=visible", Empty),
      RedactionConfig::default(),
    ) {
    Ok(safe) => assert_true(safe.url.contains("visible"))
    Err(_) => assert_true(false)
  }
}

///|
test "security invalid optional paths cannot bypass validation with Empty" {
  let rules = RedactionConfig::default()
  rules.optional_json_paths.push("/bad~8key")
  for body in [Body::Empty, Body::Base64("AQID"), Body::Text("{}")] {
    assert_true(
      redact_request(security_request("https://test.invalid", body), rules)
      is Err(InvalidPath(_)),
    )
  }
}

///|
test "security non Record sessions reject explicit record operations" {
  for mode in [SessionMode::Replay, SessionMode::StrictOffline] {
    let session = Session::with_defaults(example_cassette(), mode)
    let before = session.cassette().encode()
    let request = security_request("https://test.invalid", Empty)
    let response : Response = { status: 200, headers: [], body: Empty, }
    assert_true(session.record_response(request, response) is Err(InvalidMode))
    assert_eq(session.cassette().encode(), before)
    assert_eq(session.remaining_interactions(), 1)
  }
}

///|
test "security diagnostic matches use structure safe header keys" {
  let expected : Request = {
    method: "GET",
    url: "https://test.invalid",
    headers: [{ name: "a", value: "x&b=y", }],
    body: Empty,
  }
  let actual : Request = {
    method: "GET",
    url: "https://test.invalid",
    headers: [{ name: "a", value: "x", }, { name: "b", value: "y", }],
    body: Empty,
  }
  let cassette : Cassette = {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [
      {
        request: expected,
        response: { status: 200, headers: [], body: Empty, },
      },
    ],
  }
  let session = Session::with_defaults(cassette, StrictOffline)
  assert_true(session.replay(actual) is Err(ReplayMiss(_)))
  assert_true(session.diagnose(actual).differences.length() > 0)
}

///|
test "security diagnostics do not echo arbitrary methods or field names" {
  let request : Request = {
    method: "synthetic-method-secret",
    url: "https://test.invalid/?synthetic-query-secret=value",
    headers: [{ name: "synthetic-header-secret", value: "header-value", }],
    body: Text("body-secret"),
  }
  let session = Session::with_defaults(Cassette::empty(), StrictOffline)
  let report = session.diagnose(request)
  let text = (@debug.to_string(report) +
  report.summary() +
  request_safe_summary(request)).to_lower()
  for
    secret in [
      "synthetic-method-secret", "synthetic-query-secret", "synthetic-header-secret",
      "body-secret", "header-value",
    ] {
    assert_true(!text.contains(secret))
  }
}

///|
test "security failed record send leaves archive unchanged" {
  let policy : RedactionPolicy = {
    request: RedactionConfig::default(),
    response: security_rules(false),
  }
  let session = Session::new_with_redaction_policy(
    example_cassette(),
    Record,
    MatchConfig::default(),
    policy,
  )
  let before = session.cassette().encode()
  let request = security_request("https://test.invalid", Empty)
  let response : Response = {
    status: 200,
    headers: [],
    body: Body::Base64("AQID"),
  }
  let transport = (_ : Request) => Ok(response)
  assert_true(session.send(request, transport) is Err(RedactionFailed(_)))
  assert_eq(session.cassette().encode(), before)
}

///|
test "security recorded entries keep consumption state synchronized" {
  let session = Session::with_defaults(Cassette::empty(), Record)
  let request = security_request("https://test.invalid", Empty)
  let response : Response = { status: 201, headers: [], body: Text("ok"), }
  assert_true(session.record_response(request, response) is Ok(_))
  assert_eq(session.remaining_interactions(), 1)
  match session.replay(request) {
    Ok(replayed) => assert_eq(replayed.status, 201)
    Err(_) => assert_true(false)
  }
  assert_true(session.assert_complete() is Ok(_))
  assert_true(session.replay(request) is Err(ReplayMiss(_)))
  assert_true(session.record_response(request, response) is Ok(_))
  assert_eq(session.remaining_interactions(), 1)
  assert_true(session.replay(request) is Ok(_))
  assert_true(session.assert_complete() is Ok(_))
}
