///|
fn redaction_request() -> Request {
  {
    method: "POST",
    url: "https://example.test/items?token=secret&safe=yes#fragment",
    headers: [
      { name: "Authorization", value: "Bearer secret", },
      { name: "X-Trace", value: "trace-1", },
    ],
    body: Text("{\"credentials\":{\"token\":\"secret\"},\"name\":\"demo\"}"),
  }
}

///|
test "redacts default headers and query values" {
  let config = RedactionConfig::default()
  match redact_request(redaction_request(), config) {
    Err(_) => assert_true(false)
    Ok(safe) => {
      assert_eq(
        safe.url,
        "https://example.test/items?token=[REDACTED]&safe=yes#fragment",
      )
      assert_eq(safe.headers[0].value, REDACTION_MARKER)
      assert_eq(safe.headers[1].value, "trace-1")
    }
  }
}

///|
test "redacts nested JSON path without changing other fields" {
  let config : RedactionConfig = {
    headers: [],
    query_parameters: [],
    json_paths: ["/credentials/token"],
    optional_json_paths: [],
  }
  match redact_request(redaction_request(), config) {
    Err(_) => assert_true(false)
    Ok(safe) =>
      match safe.body {
        Text(text) => {
          assert_eq(
            text, "{\"credentials\":{\"token\":\"[REDACTED]\"},\"name\":\"demo\"}",
          )
          assert_true(!text.contains("secret"))
        }
        _ => assert_true(false)
      }
  }
}

///|
test "supports dot shorthand and array JSON Pointer indexes" {
  let config : RedactionConfig = {
    headers: [],
    query_parameters: [],
    json_paths: ["user.token", "/items/1/id"],
    optional_json_paths: [],
  }
  let request : Request = {
    method: "POST",
    url: "https://example.test",
    headers: [],
    body: Text(
      "{\"user\":{\"token\":\"a\"},\"items\":[{\"id\":\"first\"},{\"id\":\"second\"}]}",
    ),
  }
  match redact_request(request, config) {
    Err(_) => assert_true(false)
    Ok(safe) =>
      match safe.body {
        Text(text) =>
          assert_eq(
            text, "{\"user\":{\"token\":\"[REDACTED]\"},\"items\":[{\"id\":\"first\"},{\"id\":\"[REDACTED]\"}]}",
          )
        _ => assert_true(false)
      }
  }
}

///|
test "invalid JSON path fails closed" {
  let config : RedactionConfig = {
    headers: [],
    query_parameters: [],
    json_paths: ["/missing/token"],
    optional_json_paths: [],
  }
  match redact_request(redaction_request(), config) {
    Err(MissingPath(path)) => assert_eq(path, "/missing/token")
    _ => assert_true(false)
  }
}

///|
test "malformed JSON fails closed" {
  let config : RedactionConfig = {
    headers: [],
    query_parameters: [],
    json_paths: ["/token"],
    optional_json_paths: [],
  }
  let request : Request = {
    method: "POST",
    url: "https://example.test",
    headers: [],
    body: Text("not-json"),
  }
  match redact_request(request, config) {
    Err(InvalidJson(message)) =>
      assert_eq(message, "body is not valid JSON text")
    _ => assert_true(false)
  }
}

///|
test "redacts caller-defined header and query names case-insensitively" {
  let config : RedactionConfig = {
    headers: ["X-Internal-Secret"],
    query_parameters: ["tenant_secret"],
    json_paths: [],
    optional_json_paths: [],
  }
  let request : Request = {
    method: "GET",
    url: "https://example.test/items?TENANT_SECRET=private&visible=yes",
    headers: [{ name: "x-internal-secret", value: "private", }],
    body: Empty,
  }
  match redact_request(request, config) {
    Err(_) => assert_true(false)
    Ok(safe) => {
      assert_eq(
        safe.url,
        "https://example.test/items?TENANT_SECRET=[REDACTED]&visible=yes",
      )
      assert_eq(safe.headers[0].value, REDACTION_MARKER)
    }
  }
}

///|
test "redacts encoded sensitive query names and URL user information" {
  let config = RedactionConfig::default()
  let request : Request = {
    method: "GET",
    url: "https://user:password@example.test/items?access%5Ftoken=private",
    headers: [],
    body: Empty,
  }
  match redact_request(request, config) {
    Err(_) => assert_true(false)
    Ok(safe) => {
      assert_true(!safe.url.contains("password"))
      assert_true(safe.url.contains("[REDACTED]@example.test"))
      assert_true(safe.url.contains("access%5Ftoken=[REDACTED]"))
    }
  }
}

///|
test "redacts response headers and JSON body with custom rules" {
  let config : RedactionConfig = {
    headers: ["X-Session"],
    query_parameters: [],
    json_paths: ["session.id"],
    optional_json_paths: [],
  }
  let response : Response = {
    status: 200,
    headers: [{ name: "X-Session", value: "private", }],
    body: Text(
      "{\u{22}session\u{22}:{\u{22}id\u{22}:\u{22}private\u{22},\u{22}ok\u{22}:true}}",
    ),
  }
  match redact_response(response, config) {
    Err(_) => assert_true(false)
    Ok(safe) => {
      assert_eq(safe.headers[0].value, REDACTION_MARKER)
      match safe.body {
        Text(text) => {
          assert_true(text.contains(REDACTION_MARKER))
          assert_true(!text.contains("private"))
        }
        _ => assert_true(false)
      }
    }
  }
}

///|
test "optional JSON redaction paths ignore absence and redact presence" {
  let config : RedactionConfig = {
    headers: [],
    query_parameters: [],
    json_paths: [],
    optional_json_paths: ["/token"],
  }
  let without_token : Request = {
    method: "POST",
    url: "https://example.test",
    headers: [],
    body: Text("{\"name\":\"demo\"}"),
  }
  match redact_request(without_token, config) {
    Err(_) => assert_true(false)
    Ok(safe) =>
      match safe.body {
        Text(text) => assert_true(text.contains("demo"))
        _ => assert_true(false)
      }
  }
  let with_token : Request = {
    method: "POST",
    url: "https://example.test",
    headers: [],
    body: Text("{\"token\":\"optional-secret\"}"),
  }
  match redact_request(with_token, config) {
    Err(_) => assert_true(false)
    Ok(safe) =>
      match safe.body {
        Text(text) => {
          assert_true(text.contains(REDACTION_MARKER))
          assert_true(!text.contains("optional-secret"))
        }
        _ => assert_true(false)
      }
  }
}

///|
test "interaction policy keeps request and response JSON paths independent" {
  let policy : RedactionPolicy = {
    request: {
      headers: [],
      query_parameters: [],
      json_paths: ["/request_token"],
      optional_json_paths: [],
    },
    response: {
      headers: [],
      query_parameters: [],
      json_paths: ["/response_token"],
      optional_json_paths: [],
    },
  }
  let interaction : Interaction = {
    request: {
      method: "POST",
      url: "https://example.test",
      headers: [],
      body: Text("{\"request_token\":\"request-secret\"}"),
    },
    response: {
      status: 200,
      headers: [],
      body: Text("{\"response_token\":\"response-secret\"}"),
    },
  }
  match redact_interaction_with_policy(interaction, policy) {
    Err(_) => assert_true(false)
    Ok(safe) => {
      let encoded = Cassette::encode({
        format_version: CURRENT_FORMAT_VERSION,
        interactions: [safe],
      })
      assert_true(!encoded.contains("request-secret"))
      assert_true(!encoded.contains("response-secret"))
      assert_true(encoded.contains(REDACTION_MARKER))
    }
  }
}
