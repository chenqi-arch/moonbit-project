///|
/// A cassette entry considered during request matching.
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
/// Return every unconsumed entry, retaining its normalized key for diagnostics.
pub fn match_candidates(
  request : Request,
  cassette : Cassette,
  config : MatchConfig,
  consumed : Array[Bool],
) -> Array[MatchCandidate] {
  let candidates : Array[MatchCandidate] = []
  let _request_key = normalize_request(request, config)
  for index in 0..<cassette.interactions.length() {
    let used = if index < consumed.length() { consumed[index] } else { false }
    if !used {
      candidates.push({
        index,
        key: normalize_request(cassette.interactions[index].request, config),
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
  let candidates = match_candidates(request, cassette, config, consumed)
  for candidate in candidates {
    if candidate.key == request_key {
      return Matched(candidate.index)
    }
  }
  NoMatch(candidates)
}
