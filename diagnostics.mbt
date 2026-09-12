///|
/// The field that prevented a request from matching a cassette entry.
pub(all) enum MismatchKind {
  NoCandidate
  Method
  Url
  Query
  Headers
  Body
  Sequence
} derive(Eq, @debug.Debug)

///|
/// One safe, structured difference for a candidate cassette entry.
pub(all) struct Mismatch {
  candidate_index : Int
  kind : MismatchKind
  expected : String
  actual : String
} derive(Eq, @debug.Debug)

///|
/// A deterministic mismatch report suitable for test output.
pub(all) struct MismatchReport {
  request_key : String
  differences : Array[Mismatch]
} derive(Eq, @debug.Debug)

///|
pub fn MismatchKind::label(self : MismatchKind) -> String {
  match self {
    NoCandidate => "no-candidate"
    Method => "method"
    Url => "url"
    Query => "query"
    Headers => "headers"
    Body => "body"
    Sequence => "sequence"
  }
}

///|
/// Render a stable human-readable report. Values are already reduced to safe
/// descriptors by the diagnostic builder.
pub fn MismatchReport::summary(self : MismatchReport) -> String {
  if self.differences.length() == 0 {
    return "no mismatch"
  }
  let lines : Array[String] = ["request mismatch: " + self.request_key]
  for difference in self.differences {
    lines.push(
      "candidate[" +
      difference.candidate_index.to_string() +
      "] " +
      difference.kind.label() +
      ": expected " +
      difference.expected +
      ", actual " +
      difference.actual,
    )
  }
  lines.join("\n")
}

///|
priv struct DiagnosticView {
  method : String
  base_url : String
  query : String
  headers : String
  body : String
  match_base_url : String
  match_query : String
  match_headers : String
  match_body : String
}

///|
fn safe_fingerprint(value : String) -> String {
  let mut result = 17
  for index in 0..<value.length() {
    result = (result * 31 + value.unsafe_get(index).to_int()) % 1000003
  }
  result.to_string()
}

///|
fn diagnostic_query(url : String, config : RedactionConfig) -> String {
  let without_fragment = match url.split_once("#") {
    Some((before, _)) => before.to_owned()
    None => url
  }
  match without_fragment.split_once("?") {
    None => ""
    Some((_, raw_query)) => {
      let parts : Array[String] = []
      for raw_view in raw_query.split("&") {
        let raw = raw_view.to_owned()
        if raw.length() == 0 {
          continue
        }
        match raw.split_once("=") {
          Some((key, value)) => {
            let name = key.to_owned().trim().to_owned().to_lower()
            if sensitive_query_parameter(key.to_owned(), config) {
              parts.push(name + "=<redacted>")
            } else {
              parts.push(
                name +
                "=<len:" +
                value.length().to_string() +
                ",fp:" +
                safe_fingerprint(value.to_owned()) +
                ">",
              )
            }
          }
          None => {
            let name = raw.trim().to_owned().to_lower()
            if sensitive_query_parameter(raw + "", config) {
              parts.push(name + "=<redacted>")
            } else {
              parts.push(name + "=<len:0>")
            }
          }
        }
      }
      parts.sort_by((left, right) => left.compare(right))
      parts.join("&")
    }
  }
}

///|
fn diagnostic_header_parts(
  headers : Array[Header],
  config : MatchConfig,
  redaction : RedactionConfig,
) -> (String, String) {
  let summary_parts : Array[String] = []
  let match_parts : Array[String] = []
  let safe_headers = redact_headers(headers, redaction)
  for header in safe_headers {
    if should_include_header(header.name + "", config) {
      let name = normalized_header_name(header.name + "")
      let normalized_value = normalized_header_value(header.value + "")
      match_parts.push(name + "=" + normalized_value)
      let value = if sensitive_header(header.name + "", redaction) {
        "<redacted>"
      } else {
        "<len:" +
        normalized_value.length().to_string() +
        ",fp:" +
        safe_fingerprint(normalized_value + "") +
        ">"
      }
      summary_parts.push(name + "=" + value)
    }
  }
  summary_parts.sort_by((left, right) => left.compare(right))
  match_parts.sort_by((left, right) => left.compare(right))
  (summary_parts.join("&"), match_parts.join("&"))
}

///|
fn diagnostic_body_parts(
  body : Body,
  config : MatchConfig,
  redaction : RedactionConfig,
) -> (String, String) {
  let safe_body = match redact_body(body, redaction) {
    Ok(value) => value
    Err(_) => return ("<redaction-failed>", "<redaction-failed>")
  }
  match config.body_mode {
    Ignore => ("<ignored>", "")
    Exact =>
      match safe_body {
        Empty => ("empty", "empty")
        Text(value) => {
          let summary = "text<len:" +
            value.length().to_string() +
            ",fp:" +
            safe_fingerprint(value + "") +
            ">"
          (summary, normalize_body(Text(value), Exact))
        }
        Base64(value) => {
          let summary = "base64<len:" +
            value.length().to_string() +
            ",fp:" +
            safe_fingerprint(value + "") +
            ">"
          (summary, normalize_body(Base64(value), Exact))
        }
      }
  }
}

///|
fn diagnostic_view(
  request : Request,
  config : MatchConfig,
  redaction : RedactionConfig,
) -> DiagnosticView {
  let { method, url, headers, body, } = request
  let normalized_url = normalize_url(redact_url(url + "", redaction))
  let (match_base_url, match_query) = match normalized_url.split_once("?") {
    Some((base, query)) => (base.to_owned(), query.to_owned())
    None => (normalized_url + "", "")
  }
  let (header_summary, match_headers) = diagnostic_header_parts(
    headers, config, redaction,
  )
  let (body_summary, match_body) = diagnostic_body_parts(
    body, config, redaction,
  )
  {
    method: method.trim().to_owned().to_upper(),
    base_url: match_base_url + "",
    query: diagnostic_query(url, redaction),
    headers: header_summary,
    body: body_summary,
    match_base_url,
    match_query,
    match_headers,
    match_body,
  }
}

///|
fn diagnostic_key(view : DiagnosticView) -> String {
  "method=" +
  view.method +
  "\nurl=" +
  view.base_url +
  "\nquery=" +
  view.query +
  "\nheaders=" +
  view.headers +
  "\nbody=" +
  view.body
}

///|
fn add_difference(
  differences : Array[Mismatch],
  candidate_index : Int,
  kind : MismatchKind,
  expected : String,
  actual : String,
) -> Unit {
  differences.push({ candidate_index, kind, expected, actual, })
}

///|
/// Build a safe mismatch report while honoring consumed-entry sequence.
pub fn diagnose_mismatch_with_redaction(
  request : Request,
  cassette : Cassette,
  config : MatchConfig,
  consumed : Array[Bool],
  redaction : RedactionConfig,
) -> MismatchReport {
  let actual = diagnostic_view(request, config, redaction)
  let differences : Array[Mismatch] = []
  let mut has_unconsumed = false
  let mut exact_unconsumed = false
  let mut exact_consumed = false
  let mut exact_consumed_index = -1
  for index in 0..<cassette.interactions.length() {
    let used = if index < consumed.length() { consumed[index] } else { false }
    let expected = diagnostic_view(
      cassette.interactions[index].request,
      config,
      redaction,
    )
    let method_matches = actual.method == expected.method
    let base_url_matches = actual.match_base_url == expected.match_base_url
    let query_matches = actual.match_query == expected.match_query
    let headers_match = actual.match_headers == expected.match_headers
    let body_matches = actual.match_body == expected.match_body
    let exact = method_matches &&
      base_url_matches &&
      query_matches &&
      headers_match &&
      body_matches
    if used {
      if exact {
        exact_consumed = true
        if exact_consumed_index == -1 {
          exact_consumed_index = index
        }
      }
      continue
    }
    has_unconsumed = true
    if exact {
      exact_unconsumed = true
      continue
    }
    if !method_matches {
      add_difference(differences, index, Method, expected.method, actual.method)
    }
    if !base_url_matches {
      add_difference(
        differences,
        index,
        Url,
        expected.base_url,
        actual.base_url,
      )
    }
    if !query_matches {
      add_difference(differences, index, Query, expected.query, actual.query)
    }
    if !headers_match {
      add_difference(
        differences,
        index,
        Headers,
        expected.headers,
        actual.headers,
      )
    }
    if !body_matches {
      add_difference(differences, index, Body, expected.body, actual.body)
    }
  }
  if exact_unconsumed {
    return { request_key: diagnostic_key(actual), differences: [], }
  }
  if differences.length() == 0 {
    if exact_consumed {
      add_difference(
        differences,
        exact_consumed_index,
        Sequence,
        "unconsumed cassette entry",
        "entry already consumed",
      )
    } else if !has_unconsumed {
      add_difference(
        differences,
        -1,
        NoCandidate,
        "recorded interaction",
        "no unconsumed candidate",
      )
    }
  }
  { request_key: diagnostic_key(actual), differences, }
}

///|
/// Build a report using the default conservative redaction rules.
pub fn diagnose_mismatch(
  request : Request,
  cassette : Cassette,
  config : MatchConfig,
  consumed : Array[Bool],
) -> MismatchReport {
  diagnose_mismatch_with_redaction(
    request,
    cassette,
    config,
    consumed,
    RedactionConfig::default(),
  )
}
