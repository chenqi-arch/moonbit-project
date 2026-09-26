///|
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
#cfg(target="native")
async test "cassette archive rejects missing files" {
  let path = "_build/moonvcr-native-missing.json"
  @fs.remove(path) catch {
    _ => ()
  }
  let rejected = try {
    let _ = load_cassette_default(path)
    false
  } catch {
    MissingFile => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
}

///|
#cfg(target="native")
async test "cassette archive enforces size guard" {
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

///|
#cfg(target="native")
async test "cassette archive rejects malformed JSON" {
  let path = "_build/moonvcr-native-malformed.json"
  @fs.remove(path) catch {
    _ => ()
  }
  defer @fs.remove(path)
  @fs.write_file(path, "{not-json", create_mode=@fs.CreateNew)
  let rejected = try {
    let _ = load_cassette_default(path)
    false
  } catch {
    DecodeFailed(_) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
}

///|
#cfg(target="native")
async test "save new never overwrites an existing cassette" {
  let path = "_build/moonvcr-native-no-overwrite.json"
  @fs.remove(path) catch {
    _ => ()
  }
  defer @fs.remove(path)
  save_cassette_new(path, @moonvcr.example_cassette())
  let original_size = @fs.file_size(path)
  let rejected = try {
    save_cassette_new(path, @moonvcr.Cassette::empty())
    false
  } catch {
    AlreadyExists => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
  inspect(@fs.file_size(path) == original_size, content="true")
}

///|
#cfg(target="native")
async test "temporary collision preserves existing destination" {
  let path = "_build/moonvcr-native-temp-collision.json"
  let temporary = path + ".moonvcr.tmp"
  @fs.remove(path) catch {
    _ => ()
  }
  @fs.remove(temporary) catch {
    _ => ()
  }
  defer @fs.remove(path)
  defer @fs.remove(temporary)
  save_cassette_new(path, @moonvcr.example_cassette())
  let original_size = @fs.file_size(path)
  @fs.write_file(temporary, "occupied", create_mode=@fs.CreateNew)
  let rejected = try {
    save_cassette_replace(path, @moonvcr.Cassette::empty())
    false
  } catch {
    TemporaryFileExists => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
  inspect(@fs.file_size(path) == original_size, content="true")
}
