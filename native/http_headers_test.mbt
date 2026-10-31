///|
#cfg(target="native")
async test "native HTTP rejects duplicate header names before parsing the URL" {
  let cases : Array[Array[@moonvcr.Header]] = [
    [
      { name: "X-Repeated", value: "first-header-secret", },
      { name: "X-Repeated", value: "second-header-secret", },
    ],
    [
      { name: "X-Repeated", value: "first-header-secret", },
      { name: "x-repeated", value: "second-header-secret", },
    ],
    [
      { name: "X-Repeated", value: "same-value", },
      { name: "x-repeated", value: "same-value", },
    ],
    [
      { name: "X-Repeated", value: "", },
      { name: "X-Other", value: "visible", },
      { name: "x-repeated", value: "second-header-secret", },
    ],
  ]
  for headers in cases {
    let request : @moonvcr.Request = {
      method: "GET",
      // Duplicate validation must run before any URL parsing or networking.
      url: "not-an-http-url",
      headers,
      body: @moonvcr.Empty,
    }
    let rejected = try {
      let _ = send_http_with_timeout(request, 1_000)
      false
    } catch {
      UnsupportedDuplicateHeaders => true
      _ => false
    } noraise {
      _ => false
    }
    inspect(rejected, content="true")
  }
}

///|
#cfg(target="native")
async test "native duplicate header rejection neither records nor exposes values" {
  let session = @moonvcr.Session::with_defaults(
    @moonvcr.Cassette::empty(),
    @moonvcr.Record,
  )
  let request : @moonvcr.Request = {
    method: "GET",
    url: "not-an-http-url",
    headers: [
      { name: "Authorization", value: "first-header-secret", },
      { name: "authorization", value: "second-header-secret", },
    ],
    body: @moonvcr.Empty,
  }
  let result = record_http(session, request)
  inspect(result is Err(@moonvcr.TransportFailed(_)), content="true")
  let rendered = @debug.to_string(result)
  inspect(rendered.contains("first-header-secret"), content="false")
  inspect(rendered.contains("second-header-secret"), content="false")
  inspect(session.cassette().interactions.length(), content="0")
}

///|
#cfg(target="native")
async test "native distinct header names are not rejected as duplicates" {
  let request : @moonvcr.Request = {
    method: "GET",
    url: "not-an-http-url",
    headers: [
      { name: "X-First", value: "first", },
      { name: "x-second", value: "second", },
    ],
    body: @moonvcr.Empty,
  }
  let passed_header_validation = try {
    let _ = send_http_with_timeout(request, 1_000)
    false
  } catch {
    RequestFailed => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(passed_header_validation, content="true")
}
