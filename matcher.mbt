///|
/// A cassette entry considered during request matching.
///
/// `key` is a value-safe summary. It is intentionally not the internal
/// normalized matching key, so a replay error cannot expose recorded headers,
/// query values, or request bodies.
pub(all) struct MatchCandidate {
  index : Int
  key : String
} derive(Eq, @debug.Debug)

///|
/// The result of matching a request against the unconsumed cassette entries.
pub(all) enum MatchResult {
  Matched(Int)
  NoMatch(Array[MatchCandidate])
} derive(Eq, @debug.Debug)

///|
/// Build the same key used by the matcher for diagnostics and tooling.
pub fn request_match_key(request : Request, config : MatchConfig) -> String {
  normalize_request(request, config)
}

///|
/// Return every unconsumed entry with a value-safe summary for diagnostics.
pub fn match_candidates(
  request : Request,
  cassette : Cassette,
  config : MatchConfig,
  consumed : Array[Bool],
) -> Array[MatchCandidate] {
  let candidates : Array[MatchCandidate] = []
  let _ = request
  let _ = config
  for index in 0..<cassette.interactions.length() {
    let used = if index < consumed.length() { consumed[index] } else { false }
    if !used {
      candidates.push({
        index,
        key: request_safe_summary(cassette.interactions[index].request),
      })
    }
  }
  candidates
}

///|
/// Match the first unconsumed interaction with an identical normalized key.
pub fn match_request(
  request : Request,
  cassette : Cassette,
  config : MatchConfig,
  consumed : Array[Bool],
) -> MatchResult {
  let request_key = normalize_request(request, config)
  for index in 0..<cassette.interactions.length() {
    let used = if index < consumed.length() { consumed[index] } else { false }
    if !used {
      let candidate_key = normalize_request(
        cassette.interactions[index].request,
        config,
      )
      if candidate_key == request_key {
        return Matched(index)
      }
    }
  }
  NoMatch(match_candidates(request, cassette, config, consumed))
}
