///|
/// The first vertical slice must be usable without a network connection.
test "empty cassette uses current schema" {
  let cassette = Cassette::empty()
  assert_eq(cassette.format_version, CURRENT_FORMAT_VERSION)
  assert_eq(cassette.interactions.length(), 0)
}

///|
/// A cassette can make a stable JSON round trip.
test "cassette json round trip is stable" {
  let cassette = example_cassette()
  let encoded = cassette.encode()
  let decoded : Cassette = Cassette::decode(encoded)
  assert_eq(decoded, cassette)
  assert_eq(decoded.encode(), encoded)
}

///|
/// Field ordering and the final newline are part of the reviewable format.
test "cassette encoding is reviewable text" {
  let encoded = example_cassette().encode()
  assert_true(encoded.has_suffix("\n"))
  assert_true(encoded.contains("\"format_version\""))
  assert_true(encoded.contains("\"interactions\""))
  assert_true(encoded.contains("\"method\":\"GET\""))
}

///|
/// Unsupported versions fail before a caller can use the data.
test "unsupported cassette version is rejected" {
  let result = Some(
    Cassette::decode("{\"format_version\":99,\"interactions\":[]}"),
  ) catch {
    UnsupportedVersion(version) => {
      assert_eq(version, 99)
      None
    }
    _ => None
  }
  assert_eq(result, None)
}

///|
/// Malformed JSON is reported as a typed cassette error.
test "malformed cassette is rejected" {
  let result = Some(Cassette::decode("not-json")) catch {
    InvalidJson => None
    _ => None
  }
  assert_eq(result, None)
}

///|
test "invalid cassette schema is rejected" {
  let result = Some(
    Cassette::decode(
      "{\u{22}format_version\u{22}:1,\u{22}interactions\u{22}:{}}",
    ),
  ) catch {
    InvalidSchema => None
    _ => None
  }
  assert_eq(result, None)
}

///|
test "base64 bodies round trip without reinterpretation" {
  let cassette : Cassette = {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [
      {
        request: {
          method: "POST",
          url: "https://example.test/upload",
          headers: [],
          body: Base64("AAEC"),
        },
        response: { status: 201, headers: [], body: Base64("AP8="), },
      },
    ],
  }
  assert_eq(Cassette::decode(cassette.encode()), cassette)
}
