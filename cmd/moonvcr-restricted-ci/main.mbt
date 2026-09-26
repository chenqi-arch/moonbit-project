///|
fn main {
  let cassette = @moonvcr.example_cassette()
  let request = cassette.interactions[0].request
  let session = @moonvcr.Session::with_defaults(
    cassette,
    @moonvcr.StrictOffline,
  )
  let mut transport_calls = 0
  let transport = (_ : @moonvcr.Request) => {
    transport_calls += 1
    Err(@moonvcr.TransportError::Failed("network must stay disabled"))
  }
  match session.send(request, transport) {
    Ok(response) if response.status == 200 => ()
    _ => abort("restricted-network replay failed")
  }
  guard transport_calls == 0 else { abort("offline replay called transport") }
  match session.assert_complete() {
    Ok(_) => println("restricted-network CI passed network_calls=0")
    Err(_) => abort("restricted-network replay incomplete")
  }
}
