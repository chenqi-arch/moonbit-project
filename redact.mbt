///|
/// The fixed marker written in place of a value that must not enter a cassette.
pub const REDACTION_MARKER : String = "[REDACTED]"

///|
/// Additional redaction rules supplied by the caller.
///
/// Header and query names are compared case-insensitively. json_paths accepts
/// JSON Pointer paths such as /credentials/token and a dot shorthand such as
/// credentials.token. Array indexes are supported by JSON Pointer segments.
pub(all) struct RedactionConfig {
  headers : Array[String]
  query_parameters : Array[String]
  json_paths : Array[String]
} derive(Eq, @debug.Debug)

///|
/// Conservative defaults for credentials commonly sent by HTTP clients.
pub fn RedactionConfig::default() -> RedactionConfig {
  {
    headers: [
      "authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key",
      "x-auth-token", "x-access-token",
    ],
    query_parameters: [
      "api_key", "apikey", "access_token", "refresh_token", "client_secret", "token",
      "signature", "sig", "key", "secret",
    ],
    json_paths: [],
  }
}

///|
/// Errors raised when a configured value cannot be removed safely.
pub(all) enum RedactionError {
  InvalidJson(String)
  InvalidPath(String)
  MissingPath(String)
} derive(Eq, @debug.Debug)

///|
fn sensitive_header(name : String, config : RedactionConfig) -> Bool {
  header_name_is_listed(name, RedactionConfig::default().headers) ||
  header_name_is_listed(name, config.headers)
}

///|
fn sensitive_query_parameter(name : String, config : RedactionConfig) -> Bool {
  let normalized = percent_decode_query_name(name.trim().to_owned().to_lower())
  for candidate in RedactionConfig::default().query_parameters {
    if normalized ==
      percent_decode_query_name(candidate.trim().to_owned().to_lower()) {
      return true
    }
  }
  for candidate in config.query_parameters {
    if normalized ==
      percent_decode_query_name(candidate.trim().to_owned().to_lower()) {
      return true
    }
  }
  false
}

///|
fn hex_digit(value : Int) -> Int? {
  if value >= '0'.to_int() && value <= '9'.to_int() {
    return Some(value - '0'.to_int())
  }
  if value >= 'a'.to_int() && value <= 'f'.to_int() {
    return Some(value - 'a'.to_int() + 10)
  }
  if value >= 'A'.to_int() && value <= 'F'.to_int() {
    return Some(value - 'A'.to_int() + 10)
  }
  None
}

///|
/// Decode percent escapes in a query parameter name for sensitive-name
/// matching. Invalid escapes are retained and therefore cannot hide a name.
fn percent_decode_query_name(name : String) -> String {
  let output = StringBuilder(size_hint=name.length())
  let mut index = 0
  while index < name.length() {
    let code = name.unsafe_get(index)
    if code.to_int() == '%'.to_int() && index + 2 < name.length() {
      let first = hex_digit(name.unsafe_get(index + 1).to_int())
      let second = hex_digit(name.unsafe_get(index + 2).to_int())
      match (first, second) {
        (Some(left), Some(right)) => {
          output.write_char((left * 16 + right).unsafe_to_char())
          index += 3
          continue
        }
        _ => ()
      }
    }
    output.write_char(code.unsafe_to_char())
    index += 1
  }
  output.to_string()
}

///|
/// Remove URL user information before query redaction. The host and path are
/// retained, while both usernames and passwords are replaced together.
fn redact_url_userinfo(url : String) -> String {
  match url.split_once("://") {
    None => url
    Some((scheme, rest)) => {
      let (authority, suffix) = match rest.split_once("/") {
        Some((host, path)) => (host.to_owned(), "/" + path.to_owned())
        None =>
          match rest.split_once("?") {
            Some((host, query)) => (host.to_owned(), "?" + query.to_owned())
            None => (rest.to_owned(), "")
          }
      }
      match authority.split_once("@") {
        Some((_, host)) =>
          scheme.to_owned() +
          "://" +
          REDACTION_MARKER +
          "@" +
          host.to_owned() +
          suffix
        None => url
      }
    }
  }
}

///|
fn redact_headers(
  headers : Array[Header],
  config : RedactionConfig,
) -> Array[Header] {
  headers.map(header => {
    if sensitive_header(header.name, config) {
      { name: header.name, value: REDACTION_MARKER, }
    } else {
      header
    }
  })
}

///|
/// Replace sensitive query values while preserving the URL's other spelling.
fn redact_url(url : String, config : RedactionConfig) -> String {
  let (without_fragment, fragment) = match url.split_once("#") {
    Some((before, after)) => (before.to_owned(), Some(after.to_owned()))
    None => (url, None)
  }
  let without_userinfo = redact_url_userinfo(without_fragment)
  match without_userinfo.split_once("?") {
    None =>
      match fragment {
        Some(value) => without_userinfo + "#" + value
        None => without_userinfo
      }
    Some((base, raw_query)) => {
      let parts : Array[String] = []
      let mut changed = false
      for raw_view in raw_query.split("&") {
        let raw = raw_view.to_owned()
        match raw.split_once("=") {
          Some((key, value)) =>
            if sensitive_query_parameter(key.to_owned(), config) {
              parts.push(
                key.to_owned().trim().to_owned() + "=" + REDACTION_MARKER,
              )
              changed = true
            } else {
              parts.push(key.to_owned() + "=" + value.to_owned())
            }
          None =>
            if sensitive_query_parameter(raw, config) {
              parts.push(raw.trim().to_owned() + "=" + REDACTION_MARKER)
              changed = true
            } else {
              parts.push(raw)
            }
        }
      }
      let rebuilt = base.to_owned() + "?" + parts.join("&")
      let rebuilt = match fragment {
        Some(value) => rebuilt + "#" + value
        None => rebuilt
      }
      if !changed {
        return rebuilt
      }
      rebuilt
    }
  }
}

///|
fn decode_pointer_token(
  raw : StringView,
  path : String,
) -> Result[String, RedactionError] {
  let output = StringBuilder(size_hint=raw.length())
  let mut index = 0
  while index < raw.length() {
    let character = raw.unsafe_get(index)
    if character == '~' {
      if index + 1 >= raw.length() {
        return Err(InvalidPath(path + ""))
      }
      let escaped = raw.unsafe_get(index + 1)
      match escaped {
        '0' => output.write_char('~')
        '1' => output.write_char('/')
        _ => return Err(InvalidPath(path + ""))
      }
      index += 2
    } else {
      output.write_char(character.unsafe_to_char())
      index += 1
    }
  }
  Ok(output.to_string())
}

///|
/// Parse JSON Pointer or the documented dot shorthand into object-key tokens.
fn parse_redaction_path(path : String) -> Result[Array[String], RedactionError] {
  let trimmed = path.trim().to_owned()
  if trimmed.length() == 0 || trimmed == "$" {
    return Err(InvalidPath(path + ""))
  }
  if trimmed.has_prefix("/") {
    let tokens : Array[String] = []
    let tail = trimmed[1:].to_owned()
    for raw in tail.split("/") {
      match decode_pointer_token(raw, path + "") {
        Ok(token) => tokens.push(token)
        Err(error) => return Err(error)
      }
    }
    return Ok(tokens)
  }
  let shorthand = if trimmed.has_prefix("$.") {
    trimmed[2:].to_owned()
  } else if trimmed.has_prefix("$") {
    return Err(InvalidPath(path + ""))
  } else {
    trimmed
  }
  let tokens : Array[String] = []
  for raw in shorthand.split(".") {
    let token = raw.to_owned().trim().to_owned()
    if token.length() == 0 || token.contains_char('/') {
      return Err(InvalidPath(path + ""))
    }
    tokens.push(token)
  }
  Ok(tokens)
}

///|
fn parse_array_index(token : String) -> Int? {
  if token.length() == 0 {
    return None
  }
  let mut result = 0
  for index in 0..<token.length() {
    let code = token.unsafe_get(index).to_int()
    let zero = '0'.to_int()
    let nine = '9'.to_int()
    if code < zero || code > nine {
      return None
    }
    let digit = code - zero
    if result > (2147483647 - digit) / 10 {
      return None
    }
    result = result * 10 + digit
  }
  Some(result)
}

///|
fn redact_json_at(
  value : Json,
  tokens : Array[String],
  depth : Int,
  path : String,
) -> Result[Json, RedactionError] {
  if depth >= tokens.length() {
    return Ok(Json::string(REDACTION_MARKER))
  }
  let token = tokens[depth] + ""
  match value {
    Object(members) =>
      match members.get(token + "") {
        None => Err(MissingPath(path + ""))
        Some(child) =>
          match redact_json_at(child, tokens, depth + 1, path) {
            Ok(updated_child) => {
              let updated = members.copy()
              updated[token] = updated_child
              Ok(Json::object(updated))
            }
            Err(error) => Err(error)
          }
      }
    Array(items) =>
      match parse_array_index(token) {
        None => Err(InvalidPath(path + ""))
        Some(index) =>
          match items.get(index) {
            None => Err(MissingPath(path + ""))
            Some(child) =>
              match redact_json_at(child, tokens, depth + 1, path) {
                Ok(updated_child) => {
                  let updated = items.copy()
                  updated[index] = updated_child
                  Ok(Json::array(updated))
                }
                Err(error) => Err(error)
              }
          }
      }
    _ => Err(MissingPath(path + ""))
  }
}

///|
fn redact_json_text(
  text : String,
  config : RedactionConfig,
) -> Result[String, RedactionError] {
  let mut json = @json.parse(text) catch {
    _ => return Err(InvalidJson("body is not valid JSON text"))
  }
  for path in config.json_paths {
    let tokens = match parse_redaction_path(path + "") {
      Ok(tokens) => tokens
      Err(error) => return Err(error)
    }
    json = match redact_json_at(json, tokens, 0, path + "") {
      Ok(updated) => updated
      Err(error) => return Err(error)
    }
  }
  Ok(json.stringify())
}

///|
fn redact_body(
  body : Body,
  config : RedactionConfig,
) -> Result[Body, RedactionError] {
  match body {
    Text(text) if config.json_paths.length() > 0 =>
      match redact_json_text(text, config) {
        Ok(value) => Ok(Text(value))
        Err(error) => Err(error)
      }
    other => Ok(other)
  }
}

///|
/// Return a request safe to store in a cassette.
pub fn redact_request(
  request : Request,
  config : RedactionConfig,
) -> Result[Request, RedactionError] {
  let { method, url, headers, body, } = request
  match redact_body(body, config) {
    Ok(safe_body) =>
      Ok({
        method,
        url: redact_url(url, config),
        headers: redact_headers(headers, config),
        body: safe_body,
      })
    Err(error) => Err(error)
  }
}

///|
/// Return a response safe to store in a cassette.
pub fn redact_response(
  response : Response,
  config : RedactionConfig,
) -> Result[Response, RedactionError] {
  let { status, headers, body, } = response
  match redact_body(body, config) {
    Ok(safe_body) =>
      Ok({ status, headers: redact_headers(headers, config), body: safe_body, })
    Err(error) => Err(error)
  }
}

///|
/// Redact both sides of an interaction before it is persisted.
pub fn redact_interaction(
  interaction : Interaction,
  config : RedactionConfig,
) -> Result[Interaction, RedactionError] {
  let { request, response, } = interaction
  match redact_request(request, config) {
    Err(error) => Err(error)
    Ok(safe_request) =>
      match redact_response(response, config) {
        Err(error) => Err(error)
        Ok(safe_response) =>
          Ok({ request: safe_request, response: safe_response, })
      }
  }
}
