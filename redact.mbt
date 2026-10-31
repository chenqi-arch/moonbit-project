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
  optional_json_paths : Array[String]
} derive(Eq, @debug.Debug)

///|
/// Independent request and response rules for a recorded interaction.
///
/// Keeping the two sides separate avoids requiring a request-only path in a
/// response body (or vice versa). `RedactionConfig` remains available for the
/// symmetric compatibility API.
pub(all) struct RedactionPolicy {
  request : RedactionConfig
  response : RedactionConfig
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
    optional_json_paths: [],
  }
}

///|
pub fn RedactionPolicy::default() -> RedactionPolicy {
  { request: RedactionConfig::default(), response: RedactionConfig::default(), }
}

///|
/// Apply one configuration to both sides for compatibility with the original
/// MoonVCR API.
pub fn RedactionPolicy::symmetric(config : RedactionConfig) -> RedactionPolicy {
  { request: config, response: config, }
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
  let normalized = percent_decode_query_name(name, plus_as_space=true)
    .trim()
    .to_owned()
    .to_lower()
  for candidate in RedactionConfig::default().query_parameters {
    if normalized ==
      percent_decode_query_name(candidate).trim().to_owned().to_lower() {
      return true
    }
  }
  for candidate in config.query_parameters {
    if normalized ==
      percent_decode_query_name(candidate).trim().to_owned().to_lower() {
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
/// matching, exactly once. Literal '+' is form-space only in the URL, not in
/// caller-defined names. Invalid escapes/UTF-8 retain their original spelling.
fn percent_decode_query_name(
  name : String,
  plus_as_space? : Bool = false,
) -> String {
  let input = @utf8.encode(name)
  let output : Array[Byte] = []
  let mut index = 0
  while index < input.length() {
    let code = input[index].to_int()
    if code == '%'.to_int() && index + 2 < input.length() {
      let first = hex_digit(input[index + 1].to_int())
      let second = hex_digit(input[index + 2].to_int())
      match (first, second) {
        (Some(left), Some(right)) => {
          output.push((left * 16 + right).to_byte())
          index += 3
          continue
        }
        _ => ()
      }
    }
    output.push(
      if plus_as_space && code == '+'.to_int() {
        (32).to_byte()
      } else {
        input[index]
      },
    )
    index += 1
  }
  @utf8.decode(Bytes::from_array(output)) catch {
    _ => name
  }
}

///|
/// Remove URL user information before query redaction. The host and path are
/// retained, while both usernames and passwords are replaced together.
fn redact_url_userinfo(url : String) -> String {
  match url.split_once("://") {
    None => url
    Some((scheme, rest)) => {
      let (location, query) = match rest.split_once("?") {
        Some((before, query)) => (before.to_owned(), "?" + query.to_owned())
        None => (rest.to_owned(), "")
      }
      let (authority, path) = match location.split_once("/") {
        Some((host, path)) => (host.to_owned(), "/" + path.to_owned())
        None => (location, "")
      }
      match authority.rev_split_once("@") {
        Some((_, host)) =>
          scheme.to_owned() +
          "://" +
          REDACTION_MARKER +
          "@" +
          host.to_owned() +
          path +
          query
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
  let without_fragment = match url.split_once("#") {
    Some((before, _)) => before.to_owned()
    None => url
  }
  let without_userinfo = redact_url_userinfo(without_fragment)
  match without_userinfo.split_once("?") {
    None => without_userinfo
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
  // JSON Pointer identifies exact object keys. Whitespace in a pointer is
  // data, including in its final token; trimming it could select a neighbor.
  if path.has_prefix("/") {
    let tokens : Array[String] = []
    let tail = path[1:].to_owned()
    for raw in tail.split("/") {
      match decode_pointer_token(raw, path + "") {
        Ok(token) => tokens.push(token)
        Err(error) => return Err(error)
      }
    }
    return Ok(tokens)
  }
  // Only the separate dot shorthand accepts surrounding formatting spaces.
  let trimmed = path.trim().to_owned()
  if trimmed.length() == 0 || trimmed == "$" {
    return Err(InvalidPath(path + ""))
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
  if token.length() == 0 || (token.length() > 1 && token.has_prefix("0")) {
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
priv struct RedactionTarget {
  path : String
  tokens : Array[String]
  required : Bool
}

///|
fn redact_json_text(
  text : String,
  config : RedactionConfig,
) -> Result[String, RedactionError] {
  let original = @json.parse(text) catch {
    _ => return Err(InvalidJson("body is not valid JSON text"))
  }
  let targets : Array[RedactionTarget] = []
  for
    (required, paths) in [
      (true, config.json_paths),
      (false, config.optional_json_paths),
    ] {
    for path in paths {
      let tokens = match parse_redaction_path(path + "") {
        Ok(tokens) => tokens
        Err(error) => return Err(error)
      }
      targets.push({ path: path + "", tokens, required, })
    }
  }
  // A descendant must be processed before an ancestor can replace its whole
  // subtree. The secondary lexical order keeps equal-depth outcomes stable.
  targets.sort_by((left, right) => {
    let depth_order = right.tokens.length().compare(left.tokens.length())
    if depth_order != 0 {
      depth_order
    } else {
      left.path.compare(right.path)
    }
  })
  let present : Array[RedactionTarget] = []
  // Validate every rule against the untouched document. In particular, an
  // ancestor's marker must not hide a missing required or invalid optional
  // descendant. redact_json_at creates copies rather than mutating original.
  for target in targets {
    match redact_json_at(original, target.tokens, 0, target.path) {
      Ok(_) => present.push(target)
      Err(MissingPath(_)) if !target.required => ()
      Err(error) => return Err(error)
    }
  }
  let mut json = original
  for target in present {
    json = match redact_json_at(json, target.tokens, 0, target.path) {
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
  if config.json_paths.is_empty() && config.optional_json_paths.is_empty() {
    return Ok(body)
  }
  // Validate configuration even when the representation cannot contain JSON.
  for path in config.json_paths + config.optional_json_paths {
    match parse_redaction_path(path) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  match body {
    Text(text) =>
      match redact_json_text(text, config) {
        Ok(value) => Ok(Text(value))
        Err(error) => Err(error)
      }
    Empty | Base64(_) => Err(InvalidJson("JSON redaction requires a Text body"))
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
  redact_interaction_with_policy(
    interaction,
    RedactionPolicy::symmetric(config),
  )
}

///|
/// Redact a recorded request and response with independent policies.
pub fn redact_interaction_with_policy(
  interaction : Interaction,
  policy : RedactionPolicy,
) -> Result[Interaction, RedactionError] {
  let { request, response, } = interaction
  match redact_request(request, policy.request) {
    Err(error) => Err(error)
    Ok(safe_request) =>
      match redact_response(response, policy.response) {
        Err(error) => Err(error)
        Ok(safe_response) =>
          Ok({ request: safe_request, response: safe_response, })
      }
  }
}
