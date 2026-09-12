///|
/// Selects whether a session records through a transport or serves a cassette.
pub(all) enum SessionMode {
  Record
  Replay
  StrictOffline
} derive(Eq, @debug.Debug)

///|
/// A transport adapter supplied by the host application.
pub(all) enum TransportError {
  Failed(String)
} derive(Eq, @debug.Debug)

///|
/// Errors returned by the record/replay session.
pub(all) enum SessionError {
  ReplayMiss(Array[MatchCandidate])
  TransportFailed(TransportError)
  RedactionFailed(RedactionError)
} derive(Eq, @debug.Debug)

///|
/// Stateful record/replay session. Replay never invokes its transport.
pub(all) struct Session {
  mut cassette : Cassette
  config : MatchConfig
  redaction : RedactionConfig
  mode : SessionMode
  mut consumed : Array[Bool]
} derive(@debug.Debug)

///|
/// Create a session with an explicit matching policy.
pub fn Session::new(
  cassette : Cassette,
  mode : SessionMode,
  config : MatchConfig,
) -> Session {
  Session::new_with_redaction(
    cassette,
    mode,
    config,
    RedactionConfig::default(),
  )
}

///|
/// Create a session with explicit matching and redaction policies.
pub fn Session::new_with_redaction(
  cassette : Cassette,
  mode : SessionMode,
  config : MatchConfig,
  redaction : RedactionConfig,
) -> Session {
  let count = cassette.interactions.length()
  { cassette, config, redaction, mode, consumed: Array::make(count, false), }
}

///|
/// Create a session using the conservative default matching policy.
pub fn Session::with_defaults(
  cassette : Cassette,
  mode : SessionMode,
) -> Session {
  Session::new(cassette, mode, MatchConfig::default())
}

///|
/// Send one request through the selected mode.
pub fn Session::send(
  self : Session,
  request : Request,
  transport : (Request) -> Result[Response, TransportError],
) -> Result[Response, SessionError] {
  match self.mode {
    Record =>
      match transport(request) {
        Ok(response) => {
          let interaction = { request, response, }
          match redact_interaction(interaction, self.redaction) {
            Ok(safe_interaction) => {
              self.cassette.interactions.push(safe_interaction)
              Ok(response)
            }
            Err(error) => Err(RedactionFailed(error))
          }
        }
        Err(error) => Err(TransportFailed(error))
      }
    Replay | StrictOffline =>
      match redact_request(request, self.redaction) {
        Err(error) => Err(RedactionFailed(error))
        Ok(safe_request) =>
          match
            match_request(
              safe_request,
              self.cassette,
              self.config,
              self.consumed,
            ) {
            Matched(index) => {
              self.consumed[index] = true
              Ok(self.cassette.interactions[index].response)
            }
            NoMatch(candidates) => Err(ReplayMiss(candidates))
          }
      }
  }
}

///|
/// Return the cassette, including interactions recorded so far.
pub fn Session::cassette(self : Session) -> Cassette {
  self.cassette
}
