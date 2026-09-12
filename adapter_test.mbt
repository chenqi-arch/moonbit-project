///|
fn adapter_request() -> Request {
  {
    method: "GET",
    url: "https://example.test/items",
    headers: [],
    body: Empty,
  }
}

///|
fn adapter_response(status : Int) -> Response {
  { status, headers: [], body: Text("scripted"), }
}

///|
test "scripted transport returns finite responses in order" {
  let transport = ScriptedTransport::new([
    adapter_response(200),
    adapter_response(201),
  ])
  assert_eq(transport.remaining(), 2)
  match transport.send(adapter_request()) {
    Ok(response) => assert_eq(response.status, 200)
    Err(_) => assert_true(false)
  }
  assert_eq(transport.remaining(), 1)
  match transport.send(adapter_request()) {
    Ok(response) => assert_eq(response.status, 201)
    Err(_) => assert_true(false)
  }
  assert_eq(transport.remaining(), 0)
}

///|
test "scripted transport reports exhaustion without network fallback" {
  let transport = ScriptedTransport::new([adapter_response(204)])
  match transport.send(adapter_request()) {
    Ok(response) => assert_eq(response.status, 204)
    Err(_) => assert_true(false)
  }
  match transport.send(adapter_request()) {
    Ok(_) => assert_true(false)
    Err(TransportError::Failed(message)) =>
      assert_eq(message, "scripted transport exhausted")
  }
}

///|
test "scripted transport can drive a record session" {
  let request = adapter_request()
  let scripted = ScriptedTransport::new([adapter_response(201)])
  let session = Session::with_defaults(Cassette::empty(), Record)
  match session.send(request, request => scripted.send(request)) {
    Ok(response) => assert_eq(response.status, 201)
    Err(_) => assert_true(false)
  }
  assert_eq(session.cassette().interactions.length(), 1)
}
