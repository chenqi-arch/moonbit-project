///|
fn request(page : Int) -> @moonvcr.Request {
  {
    method: "GET",
    url: "https://api.example.test/items?page=" + page.to_string(),
    headers: [{ name: "Accept", value: "application/json", }],
    body: @moonvcr.Empty,
  }
}

///|
fn main {
  let cassette : @moonvcr.Cassette = {
    format_version: @moonvcr.CURRENT_FORMAT_VERSION,
    interactions: [
      {
        request: request(1),
        response: { status: 200, headers: [], body: @moonvcr.Text("{}"), },
      },
    ],
  }
  let session = @moonvcr.Session::with_defaults(
    cassette,
    @moonvcr.StrictOffline,
  )
  match session.replay(request(3)) {
    Err(error) => abort(error.summary())
    Ok(_) => abort("pagination failure scenario unexpectedly passed")
  }
}
