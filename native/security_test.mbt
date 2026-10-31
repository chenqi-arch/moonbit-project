///|
#cfg(target="native")
async test "native helper replays without HTTP even with an invalid network timeout" {
  for
    mode in [@moonvcr.SessionMode::Replay, @moonvcr.SessionMode::StrictOffline] {
    let cassette = @moonvcr.example_cassette()
    let request = cassette.interactions[0].request
    let session = @moonvcr.Session::with_defaults(cassette, mode)
    match record_http(session, request, timeout_millis=0) {
      Ok(response) => inspect(response.status, content="200")
      Err(error) => abort(error.summary())
    }
    inspect(session.assert_complete() is Ok(_), content="true")
    inspect(
      record_http(session, request, timeout_millis=0)
      is Err(@moonvcr.ReplayMiss(_)),
      content="true",
    )
    inspect(session.cassette().interactions.length(), content="1")
  }
}

///|
#cfg(target="native")
async test "native archive stores only redacted encoded query and fragment" {
  let path = "_build/moonvcr-security-redacted.json"
  @fs.remove(path) catch {
    _ => ()
  }
  defer @fs.remove(path)
  let session = @moonvcr.Session::with_defaults(
    @moonvcr.Cassette::empty(),
    @moonvcr.Record,
  )
  let request : @moonvcr.Request = {
    method: "GET",
    url: "https://test.invalid/?%54oken=query-secret#fragment-secret",
    headers: [],
    body: @moonvcr.Empty,
  }
  let response : @moonvcr.Response = {
    status: 200,
    headers: [],
    body: @moonvcr.Empty,
  }
  inspect(session.record_response(request, response) is Ok(_), content="true")
  save_cassette_new(path, session.cassette())
  let loaded = load_cassette_default(path).encode()
  inspect(
    loaded.contains("query-secret") || loaded.contains("fragment-secret"),
    content="false",
  )
}

///|
#cfg(target="native")
async test "native archive remains empty after failed binary JSON redaction" {
  let path = "_build/moonvcr-security-rejected.json"
  @fs.remove(path) catch {
    _ => ()
  }
  defer @fs.remove(path)
  let response_rules = @moonvcr.RedactionConfig::default()
  response_rules.json_paths.push("/token")
  let session = @moonvcr.Session::new_with_redaction_policy(
    @moonvcr.Cassette::empty(),
    @moonvcr.Record,
    @moonvcr.MatchConfig::default(),
    { request: @moonvcr.RedactionConfig::default(), response: response_rules, },
  )
  let request : @moonvcr.Request = {
    method: "GET",
    url: "https://test.invalid",
    headers: [],
    body: @moonvcr.Empty,
  }
  let response : @moonvcr.Response = {
    status: 200,
    headers: [],
    body: @moonvcr.Base64("eyJ0b2tlbiI6InN5bnRoZXRpYy1zZWNyZXQifQ=="),
  }
  inspect(
    session.record_response(request, response)
    is Err(@moonvcr.RedactionFailed(_)),
    content="true",
  )
  save_cassette_new(path, session.cassette())
  let loaded = load_cassette_default(path)
  inspect(loaded.interactions.length(), content="0")
  inspect(
    loaded.encode().contains("eyJ0b2tlbiI6InN5bnRoZXRpYy1zZWNyZXQifQ=="),
    content="false",
  )
}
