///|
/// Run with moon run cmd/moonvcr-demo.
///
/// The transport deliberately fails if called. A successful run therefore
/// proves that StrictOffline serves the cassette without touching the network.
fn main {
  let cassette_text = @moonvcr.Cassette::encode(@moonvcr.example_cassette())
  let cassette = @moonvcr.Cassette::decode(cassette_text) catch {
    _ => {
      println("cassette decode failed")
      return
    }
  }
  let request : @moonvcr.Request = {
    method: "GET",
    url: "https://api.example.test/v1/items?page=1",
    headers: [{ name: "accept", value: "application/json", }],
    body: @moonvcr.Body::Empty,
  }
  let session = @moonvcr.Session::with_defaults(
    cassette,
    @moonvcr.SessionMode::StrictOffline,
  )
  let offline_transport = (_request : @moonvcr.Request) => {
    Err(@moonvcr.TransportError::Failed("network disabled"))
  }
  match session.send(request, offline_transport) {
    Ok(response) => {
      println("offline replay status=" + response.status.to_string())
      match response.body {
        @moonvcr.Body::Text(body) => println(body)
        @moonvcr.Body::Empty => println("<empty body>")
        @moonvcr.Body::Base64(_) => println("<base64 body>")
      }
    }
    Err(_) => println("offline replay failed")
  }
  let scripted = @moonvcr.ScriptedTransport::new([
    {
      status: 201,
      headers: [],
      body: @moonvcr.Body::Text("recorded response"),
    },
  ])
  let record_session = @moonvcr.Session::with_defaults(
    @moonvcr.Cassette::empty(),
    @moonvcr.SessionMode::Record,
  )
  match record_session.send(request, request => scripted.send(request)) {
    Ok(_) =>
      println(
        "recorded interactions=" +
        record_session.cassette().interactions.length().to_string(),
      )
    Err(_) => println("record failed")
  }
}
