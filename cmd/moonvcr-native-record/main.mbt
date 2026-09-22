///|
/// The first half of the cross-process acceptance flow.
async fn main {
  let path = "_build/moonvcr-cross-process.json"
  @native.save_cassette_replace(path, @moonvcr.example_cassette())
  println("native record saved interactions=1")
}
