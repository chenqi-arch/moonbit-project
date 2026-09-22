///|
/// The second half of the cross-process acceptance flow. It never supplies a
/// network transport: the response must come from the saved cassette.
async fn main {
  let path = "_build/moonvcr-cross-process.json"
  let cassette = @native.load_cassette_default(path)
  let session = @moonvcr.Session::with_defaults(
    cassette,
    @moonvcr.SessionMode::StrictOffline,
  )
  let request = @moonvcr.example_cassette().interactions[0].request
  match session.replay(request) {
    Ok(response) => {
      guard response.status == 200 else {
        abort("native replay status mismatch")
      }
      match session.assert_complete() {
        Ok(_) => println("native replay offline status=200")
        Err(_) => abort("native replay incomplete")
      }
    }
    Err(_) => abort("native replay failed")
  }
  @fs.remove(path) catch {
    _ => ()
  }
}
