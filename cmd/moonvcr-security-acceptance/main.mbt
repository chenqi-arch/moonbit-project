///|
fn require(condition : Bool, message : String) -> Unit {
  guard condition else { abort(message) }
}

///|
fn main {
  let encoded_secret = "eyJ0b2tlbiI6InN5bnRoZXRpYy1zZWNyZXQifQ=="
  let bodies : Array[@moonvcr.Body] = [
    @moonvcr.Empty,
    @moonvcr.Base64(encoded_secret),
    @moonvcr.Text("not-json"),
  ]
  let mut rejected = 0
  for optional in [false, true] {
    for response_side in [false, true] {
      let rules = @moonvcr.RedactionConfig::default()
      if optional {
        rules.optional_json_paths.push("/token")
      } else {
        rules.json_paths.push("/token")
      }
      let defaults = @moonvcr.RedactionConfig::default()
      let policy : @moonvcr.RedactionPolicy = if response_side {
        { request: defaults, response: rules, }
      } else {
        { request: rules, response: defaults, }
      }
      for body in bodies {
        let session = @moonvcr.Session::new_with_redaction_policy(
          @moonvcr.example_cassette(),
          @moonvcr.Record,
          @moonvcr.MatchConfig::default(),
          policy,
        )
        let before = session.cassette().encode()
        let request : @moonvcr.Request = {
          method: "POST",
          url: "https://test.invalid",
          headers: [],
          body: if response_side {
            @moonvcr.Empty
          } else {
            body
          },
        }
        let response : @moonvcr.Response = {
          status: 200,
          headers: [],
          body: if response_side {
            body
          } else {
            @moonvcr.Empty
          },
        }
        require(
          session.record_response(request, response) is Err(_),
          "unsafe JSON body was recorded",
        )
        require(
          session.cassette().encode() == before,
          "failed redaction changed cassette",
        )
        require(
          !session.cassette().encode().contains(encoded_secret),
          "Base64 secret persisted",
        )
        rejected += 1
      }
    }
  }
  let plain = ["t", "o", "k", "e", "n"]
  let lower = ["%74", "%6f", "%6b", "%65", "%6e"]
  let upper = ["%54", "%4F", "%4B", "%45", "%4E"]
  for combination in 0..<1024 {
    let mut choices = combination
    let mut name = ""
    for index in 0..<5 {
      name += match choices % 4 {
        0 => plain[index]
        1 => plain[index].to_upper()
        2 => lower[index]
        _ => upper[index]
      }
      choices /= 4
    }
    let session = @moonvcr.Session::with_defaults(
      @moonvcr.Cassette::empty(),
      @moonvcr.Record,
    )
    let request : @moonvcr.Request = {
      method: "GET",
      url: "https://test.invalid/?" + name + "=query-secret#fragment-secret",
      headers: [],
      body: @moonvcr.Empty,
    }
    let response : @moonvcr.Response = {
      status: 200,
      headers: [],
      body: @moonvcr.Empty,
    }
    require(
      session.record_response(request, response) is Ok(_),
      "safe query recording failed",
    )
    let text = session.cassette().encode()
    require(
      !text.contains("query-secret") && !text.contains("fragment-secret"),
      "encoded query or fragment leaked",
    )
  }
  let cassette = @moonvcr.example_cassette()
  let request = cassette.interactions[0].request
  let offline = @moonvcr.Session::with_defaults(
    cassette,
    @moonvcr.StrictOffline,
  )
  let response : @moonvcr.Response = {
    status: 200,
    headers: [],
    body: @moonvcr.Empty,
  }
  require(
    offline.record_response(request, response) is Err(_),
    "offline session recorded a response",
  )
  require(offline.replay(request) is Ok(_), "offline replay failed")
  require(offline.assert_complete() is Ok(_), "offline cassette incomplete")
  let recorder = @moonvcr.Session::with_defaults(
    @moonvcr.Cassette::empty(),
    @moonvcr.Record,
  )
  let transport = (_ : @moonvcr.Request) => {
    Err(@moonvcr.TransportError::Failed("transport-secret"))
  }
  match recorder.send(request, transport) {
    Err(error) =>
      require(
        !@debug.to_string(error).contains("transport-secret"),
        "transport Debug leaked",
      )
    Ok(_) => abort("failing transport unexpectedly succeeded")
  }
  println(
    "security acceptance passed rejected=" +
    rejected.to_string() +
    " encoded_names=1024 retained_secrets=0",
  )
  audit_followup_acceptance()
}

///|
/// Public-API checks for the second independent audit. These run against the
/// candidate archive and, after publication, a downloaded registry package.
fn audit_followup_acceptance() -> Unit {
  let mut pointer_cases = 0
  for (suffix, escaped) in [(" ", " "), ("\t", "\\t"), ("\n", "\\n")] {
    for optional in [false, true] {
      for response_side in [false, true] {
        let rules = @moonvcr.RedactionConfig::default()
        if optional {
          rules.optional_json_paths.push("/token" + suffix)
        } else {
          rules.json_paths.push("/token" + suffix)
        }
        let policy : @moonvcr.RedactionPolicy = if response_side {
          { request: @moonvcr.RedactionConfig::default(), response: rules, }
        } else {
          { request: rules, response: @moonvcr.RedactionConfig::default(), }
        }
        let body = @moonvcr.Text(
          "{\"token" +
          escaped +
          "\":\"pointer-audit-secret\",\"token\":\"public-control\"}",
        )
        let request : @moonvcr.Request = {
          method: "POST",
          url: "https://test.invalid",
          headers: [],
          body: if response_side {
            @moonvcr.Empty
          } else {
            body
          },
        }
        let response : @moonvcr.Response = {
          status: 200,
          headers: [],
          body: if response_side {
            body
          } else {
            @moonvcr.Empty
          },
        }
        let session = @moonvcr.Session::new_with_redaction_policy(
          @moonvcr.Cassette::empty(),
          @moonvcr.Record,
          @moonvcr.MatchConfig::default(),
          policy,
        )
        require(
          session.record_response(request, response) is Ok(_),
          "exact pointer recording failed",
        )
        let saved = session.cassette().encode()
        require(
          !saved.contains("pointer-audit-secret"),
          "whitespace pointer secret retained",
        )
        require(
          saved.contains("public-control"),
          "pointer modified the adjacent key",
        )
        pointer_cases += 1
      }
    }
  }
  let original : @moonvcr.Request = {
    method: "GET",
    url: "https://test.invalid/?role=user&role=admin",
    headers: [],
    body: @moonvcr.Empty,
  }
  let changed : @moonvcr.Request = {
    method: "GET",
    url: "https://test.invalid/?role=admin&role=user",
    headers: [],
    body: @moonvcr.Empty,
  }
  let config = @moonvcr.MatchConfig::default()
  require(
    @moonvcr.request_match_key(original, config) !=
    @moonvcr.request_match_key(changed, config),
    "duplicate query order lost",
  )
  let header_first : @moonvcr.Request = {
    method: "GET",
    url: "https://test.invalid",
    body: @moonvcr.Empty,
    headers: [
      { name: "X-Mode", value: "user", },
      { name: "x-mode", value: "admin", },
    ],
  }
  let header_reversed : @moonvcr.Request = {
    method: "GET",
    url: "https://test.invalid",
    body: @moonvcr.Empty,
    headers: [
      { name: "x-mode", value: "admin", },
      { name: "X-Mode", value: "user", },
    ],
  }
  require(
    @moonvcr.request_match_key(header_first, config) !=
    @moonvcr.request_match_key(header_reversed, config),
    "duplicate header order lost",
  )
  let raw : @moonvcr.Request = {
    method: "GET",
    url: "https://test.invalid/?token=import-audit-secret",
    headers: [],
    body: @moonvcr.Empty,
  }
  let cassette : @moonvcr.Cassette = {
    format_version: 1,
    interactions: [
      {
        request: raw,
        response: { status: 200, headers: [], body: @moonvcr.Empty, },
      },
    ],
  }
  let session = @moonvcr.Session::with_defaults(
    cassette,
    @moonvcr.StrictOffline,
  )
  require(
    session.replay(raw) is Err(_),
    "raw imported cassette unexpectedly matched",
  )
  let report = session.diagnose(raw)
  require(
    report.differences.length() > 0,
    "diagnosis disagrees with replay miss",
  )
  require(
    !@debug.to_string(report).contains("import-audit-secret"),
    "diagnosis leaked raw cassette",
  )
  let whitespace_contract = @moonvcr.ResponseContract::permissive()
  whitespace_contract.json_fields.push({
    path: "/id ",
    expected_kind: @moonvcr.JsonNumber,
  })
  let incompatible : @moonvcr.Response = {
    status: 200,
    headers: [],
    body: @moonvcr.Text("{\"id \":\"wrong\",\"id\":123}"),
  }
  require(
    !incompatible.validate_contract(whitespace_contract).is_valid(),
    "contract checked adjacent key",
  )
  let array_request : @moonvcr.Request = {
    method: "POST",
    url: "https://test.invalid",
    headers: [],
    body: @moonvcr.Text(
      "{\"items\":[{\"token\":\"a\"},{\"token\":\"array-audit-secret\"}]}",
    ),
  }
  for optional in [false, true] {
    let rules = @moonvcr.RedactionConfig::default()
    if optional {
      rules.optional_json_paths.push("/items/01/token")
    } else {
      rules.json_paths.push("/items/01/token")
    }
    require(
      @moonvcr.redact_request(array_request, rules) is Err(_),
      "invalid array index accepted",
    )
  }
  let array_contract = @moonvcr.ResponseContract::permissive()
  array_contract.optional_json_fields.push({
    path: "/items/01/token",
    expected_kind: @moonvcr.JsonString,
  })
  let array_response : @moonvcr.Response = {
    status: 200,
    headers: [],
    body: array_request.body,
  }
  require(
    !array_response.validate_contract(array_contract).is_valid(),
    "optional contract ignored invalid index",
  )
  let nested : @moonvcr.Request = {
    method: "POST",
    url: "https://test.invalid",
    headers: [],
    body: @moonvcr.Text(
      "{\"credentials\":{\"token\":\"overlap-audit-secret\"}}",
    ),
  }
  let mut saved_body : @moonvcr.Body? = None
  for
    paths in [
      ["/credentials", "/credentials/token"],
      ["/credentials/token", "/credentials"],
    ] {
    let rules = @moonvcr.RedactionConfig::default()
    for path in paths {
      rules.json_paths.push(path)
    }
    let safe = match @moonvcr.redact_request(nested, rules) {
      Ok(value) => value
      Err(_) => abort("overlapping rules depended on order")
    }
    match saved_body {
      None => saved_body = Some(safe.body)
      Some(expected) =>
        require(expected == safe.body, "overlapping results depended on order")
    }
    require(
      !@debug.to_string(safe).contains("overlap-audit-secret"),
      "overlap retained secret",
    )
  }
  println(
    "audit acceptance passed pointer_cases=" +
    pointer_cases.to_string() +
    " retained_secrets=0 duplicate_order=preserved diagnosis=consistent invalid_indices=rejected overlapping_rules=stable",
  )
}
