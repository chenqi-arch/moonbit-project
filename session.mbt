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
  IncompleteReplay(Int)
} derive(Eq, @debug.Debug)

///|
/// Render a safe summary without copying transport messages or secrets.
pub fn SessionError::summary(self : SessionError) -> String {
  match self {
    ReplayMiss(candidates) =>
      "replay miss: " + candidates.length().to_string() + " candidates"
    TransportFailed(_) => "transport failed"
    RedactionFailed(_) => "redaction failed"
    IncompleteReplay(remaining) =>
      "replay incomplete: " + remaining.to_string() + " interactions remain"
  }
}

///|
/// Stateful record/replay session. Replay never invokes its transport.
pub(all) struct Session {
  mut cassette : Cassette
  config : MatchConfig
  redaction : RedactionPolicy
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
  Session::new_with_redaction_policy(
    cassette,
    mode,
    config,
    RedactionPolicy::symmetric(redaction),
  )
}

///|
/// Create a session whose request and response redaction rules are independent.
pub fn Session::new_with_redaction_policy(
  cassette : Cassette,
  mode : SessionMode,
  config : MatchConfig,
  redaction : RedactionPolicy,
) -> Session {
  let count = cassette.interactions.length()
  {
    cassette: copy_cassette(cassette),
    config: copy_match_config(config),
    redaction: copy_redaction_policy(redaction),
    mode,
    consumed: Array::make(count, false),
  }
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
        Ok(response) => self.record_response(request, response)
        Err(error) => Err(TransportFailed(error))
      }
    Replay | StrictOffline => self.replay(request)
  }
}

///|
/// Persist one response obtained by an external, possibly asynchronous
/// transport. The response returned to the caller remains unredacted.
pub fn Session::record_response(
  self : Session,
  request : Request,
  response : Response,
) -> Result[Response, SessionError] {
  let interaction : Interaction = { request, response, }
  match redact_interaction_with_policy(interaction, self.redaction) {
    Ok(safe_interaction) => {
      self.cassette.interactions.push(safe_interaction)
      Ok(response)
    }
    Err(error) => Err(RedactionFailed(error))
  }
}

///|
/// Replay one request without accepting a transport callback. This is useful
/// to platform adapters that need an asynchronous HTTP layer.
pub fn Session::replay(
  self : Session,
  request : Request,
) -> Result[Response, SessionError] {
  match redact_request(request, self.redaction.request) {
    Err(error) => Err(RedactionFailed(error))
    Ok(safe_request) =>
      match
        match_request(safe_request, self.cassette, self.config, self.consumed) {
        Matched(index) => {
          self.consumed[index] = true
          Ok(copy_response(self.cassette.interactions[index].response))
        }
        NoMatch(candidates) => Err(ReplayMiss(candidates))
      }
  }
}

///|
/// Explain why a request would miss the current cassette.
pub fn Session::diagnose(self : Session, request : Request) -> MismatchReport {
  diagnose_mismatch_with_redaction(
    request,
    self.cassette,
    self.config,
    self.consumed,
    self.redaction.request,
  )
}

///|
/// Return the cassette, including interactions recorded so far.
pub fn Session::cassette(self : Session) -> Cassette {
  copy_cassette(self.cassette)
}

///|
/// Number of replay entries that have not been consumed yet.
pub fn Session::remaining_interactions(self : Session) -> Int {
  let mut remaining = 0
  for index in 0..<self.cassette.interactions.length() {
    let used = if index < self.consumed.length() {
      self.consumed[index]
    } else {
      false
    }
    if !used {
      remaining += 1
    }
  }
  remaining
}

///|
/// Fail a replay assertion when the caller did not consume the whole cassette.
pub fn Session::assert_complete(self : Session) -> Result[Unit, SessionError] {
  let remaining = self.remaining_interactions()
  if remaining == 0 {
    Ok(())
  } else {
    Err(IncompleteReplay(remaining))
  }
}

///|
fn copy_header(header : Header) -> Header {
  { name: header.name + "", value: header.value + "", }
}

///|
fn copy_headers(headers : Array[Header]) -> Array[Header] {
  let copied : Array[Header] = []
  for header in headers {
    copied.push(copy_header(header))
  }
  copied
}

///|
fn copy_body(body : Body) -> Body {
  match body {
    Empty => Empty
    Text(value) => Text(value + "")
    Base64(value) => Base64(value + "")
  }
}

///|
fn copy_request(request : Request) -> Request {
  {
    method: request.method + "",
    url: request.url + "",
    headers: copy_headers(request.headers),
    body: copy_body(request.body),
  }
}

///|
fn copy_response(response : Response) -> Response {
  {
    status: response.status,
    headers: copy_headers(response.headers),
    body: copy_body(response.body),
  }
}

///|
fn copy_cassette(cassette : Cassette) -> Cassette {
  let interactions : Array[Interaction] = []
  for interaction in cassette.interactions {
    interactions.push({
      request: copy_request(interaction.request),
      response: copy_response(interaction.response),
    })
  }
  { format_version: cassette.format_version, interactions, }
}

///|
fn copy_match_config(config : MatchConfig) -> MatchConfig {
  {
    include_headers: config.include_headers.map(value => value + ""),
    ignore_headers: config.ignore_headers.map(value => value + ""),
    body_mode: config.body_mode,
  }
}

///|
fn copy_redaction_config(config : RedactionConfig) -> RedactionConfig {
  {
    headers: config.headers.map(value => value + ""),
    query_parameters: config.query_parameters.map(value => value + ""),
    json_paths: config.json_paths.map(value => value + ""),
    optional_json_paths: config.optional_json_paths.map(value => value + ""),
  }
}

///|
fn copy_redaction_policy(policy : RedactionPolicy) -> RedactionPolicy {
  {
    request: copy_redaction_config(policy.request),
    response: copy_redaction_config(policy.response),
  }
}
