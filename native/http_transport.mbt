///|
/// Safe public error categories for the native HTTP adapter. Underlying error
/// strings are deliberately not exposed because they may contain credentials.
pub suberror HttpAdapterError {
  UnsupportedMethod
  UnsupportedRequestBody
  UnsupportedDuplicateHeaders
  InvalidTimeout
  TimedOut
  RequestFailed
} derive(@debug.Debug)

///|
pub const DEFAULT_HTTP_TIMEOUT_MILLIS : Int = 30_000

///|
fn request_method(
  method : String,
) -> @http.RequestMethod raise HttpAdapterError {
  match method.trim().to_owned().to_upper() {
    "GET" => @http.Get
    "HEAD" => @http.Head
    "POST" => @http.Post
    "PUT" => @http.Put
    "DELETE" => @http.Delete
    "CONNECT" => @http.Connect
    "OPTIONS" => @http.Options
    "TRACE" => @http.Trace
    "PATCH" => @http.Patch
    _ => raise UnsupportedMethod
  }
}

///|
/// The async client has one value per case-insensitive header name. Reject
/// duplicate input names rather than silently discarding or merging values.
fn request_headers(
  headers : Array[@moonvcr.Header],
) -> @http.Headers raise HttpAdapterError {
  let result : @http.Headers = Map([])
  for header in headers {
    match result.get(header.name) {
      Some(_) => raise UnsupportedDuplicateHeaders
      None => result[header.name] = header.value
    }
  }
  result
}

///|
fn request_body(body : @moonvcr.Body) -> Bytes raise HttpAdapterError {
  match body {
    @moonvcr.Empty => b""
    @moonvcr.Text(text) => @utf8.encode(text)
    @moonvcr.Base64(value) =>
      @base64.decode(value) catch {
        _ => raise UnsupportedRequestBody
      }
  }
}

///|
/// Rebuild the cookie fields exposed by the official parser. Attribute
/// spelling/order is canonical, not the original HTTP header byte sequence.
fn cookie_header_value(cookie : @http.Cookie) -> String {
  let fields = [cookie.name + "=" + cookie.value]
  match cookie.path {
    Some(value) => fields.push("Path=" + value)
    None => ()
  }
  match cookie.expires_raw {
    Some(value) => fields.push("Expires=" + value)
    None => ()
  }
  match cookie.max_age {
    Some(value) => fields.push("Max-Age=" + value.to_string())
    None => ()
  }
  match cookie.domain {
    Some(value) => fields.push("Domain=" + value)
    None => ()
  }
  if cookie.secure {
    fields.push("Secure")
  }
  if cookie.http_only {
    fields.push("HttpOnly")
  }
  for extension in cookie.extensions {
    fields.push(extension)
  }
  fields.join("; ")
}

///|
fn response_headers(response : @http.Response) -> Array[@moonvcr.Header] {
  let result : Array[@moonvcr.Header] = []
  for name, value in response.headers {
    result.push({ name: name.to_string(), value, })
  }
  result.sort_by((left, right) => left.name.compare(right.name))
  // async separates Set-Cookie from its ordinary header map. Keep each cookie
  // as one array entry and retain the order reported by its parser.
  for cookie in response.cookies {
    result.push({ name: "Set-Cookie", value: cookie_header_value(cookie), })
  }
  result
}

///|
fn response_body(data : &@io.Data) -> @moonvcr.Body {
  let text = data.text() catch {
    _ => return @moonvcr.Base64(@base64.encode(data.binary()))
  }
  @moonvcr.Text(text)
}

///|
/// Send a request with an explicit deadline. TLS verification uses the
/// official client's secure default.
pub async fn send_http_with_timeout(
  request : @moonvcr.Request,
  timeout_millis : Int,
) -> @moonvcr.Response raise HttpAdapterError {
  if timeout_millis <= 0 {
    raise InvalidTimeout
  }
  let method = request_method(request.method + "")
  let body = request_body(request.body)
  let headers = request_headers(request.headers)
  let result = @async.with_timeout_opt(timeout_millis, () => {
    @http.request(request.url + "", method, headers, body)
  }) catch {
    _ => raise RequestFailed
  }
  guard result is Some((response, data)) else { raise TimedOut }
  {
    status: response.code,
    headers: response_headers(response),
    body: response_body(data),
  }
}

///|
pub async fn send_http(
  request : @moonvcr.Request,
) -> @moonvcr.Response raise HttpAdapterError {
  send_http_with_timeout(request, DEFAULT_HTTP_TIMEOUT_MILLIS)
}

///|
pub async fn record_http(
  session : @moonvcr.Session,
  request : @moonvcr.Request,
  timeout_millis? : Int = DEFAULT_HTTP_TIMEOUT_MILLIS,
) -> Result[@moonvcr.Response, @moonvcr.SessionError] {
  if session.mode() != @moonvcr.Record {
    return session.replay(request)
  }
  let response = send_http_with_timeout(request, timeout_millis) catch {
    error =>
      return Err(
        @moonvcr.SessionError::TransportFailed(
          @moonvcr.TransportError::Failed(error.summary()),
        ),
      )
  }
  session.record_response(request, response)
}

///|
pub fn HttpAdapterError::summary(self : HttpAdapterError) -> String {
  match self {
    UnsupportedMethod => "unsupported HTTP method"
    UnsupportedRequestBody => "unsupported request body representation"
    UnsupportedDuplicateHeaders =>
      "duplicate request header names are not supported"
    InvalidTimeout => "HTTP timeout must be positive"
    TimedOut => "HTTP request timed out"
    RequestFailed => "HTTP request failed"
  }
}
