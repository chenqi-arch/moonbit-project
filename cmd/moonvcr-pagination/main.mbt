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
fn cassette() -> @moonvcr.Cassette {
  {
    format_version: @moonvcr.CURRENT_FORMAT_VERSION,
    interactions: [
      {
        request: request(1),
        response: {
          status: 200,
          headers: [{ name: "Content-Type", value: "application/json", }],
          body: @moonvcr.Text("{\"items\":[1,2],\"next\":2}"),
        },
      },
      {
        request: request(2),
        response: {
          status: 200,
          headers: [{ name: "Content-Type", value: "application/json", }],
          body: @moonvcr.Text("{\"items\":[3],\"next\":null}"),
        },
      },
    ],
  }
}

///|
fn main {
  let session = @moonvcr.Session::with_defaults(
    cassette(),
    @moonvcr.StrictOffline,
  )
  for page in [1, 2] {
    match session.replay(request(page)) {
      Ok(response) if response.status == 200 => ()
      _ => abort("pagination replay failed")
    }
  }
  match session.assert_complete() {
    Ok(_) => println("pagination SDK offline regression passed pages=2")
    Err(_) => abort("pagination replay incomplete")
  }
}
