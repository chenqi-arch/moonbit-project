///|
fn request(
  method : String,
  path : String,
  headers? : Array[@moonvcr.Header] = [],
  body? : @moonvcr.Body = @moonvcr.Empty,
) -> @moonvcr.Request {
  { method, url: "http://127.0.0.1:38081" + path, headers, body, }
}

///|
fn header_value(response : @moonvcr.Response, name : String) -> String? {
  for header in response.headers {
    if header.name.to_lower() == name.to_lower() {
      return Some(header.value)
    }
  }
  None
}

///|
async fn main {
  let get_response = @native.send_http(request("GET", "/items?page=1"))
  guard get_response.status == 200 else { abort("GET status mismatch") }
  guard header_value(get_response, "content-type") is Some("application/json") else {
    abort("GET response header mismatch")
  }
  guard get_response.body is @moonvcr.Text(get_text) &&
    get_text.contains("items") else {
    abort("GET JSON response mismatch")
  }

  let post_response = @native.send_http(
    request(
      "POST",
      "/orders?token=integration-secret",
      headers=[
        { name: "Content-Type", value: "application/json", },
        { name: "X-Client-Id", value: "integration", },
      ],
      body=@moonvcr.Text(
        "{\"request_token\":\"request-secret\",\"sku\":\"demo\"}",
      ),
    ),
  )
  guard post_response.status == 201 else { abort("POST status mismatch") }
  guard post_response.body is @moonvcr.Text(post_text) &&
    post_text.contains("created") else {
    abort("POST JSON response mismatch")
  }

  let byte_response = @native.send_http(request("GET", "/bytes"))
  guard byte_response.body is @moonvcr.Base64(encoded) && encoded.length() > 0 else {
    abort("binary response was not preserved as base64")
  }

  let unavailable = @native.send_http(request("GET", "/status/503"))
  guard unavailable.status == 503 else {
    abort("non-2xx status was not preserved")
  }
  let redirect = @native.send_http(request("GET", "/redirect"))
  guard redirect.status == 302 else { abort("redirect boundary changed") }

  let invalid_method = try {
    let _ = @native.send_http(request("NOT-A-METHOD", "/health"))
    "not rejected"
  } catch {
    error => error.summary()
  }
  guard invalid_method == "unsupported HTTP method" else {
    abort("unsupported method error mismatch")
  }

  let invalid_timeout = try {
    let _ = @native.send_http_with_timeout(request("GET", "/health"), 0)
    "not rejected"
  } catch {
    error => error.summary()
  }
  guard invalid_timeout == "HTTP timeout must be positive" else {
    abort("invalid timeout error mismatch")
  }

  let timed_out = try {
    let _ = @native.send_http_with_timeout(request("GET", "/slow"), 20)
    "not rejected"
  } catch {
    error => error.summary()
  }
  guard timed_out == "HTTP request timed out" else {
    abort("timeout error mismatch")
  }

  let connection_failure = try {
    let _ = @native.send_http_with_timeout(request("GET", "/drop"), 500)
    "not rejected"
  } catch {
    error => error.summary()
  }
  guard connection_failure == "HTTP request failed" else {
    abort("connection failure error mismatch")
  }
  println(
    "native HTTP acceptance passed: GET POST headers JSON bytes errors timeout status redirect",
  )
}
