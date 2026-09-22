///|
/// Run with `moon run --target native cmd/moonvcr-native-demo`.
///
/// This demo proves the native boundary without contacting a third-party
/// service: a real cassette is durably written, loaded, and decoded again.
async fn main {
  let path = "_build/moonvcr-native-demo.json"
  @fs.remove(path) catch {
    _ => ()
  }
  defer @fs.remove(path)

  let cassette = @moonvcr.example_cassette()
  @native.save_cassette_new(path, cassette)
  let loaded = @native.load_cassette_default(path)
  println(
    "native archive roundtrip interactions=" +
    loaded.interactions.length().to_string(),
  )
}
