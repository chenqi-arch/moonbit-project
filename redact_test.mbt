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
