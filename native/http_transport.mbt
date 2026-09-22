///|
/// Errors from the native HTTP adapter. The underlying library message is not
/// exposed by the public summary because it may contain a URL or credential.
pub suberror HttpAdapterError {
  UnsupportedMethod
  UnsupportedRequestBody
  RequestFailed
} derive(@debug.Debug)

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
fn request_headers(headers : Array[@moonvcr.Header]) -> @http.Headers {
  let result : @http.Headers = Map([])
  for header in headers {
    result[header.name] = header.value
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
fn response_headers(headers : @http.Headers) -> Array[@moonvcr.Header] {
  let result : Array[@moonvcr.Header] = []
  for name, value in headers {
    result.push({ name: name.to_string(), value, })
  }
  result.sort_by((left, right) => left.name.compare(right.name))
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
/// Send a MoonVCR request through MoonBit's official native HTTP client.
/// TLS verification remains enabled by the dependency's default client.
pub async fn send_http(
  request : @moonvcr.Request,
) -> @moonvcr.Response raise HttpAdapterError {
  let method = request_method(request.method + "")
  let body = request_body(request.body)
  let headers = request_headers(request.headers)
  let (response, data) = @http.request(request.url + "", method, headers, body) catch {
    _ => raise RequestFailed
  }
  {
    status: response.code,
    headers: response_headers(response.headers),
    body: response_body(data),
  }
}

///|
/// Record one real HTTP response through a core Session.
pub async fn record_http(
  session : @moonvcr.Session,
  request : @moonvcr.Request,
) -> Result[@moonvcr.Response, @moonvcr.SessionError] {
  let response = send_http(request) catch {
    _ =>
      return Err(
        @moonvcr.SessionError::TransportFailed(
          @moonvcr.TransportError::Failed("native HTTP request failed"),
        ),
      )
  }
  session.record_response(request, response)
}

///|
pub fn HttpAdapterError::summary(self : HttpAdapterError) -> String {
  match self {
    UnsupportedMethod => "unsupported HTTP method"
    UnsupportedRequestBody =>
      "request body representation is not supported by this adapter"
    RequestFailed => "HTTP request failed"
  }
}
