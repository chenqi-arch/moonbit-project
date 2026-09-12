///|
/// A deterministic transport adapter backed by a finite response script.
///
/// The adapter is useful for examples and tests: it never opens a socket, and
/// once the script is exhausted it returns a typed error instead of guessing
/// a response.
pub(all) struct ScriptedTransport {
  responses : Array[Response]
  mut cursor : Int
} derive(@debug.Debug)

///|
pub fn ScriptedTransport::new(responses : Array[Response]) -> ScriptedTransport {
  { responses, cursor: 0, }
}

///|
/// Return the next scripted response, or fail when no response remains.
pub fn ScriptedTransport::send(
  self : ScriptedTransport,
  _request : Request,
) -> Result[Response, TransportError] {
  if self.cursor >= self.responses.length() {
    return Err(TransportError::Failed("scripted transport exhausted"))
  }
  let response = self.responses[self.cursor]
  self.cursor += 1
  Ok(response)
}

///|
pub fn ScriptedTransport::remaining(self : ScriptedTransport) -> Int {
  self.responses.length() - self.cursor
}
