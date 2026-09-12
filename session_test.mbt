///|
fn session_request(url : String) -> Request {
  { method: "GET", url, headers: [], body: Empty, }
}

///|
fn session_response(status : Int) -> Response {
  { status, headers: [], body: Text("offline response"), }
}

///|
test "replay returns a cassette response without network" {
  let request = session_request("https://example.test/health")
  let cassette : Cassette = {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [{ request, response: session_response(200), }],
  }
  let session = Session::with_defaults(cassette, Replay)
  let network_guard = (_ : Request) => {
    Err(TransportError::Failed("network must not be called"))
  }
  match session.send(request, network_guard) {
    Ok(response) => assert_eq(response.status, 200)
    Err(_) => assert_true(false)
  }
}

///|
test "replay consumes matching entries in order" {
  let request = session_request("https://example.test/items")
  let cassette : Cassette = {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [
      { request, response: session_response(200), },
      { request, response: session_response(201), },
    ],
  }
  let session = Session::with_defaults(cassette, StrictOffline)
  let no_network = (_ : Request) => Err(TransportError::Failed("offline"))
  match session.send(request, no_network) {
    Ok(response) => assert_eq(response.status, 200)
    Err(_) => assert_true(false)
  }
  match session.send(request, no_network) {
    Ok(response) => assert_eq(response.status, 201)
    Err(_) => assert_true(false)
  }
  match session.send(request, no_network) {
    Ok(_) => assert_true(false)
    Err(ReplayMiss(candidates)) => assert_eq(candidates.length(), 0)
    Err(_) => assert_true(false)
  }
}

///|
test "record calls transport and appends the interaction" {
  let request = session_request("https://example.test/items")
  let cassette = Cassette::empty()
  let session = Session::with_defaults(cassette, Record)
  let transport = (_ : Request) => Ok(session_response(201))
  match session.send(request, transport) {
    Ok(response) => assert_eq(response.status, 201)
    Err(_) => assert_true(false)
  }
  assert_eq(session.cassette().interactions.length(), 1)
  assert_eq(session.cassette().interactions[0].request.url, request.url)
}

///|
test "transport errors are typed" {
  let session = Session::with_defaults(Cassette::empty(), Record)
  let transport = (_ : Request) => Err(TransportError::Failed("timeout"))
  match session.send(session_request("https://example.test"), transport) {
    Ok(_) => assert_true(false)
    Err(TransportFailed(TransportError::Failed(message))) =>
      assert_eq(message, "timeout")
    Err(_) => assert_true(false)
  }
}

///|
test "record stores a redacted interaction but returns the real response" {
  let request : Request = {
    method: "GET",
    url: "https://example.test/items?token=real-token",
    headers: [{ name: "Authorization", value: "Bearer real-token", }],
    body: Empty,
  }
  let real_response : Response = {
    status: 200,
    headers: [{ name: "Set-Cookie", value: "session=real-cookie", }],
    body: Text("{\u{22}token\u{22}:\u{22}real-token\u{22},\u{22}ok\u{22}:true}"),
  }
  let session = Session::new_with_redaction(
    Cassette::empty(),
    Record,
    MatchConfig::default(),
    { headers: [], query_parameters: [], json_paths: ["/token"], },
  )
  let transport = (_ : Request) => Ok(real_response)
  match session.send(request, transport) {
    Err(_) => assert_true(false)
    Ok(response) => {
      assert_eq(response.body, real_response.body)
      let saved = session.cassette().interactions[0]
      assert_eq(
        saved.request.url,
        "https://example.test/items?token=[REDACTED]",
      )
      assert_eq(saved.request.headers[0].value, REDACTION_MARKER)
      assert_eq(saved.response.headers[0].value, REDACTION_MARKER)
      match saved.response.body {
        Text(text) => assert_true(!text.contains("real-token"))
        _ => assert_true(false)
      }
      let replay = Session::with_defaults(session.cassette(), Replay)
      let no_network = (_ : Request) => {
        Err(TransportError::Failed("network must not be called"))
      }
      match replay.send(request, no_network) {
        Ok(replayed) => assert_eq(replayed.status, 200)
        Err(_) => assert_true(false)
      }
    }
  }
}

///|
test "redaction failure does not append an interaction" {
  let session = Session::new_with_redaction(
    Cassette::empty(),
    Record,
    MatchConfig::default(),
    { headers: [], query_parameters: [], json_paths: ["/required"], },
  )
  let request = session_request("https://example.test")
  let response : Response = { status: 200, headers: [], body: Text("{}"), }
  let transport = (_ : Request) => Ok(response)
  match session.send(request, transport) {
    Err(RedactionFailed(MissingPath(path))) => assert_eq(path, "/required")
    _ => assert_true(false)
  }
  assert_eq(session.cassette().interactions.length(), 0)
}

///|
test "replay applies the same custom JSON redaction view" {
  let recorded_request : Request = {
    method: "POST",
    url: "https://example.test/items",
    headers: [],
    body: Text(
      "{\u{22}credentials\u{22}:{\u{22}token\u{22}:\u{22}[REDACTED]\u{22}}}",
    ),
  }
  let cassette : Cassette = {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [
      { request: recorded_request, response: session_response(202), },
    ],
  }
  let redaction : RedactionConfig = {
    headers: [],
    query_parameters: [],
    json_paths: ["/credentials/token"],
  }
  let session = Session::new_with_redaction(
    cassette,
    StrictOffline,
    MatchConfig::default(),
    redaction,
  )
  let request : Request = {
    method: "POST",
    url: "https://example.test/items",
    headers: [],
    body: Text(
      "{\u{22}credentials\u{22}:{\u{22}token\u{22}:\u{22}real-token\u{22}}}",
    ),
  }
  let no_network = (_ : Request) => {
    Err(TransportError::Failed("network must not be called"))
  }
  match session.send(request, no_network) {
    Ok(response) => assert_eq(response.status, 202)
    Err(_) => assert_true(false)
  }
}

///|
test "replay redaction failure is typed and does not call transport" {
  let session = Session::new_with_redaction(
    Cassette::empty(),
    Replay,
    MatchConfig::default(),
    { headers: [], query_parameters: [], json_paths: ["/required"], },
  )
  let request : Request = {
    method: "POST",
    url: "https://example.test",
    headers: [],
    body: Text("{}"),
  }
  let should_not_run = (_ : Request) => {
    Err(TransportError::Failed("transport must not run"))
  }
  match session.send(request, should_not_run) {
    Err(RedactionFailed(MissingPath(path))) => assert_eq(path, "/required")
    _ => assert_true(false)
  }
}
