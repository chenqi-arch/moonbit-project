///|
/// The native acceptance test exercises the durable path used by CI and
/// command-line integrations: encode, atomically create, read, and decode.
#cfg(target="native")
async test "cassette archive round trip" {
  let path = "_build/moonvcr-native-roundtrip.json"
  @fs.remove(path) catch {
    _ => ()
  }
  defer @fs.remove(path)

  let original = @moonvcr.example_cassette()
  save_cassette_new(path, original)
  let loaded = load_cassette_default(path)
  inspect(loaded.format_version, content="1")
  inspect(loaded.interactions.length(), content="1")
  inspect(@fs.file_size(path) > 0L, content="true")
}

///|
/// The size guard prevents an unexpectedly large cassette from being loaded
/// into memory by a CI or local verification process.
#cfg(target="native")
async test "cassette archive size guard" {
  let path = "_build/moonvcr-native-size-guard.json"
  @fs.remove(path) catch {
    _ => ()
  }
  defer @fs.remove(path)

  save_cassette_new(path, @moonvcr.example_cassette())
  let rejected = try {
    let _ = load_cassette(path, 1L)
    false
  } catch {
    TooLarge(_) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
}
