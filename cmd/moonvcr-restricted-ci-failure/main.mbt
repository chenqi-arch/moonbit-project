///|
fn main {
  let cassette = @moonvcr.example_cassette()
  let session = @moonvcr.Session::with_defaults(
    cassette,
    @moonvcr.StrictOffline,
  )
  let unexpected : @moonvcr.Request = {
    method: "DELETE",
    url: "https://api.example.test/v1/items?page=1",
    headers: [{ name: "Accept", value: "application/json", }],
    body: @moonvcr.Empty,
  }
  let mut transport_calls = 0
  let transport = (_ : @moonvcr.Request) => {
    transport_calls += 1
    Err(@moonvcr.TransportError::Failed("network must stay disabled"))
  }
  match session.send(unexpected, transport) {
    Err(error) => {
      guard transport_calls == 0 else {
        abort("offline failure called transport")
      }
      abort(error.summary())
    }
    Ok(_) => abort("restricted-network failure scenario unexpectedly passed")
  }
}
