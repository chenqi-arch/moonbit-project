///|
/// Controls which request fields participate in cassette matching.
pub(all) enum BodyMatchMode {
  Exact
  Ignore
} derive(Eq, @debug.Debug)

///|
/// Header and body matching policy for a session.
pub(all) struct MatchConfig {
  include_headers : Array[String]
  ignore_headers : Array[String]
  body_mode : BodyMatchMode
} derive(Eq, @debug.Debug)

///|
/// Return the conservative default matching policy.
pub fn MatchConfig::default() -> MatchConfig {
  { include_headers: [], ignore_headers: [], body_mode: Exact, }
}

///|
fn normalized_header_name(name : String) -> String {
  name.trim().to_owned().to_lower()
}

///|
fn normalized_header_value(value : String) -> String {
  value.trim().to_owned()
}

///|
fn header_name_is_listed(name : String, names : Array[String]) -> Bool {
  let normalized = normalized_header_name(name)
  for candidate in names {
    if normalized == normalized_header_name(candidate) {
      return true
    }
  }
  false
}

///|
fn should_include_header(name : String, config : MatchConfig) -> Bool {
  if header_name_is_listed(name, config.ignore_headers) {
    return false
  }
  if config.include_headers.length() == 0 {
    return true
  }
  header_name_is_listed(name, config.include_headers)
}

///|
fn normalize_query(url : String) -> String {
  let without_fragment = match url.split_once("#") {
    Some((before, _)) => before.to_owned()
    None => url
  }
  match without_fragment.split_once("?") {
    None => without_fragment
    Some((base, raw_query)) => {
      let parts : Array[String] = []
      for raw_part in raw_query.split("&") {
        let part = raw_part.to_owned().trim().to_owned()
        if part.length() == 0 {
          continue
        }
        let normalized = match part.split_once("=") {
          Some((key, value)) =>
            normalized_header_value(key.to_owned()) +
            "=" +
            normalized_header_value(value.to_owned())
          None => normalized_header_value(part) + "="
        }
        parts.push(normalized)
      }
      if parts.length() == 0 {
        base.to_owned()
      } else {
        parts.sort_by((left, right) => left.compare(right))
        base.to_owned() + "?" + parts.join("&")
      }
    }
  }
}

///|
/// Remove fragments and sort query pairs without decoding user data.
pub fn normalize_url(url : String) -> String {
  normalize_query(url)
}

///|
fn normalize_headers(headers : Array[Header], config : MatchConfig) -> String {
  let parts : Array[String] = []
  for header in headers {
    if should_include_header(header.name, config) {
      parts.push(
        normalized_header_name(header.name) +
        "=" +
        normalized_header_value(header.value),
      )
    }
  }
  parts.sort_by((left, right) => left.compare(right))
  parts.join("&")
}

///|
fn normalize_body(body : Body, mode : BodyMatchMode) -> String {
  match mode {
    Ignore => ""
    Exact =>
      match body {
        Empty => "empty"
        Text(value) => "text:" + value.length().to_string() + ":" + value
        Base64(value) => "base64:" + value.length().to_string() + ":" + value
      }
  }
}

///|
/// Build a deterministic, transport-independent key for a request.
pub fn normalize_request(request : Request, config : MatchConfig) -> String {
  let method = request.method.trim().to_owned().to_upper()
  let headers = normalize_headers(request.headers, config)
  let body = normalize_body(request.body, config.body_mode)
  "method=" +
  method +
  "\nurl=" +
  normalize_url(request.url) +
  "\nheaders=" +
  headers +
  "\nbody=" +
  body
}
