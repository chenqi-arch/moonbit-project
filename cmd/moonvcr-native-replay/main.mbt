///|
fn redaction_policy() -> @moonvcr.RedactionPolicy {
  let request = @moonvcr.RedactionConfig::default()
  request.json_paths.push("/request_token")
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
  let path = "_build/moonvcr-real-http.json"
  let cassette = @native.load_cassette_default(path)
  let session = @moonvcr.Session::new_with_redaction_policy(
    cassette,
    @moonvcr.StrictOffline,
    @moonvcr.MatchConfig::default(),
    redaction_policy(),
  )
  let get_response = match session.replay(get_request()) {
    Ok(response) => response
    Err(_) => abort("offline GET replay failed")
  }
  guard get_response.status == 200 else { abort("offline GET status mismatch") }
  let order_response = match session.replay(order_request()) {
    Ok(response) => response
    Err(_) => abort("offline POST replay failed")
  }
  let contract : @moonvcr.ResponseContract = {
    allowed_statuses: [201],
    required_headers: ["content-type", "x-moonvcr-server"],
    required_header_values: [
      { name: "content-type", expected_value: "application/json", },
    ],
    body_kind: Some(@moonvcr.ExpectTextBody),
    json_fields: [
      { path: "/id", expected_kind: @moonvcr.JsonNumber, },
      { path: "/state", expected_kind: @moonvcr.JsonString, },
    ],
    optional_json_fields: [
      { path: "/note", expected_kind: @moonvcr.JsonString, },
    ],
    json_array_elements: [
      { path: "/items", expected_kind: @moonvcr.JsonObject, },
    ],
  }
  let report = order_response.validate_contract(contract)
  guard report.is_valid() else { abort(report.summary()) }
  match session.assert_complete() {
    Ok(_) => ()
    Err(_) => abort("offline replay did not consume the complete cassette")
  }
  let encoded = cassette.encode()
  guard !encoded.contains("secret") else {
    abort("loaded cassette contains a secret")
  }
  @fs.remove(path) catch {
    _ => ()
  }
  println(
    "cross-process strict offline replay passed interactions=2 network_calls=0",
  )
}
