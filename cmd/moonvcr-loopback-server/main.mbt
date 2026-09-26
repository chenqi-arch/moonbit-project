///|
async fn send_text(
  conn : @http.ServerConnection,
  status : Int,
  reason : String,
  text : String,
  headers? : @http.Headers = Map([]),
) -> Unit {
  conn
  ..send_response(status, reason, extra_headers=headers)
  ..write(text)
  .end_response()
}

///|
async fn handle_request(
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  match (request.meth, request.path) {
    (@http.Get, "/health") =>
      send_text(conn, 200, "OK", "ready", headers={
        "Content-Type": "text/plain",
      })
    (@http.Get, path) if path.has_prefix("/items?") =>
      send_text(
        conn,
        200,
        "OK",
        "{\"items\":[{\"id\":1}],\"next\":null,\"response_token\":\"server-secret\"}",
        headers={
          "Content-Type": "application/json",
          "X-MoonVCR-Server": "loopback",
        },
      )
    (@http.Post, path) if path.has_prefix("/orders?") => {
      let client_id = request.headers.get("x-client-id").unwrap_or("")
      let body_text = body.read_all().text() catch { _ => "" }
      if client_id != "integration" || !body_text.contains("request_token") {
        send_text(conn, 400, "Bad Request", "invalid request")
      } else {
        send_text(
          conn,
          201,
          "Created",
          "{\"id\":42,\"state\":\"created\",\"items\":[{\"sku\":\"demo\"}],\"response_token\":\"response-secret\"}",
          headers={
            "Content-Type": "application/json",
            "X-MoonVCR-Server": "loopback",
          },
        )
      }
    }
    (@http.Get, "/bytes") =>
      conn
      ..send_response(200, "OK", extra_headers={
        "Content-Type": "application/octet-stream",
      })
      ..write(b"\xff\x00\xfe")
      .end_response()
    (@http.Get, "/slow") => {
      @async.sleep(500)
      send_text(conn, 200, "OK", "slow response")
    }
    (@http.Get, "/redirect") =>
      send_text(conn, 302, "Found", "redirect", headers={
        "Location": "/health",
      })
    (@http.Get, "/status/503") =>
      send_text(conn, 503, "Service Unavailable", "synthetic outage")
    _ => send_text(conn, 404, "Not Found", "not found")
  }
}

///|
async fn main {
  let server = @http.Server(
    @socket.Addr::parse("127.0.0.1:38081"),
    reuse_addr=true,
  )
  println("MoonVCR loopback ready on 127.0.0.1:38081")
  // A health probe or one-shot client normally closes its connection after the
  // response. Keep that connection-local EOF from terminating the whole test
  // service before the next acceptance request arrives.
  server.run_forever(allow_failure=true) <| handle_request
}
