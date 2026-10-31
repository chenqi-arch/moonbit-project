///|
fn redaction_policy(request_json : Bool) -> @moonvcr.RedactionPolicy {
  let request = @moonvcr.RedactionConfig::default()
  if request_json {
    request.json_paths.push("/request_token")
  }
  let response = @moonvcr.RedactionConfig::default()
  response.json_paths.push("/response_token")
  { request, response, }
}

///|
fn get_request() -> @moonvcr.Request {
  {
    method: "GET",
    url: "http://127.0.0.1:38081/items?page=1&api%5Fkey=get-secret",
    headers: [{ name: "Authorization", value: "Bearer get-secret", }],
    body: @moonvcr.Empty,
  }
}

///|
fn order_request() -> @moonvcr.Request {
  {
    method: "POST",
    url: "http://127.0.0.1:38081/orders?token=query-secret",
    headers: [
      { name: "Content-Type", value: "application/json", },
      { name: "X-Client-Id", value: "integration", },
      { name: "Cookie", value: "session=cookie-secret", },
    ],
    body: @moonvcr.Text(
      "{\"request_token\":\"request-secret\",\"sku\":\"demo\"}",
    ),
  }
}

///|
async fn main {
  let get_session = @moonvcr.Session::new_with_redaction_policy(
    @moonvcr.Cassette::empty(),
    @moonvcr.Record,
    @moonvcr.MatchConfig::default(),
    redaction_policy(false),
  )
  let session = @moonvcr.Session::new_with_redaction_policy(
    @moonvcr.Cassette::empty(),
    @moonvcr.Record,
    @moonvcr.MatchConfig::default(),
    redaction_policy(true),
  )
  match @native.record_http(get_session, get_request(), timeout_millis=2_000) {
    Ok(response) if response.status == 200 => ()
    _ => abort("real GET recording failed")
  }
  match @native.record_http(session, order_request(), timeout_millis=2_000) {
    Ok(response) if response.status == 201 => ()
    _ => abort("real POST recording failed")
  }
  let get_cassette = get_session.cassette()
  let order_cassette = session.cassette()
  guard get_cassette.interactions.length() == 1 &&
    order_cassette.interactions.length() == 1 else {
    abort("per-operation recording count mismatch")
  }
  let cassette : @moonvcr.Cassette = {
    format_version: get_cassette.format_version,
    interactions: [get_cassette.interactions[0], order_cassette.interactions[0]],
  }
  guard cassette.interactions.length() == 2 else {
    abort("recorded interaction count mismatch")
  }
  let encoded = cassette.encode()
  for
    secret in [
      "get-secret", "query-secret", "cookie-secret", "request-secret", "server-secret",
      "response-secret",
    ] {
    if encoded.contains(secret) {
      abort("recorded cassette contains a secret")
    }
  }
  @native.save_cassette_replace("_build/moonvcr-real-http.json", cassette)
  println("real HTTP recording saved interactions=2 secrets=0")
}
