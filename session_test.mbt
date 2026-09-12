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
