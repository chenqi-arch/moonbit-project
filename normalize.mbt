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
      let parts : Array[(String, String, Int)] = []
      for raw_part in raw_query.split("&") {
        let part = raw_part.to_owned()
        if part.length() == 0 {
          continue
        }
        let (name, normalized) = match part.split_once("=") {
          Some((key, value)) =>
            (key.to_owned(), key.to_owned() + "=" + value.to_owned())
          None => (part, part + "=")
        }
        // Encoded spellings of one name still share an ordered value group.
        parts.push(
          (
            percent_decode_query_name(name, plus_as_space=true),
            normalized,
            parts.length(),
          ),
        )
      }
      if parts.length() == 0 {
        base.to_owned()
      } else {
        parts.sort_by((left, right) => {
          let (left_name, _, left_index) = left
          let (right_name, _, right_index) = right
          let order = left_name.compare(right_name)
          if order == 0 {
            left_index.compare(right_index)
          } else {
            order
          }
        })
        base.to_owned() +
        "?" +
        parts
        .map(part => {
          let (_, value, _) = part
          value
        })
        .join("&")
      }
    }
  }
}

///|
/// Remove fragments and order different query names without changing the
/// relative order of repeated names or trimming query values.
pub fn normalize_url(url : String) -> String {
  normalize_query(url)
}

///|
fn normalize_headers(headers : Array[Header], config : MatchConfig) -> String {
  let parts : Array[(String, String, Int)] = []
  for header in headers {
    if should_include_header(header.name, config) {
      let name = normalized_header_name(header.name)
      parts.push(
        (
          name,
          length_prefix(name) +
          "=" +
          length_prefix(normalized_header_value(header.value)),
          parts.length(),
        ),
      )
    }
  }
  parts.sort_by((left, right) => {
    let (left_name, _, left_index) = left
    let (right_name, _, right_index) = right
    let order = left_name.compare(right_name)
    if order == 0 {
      left_index.compare(right_index)
    } else {
      order
    }
  })
  parts
  .map(part => {
    let (_, value, _) = part
    value
  })
  .join("&")
}

///|
fn normalize_body(body : Body, mode : BodyMatchMode) -> String {
  match mode {
    Ignore => ""
    Exact =>
      match body {
        Empty => "empty"
        Text(value) => "text:" + length_prefix(value)
        Base64(value) => "base64:" + length_prefix(value)
      }
  }
}

///|
/// Prefix a value with its length so delimiters inside the value cannot make
/// two different request structures share the same matching key.
fn length_prefix(value : String) -> String {
  value.length().to_string() + ":" + value
}

///|
/// Describe a request without copying URL, header, query, or body values.
/// This is suitable for public candidate errors.
pub fn request_safe_summary(request : Request) -> String {
  let method = safe_method_description(request.method)
  let body = match request.body {
    Empty => "empty"
    Text(value) => "text(len=" + value.length().to_string() + ")"
    Base64(value) => "base64(len=" + value.length().to_string() + ")"
  }
  "method=" +
  method +
  ",url-len=" +
  request.url.length().to_string() +
  ",headers=" +
  request.headers.length().to_string() +
  ",body=" +
  body
}

///|
fn safe_method_description(method : String) -> String {
  let normalized = method.trim().to_owned().to_upper()
  match normalized {
    "GET"
    | "HEAD"
    | "POST"
    | "PUT"
    | "DELETE"
    | "CONNECT"
    | "OPTIONS"
    | "TRACE"
    | "PATCH" => normalized
    _ => "<method len=" + normalized.length().to_string() + ">"
  }
}

///|
fn safe_name_description(kind : String, name : String) -> String {
  "<" +
  kind +
  " len=" +
  name.length().to_string() +
  ",fp=" +
  safe_fingerprint(name) +
  ">"
}

///|
/// Build a deterministic, transport-independent key for a request.
pub fn normalize_request(request : Request, config : MatchConfig) -> String {
  let method = request.method.trim().to_owned().to_upper()
  let headers = normalize_headers(request.headers, config)
  let body = normalize_body(request.body, config.body_mode)
  "method=" +
  length_prefix(method) +
  "\nurl=" +
  length_prefix(normalize_url(request.url)) +
  "\nheaders=" +
  headers +
  "\nbody=" +
  body
}
