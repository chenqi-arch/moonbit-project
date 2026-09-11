///|
/// The cassette schema supported by this release.
pub const CURRENT_FORMAT_VERSION : Int = 1

///|
/// A HTTP header stored in a cassette.
pub(all) struct Header {
  name : String
  value : String
} derive(ToJson, FromJson, Eq, @debug.Debug)

///|
/// A request or response body.
pub(all) enum Body {
  Empty
  Text(String)
  Base64(String)
} derive(ToJson, FromJson, Eq, @debug.Debug)

///|
/// The request captured in one interaction.
pub(all) struct Request {
  method : String
  url : String
  headers : Array[Header]
  body : Body
} derive(ToJson, FromJson, Eq, @debug.Debug)

///|
/// The response captured in one interaction.
pub(all) struct Response {
  status : Int
  headers : Array[Header]
  body : Body
} derive(ToJson, FromJson, Eq, @debug.Debug)

///|
/// One request/response pair in a cassette.
pub(all) struct Interaction {
  request : Request
  response : Response
} derive(ToJson, FromJson, Eq, @debug.Debug)

///|
/// A versioned collection of recorded HTTP interactions.
pub(all) struct Cassette {
  format_version : Int
  interactions : Array[Interaction]
} derive(ToJson, FromJson, Eq, @debug.Debug)

///|
/// Errors raised while reading a cassette.
pub(all) suberror CassetteError {
  InvalidJson
  InvalidSchema
  UnsupportedVersion(Int)
} derive(Eq, @debug.Debug)

///|
/// Create an empty cassette using the current schema version.
pub fn Cassette::empty() -> Cassette {
  { format_version: CURRENT_FORMAT_VERSION, interactions: [], }
}

///|
/// Encode a cassette as deterministic JSON text.
pub fn Cassette::encode(self : Cassette) -> String {
  @json.to_json(self).stringify() + "\n"
}

///|
/// Decode a cassette and reject schema versions this release cannot handle.
pub fn Cassette::decode(text : String) -> Cassette raise CassetteError {
  let json = @json.parse(text) catch { _ => raise InvalidJson }
  let cassette : Cassette = @json.from_json(json) catch {
    _ => raise InvalidSchema
  }
  if cassette.format_version != CURRENT_FORMAT_VERSION {
    raise UnsupportedVersion(cassette.format_version)
  }
  cassette
}

///|
/// Return a small, useful example for documentation and tests.
pub fn example_cassette() -> Cassette {
  {
    format_version: CURRENT_FORMAT_VERSION,
    interactions: [
      {
        request: {
          method: "GET",
          url: "https://api.example.test/v1/items?page=1",
          headers: [{ name: "accept", value: "application/json", }],
          body: Empty,
        },
        response: {
          status: 200,
          headers: [{ name: "content-type", value: "application/json", }],
          body: Text("{\"items\":[]}"),
        },
      },
    ],
  }
}
