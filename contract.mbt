///|
/// The response body representation expected by an offline contract.
pub(all) enum ContractBodyKind {
  ExpectEmptyBody
  ExpectTextBody
  ExpectBase64Body
} derive(Eq, @debug.Debug)

///|
/// JSON value kinds supported by field-level response contracts.
pub(all) enum JsonValueKind {
  JsonNull
  JsonBoolean
  JsonNumber
  JsonString
  JsonArray
  JsonObject
} derive(Eq, @debug.Debug)

///|
/// One required JSON field and its expected value kind.
///
/// Paths use the same JSON Pointer or dot shorthand accepted by redaction.
pub(all) struct JsonFieldContract {
  path : String
  expected_kind : JsonValueKind
} derive(Eq, @debug.Debug)

///|
/// A rule for the direct elements of a JSON array field. The array itself is
/// located by `path`; every element must have `expected_kind`.
pub(all) struct JsonArrayElementContract {
  path : String
  expected_kind : JsonValueKind
} derive(Eq, @debug.Debug)

///|
/// One required response header value. The value is used only for an exact
/// comparison; reports expose a length and fingerprint instead of the value.
pub(all) struct HeaderValueContract {
  name : String
  expected_value : String
} derive(Eq, @debug.Debug)

///|
/// A small, transport-independent contract for a recorded or replayed response.
/// Empty arrays mean that the corresponding property is unrestricted.
pub(all) struct ResponseContract {
  allowed_statuses : Array[Int]
  required_headers : Array[String]
  required_header_values : Array[HeaderValueContract]
  body_kind : ContractBodyKind?
  json_fields : Array[JsonFieldContract]
  optional_json_fields : Array[JsonFieldContract]
  json_array_elements : Array[JsonArrayElementContract]
} derive(Eq, @debug.Debug)

///|
/// The category of one response contract violation.
pub(all) enum ContractViolationKind {
  StatusViolation
  MissingHeaderViolation
  HeaderValueViolation
  BodyKindViolation
  InvalidJsonViolation
  InvalidJsonPathViolation
  MissingJsonFieldViolation
  JsonTypeViolation
} derive(Eq, @debug.Debug)

///|
/// A safe response contract difference.
///
/// `expected` and `actual` only contain status or type descriptors. Response
/// header values, JSON values, and body text are never copied into this type.
pub(all) struct ContractViolation {
  kind : ContractViolationKind
  path : String
  expected : String
  actual : String
} derive(Eq, @debug.Debug)

///|
/// Stable contract validation output suitable for CI assertions.
pub(all) struct ContractReport {
  violations : Array[ContractViolation]
} derive(Eq, @debug.Debug)

///|
/// Create a contract that accepts every response.
pub fn ResponseContract::permissive() -> ResponseContract {
  {
    allowed_statuses: [],
    required_headers: [],
    required_header_values: [],
    body_kind: None,
    json_fields: [],
    optional_json_fields: [],
    json_array_elements: [],
  }
}

///|
pub fn ContractBodyKind::label(self : ContractBodyKind) -> String {
  match self {
    ExpectEmptyBody => "empty"
    ExpectTextBody => "text"
    ExpectBase64Body => "base64"
  }
}

///|
pub fn JsonValueKind::label(self : JsonValueKind) -> String {
  match self {
    JsonNull => "null"
    JsonBoolean => "boolean"
    JsonNumber => "number"
    JsonString => "string"
    JsonArray => "array"
    JsonObject => "object"
  }
}

///|
pub fn ContractViolationKind::label(self : ContractViolationKind) -> String {
  match self {
    StatusViolation => "status"
    MissingHeaderViolation => "missing-header"
    HeaderValueViolation => "header-value"
    BodyKindViolation => "body-kind"
    InvalidJsonViolation => "invalid-json"
    InvalidJsonPathViolation => "invalid-json-path"
    MissingJsonFieldViolation => "missing-json-field"
    JsonTypeViolation => "json-type"
  }
}

///|
pub fn ContractReport::is_valid(self : ContractReport) -> Bool {
  self.violations.length() == 0
}

///|
/// Render deterministic, value-safe output for CI and review.
pub fn ContractReport::summary(self : ContractReport) -> String {
  if self.violations.length() == 0 {
    return "contract valid"
  }
  let lines : Array[String] = [
    "contract violations: " + self.violations.length().to_string(),
  ]
  for violation in self.violations {
    lines.push(
      violation.kind.label() +
      " " +
      violation.path +
      ": expected " +
      violation.expected +
      ", actual " +
      violation.actual,
    )
  }
  lines.join("\n")
}

///|
fn response_body_kind(body : Body) -> ContractBodyKind {
  match body {
    Empty => ExpectEmptyBody
    Text(_) => ExpectTextBody
    Base64(_) => ExpectBase64Body
  }
}

///|
fn json_value_kind(value : Json) -> JsonValueKind {
  match value {
    Null => JsonNull
    True | False => JsonBoolean
    Number(_, ..) => JsonNumber
    String(_) => JsonString
    Array(_) => JsonArray
    Object(_) => JsonObject
  }
}

///|
fn status_is_allowed(status : Int, allowed : Array[Int]) -> Bool {
  if allowed.length() == 0 {
    return true
  }
  for candidate in allowed {
    if candidate == status {
      return true
    }
  }
  false
}

///|
fn allowed_statuses_label(statuses : Array[Int]) -> String {
  let parts : Array[String] = []
  for status in statuses {
    parts.push(status.to_string())
  }
  parts.join("|")
}

///|
fn response_has_header(headers : Array[Header], required : String) -> Bool {
  let expected = normalized_header_name(required)
  for header in headers {
    if normalized_header_name(header.name) == expected {
      return true
    }
  }
  false
}

///|
fn response_header_value(headers : Array[Header], required : String) -> String? {
  let expected = normalized_header_name(required)
  for header in headers {
    if normalized_header_name(header.name) == expected {
      return Some(header.value + "")
    }
  }
  None
}

///|
fn safe_header_value(value : String) -> String {
  "<len:" + value.length().to_string() + ",fp:" + safe_fingerprint(value) + ">"
}

///|
fn json_value_at(value : Json, tokens : Array[String]) -> Json? {
  let mut current = value
  for token in tokens {
    current = match current {
      Object(members) =>
        match members.get(token + "") {
          Some(child) => child
          None => return None
        }
      Array(items) =>
        match parse_array_index(token + "") {
          Some(index) =>
            match items.get(index) {
              Some(child) => child
              None => return None
            }
          None => return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
fn add_contract_violation(
  violations : Array[ContractViolation],
  kind : ContractViolationKind,
  path : String,
  expected : String,
  actual : String,
) -> Unit {
  violations.push({ kind, path, expected, actual, })
}

///|
/// Validate a response without performing network or file-system access.
///
/// Violations are emitted in a stable order: status, required headers, header
/// values, body kind, required JSON fields, optional JSON fields, then array
/// element rules in caller-provided order.
pub fn Response::validate_contract(
  self : Response,
  contract : ResponseContract,
) -> ContractReport {
  let violations : Array[ContractViolation] = []
  if !status_is_allowed(self.status, contract.allowed_statuses) {
    add_contract_violation(
      violations,
      StatusViolation,
      "status",
      allowed_statuses_label(contract.allowed_statuses),
      self.status.to_string(),
    )
  }
  for required in contract.required_headers {
    if !response_has_header(self.headers, required) {
      add_contract_violation(
        violations,
        MissingHeaderViolation,
        "header:" + normalized_header_name(required),
        "present",
        "missing",
      )
    }
  }
  for required in contract.required_header_values {
    match response_header_value(self.headers, required.name) {
      None =>
        add_contract_violation(
          violations,
          HeaderValueViolation,
          "header:" + normalized_header_name(required.name),
          safe_header_value(required.expected_value),
          "missing",
        )
      Some(actual) =>
        if normalized_header_value(actual) !=
          normalized_header_value(required.expected_value) {
          add_contract_violation(
            violations,
            HeaderValueViolation,
            "header:" + normalized_header_name(required.name),
            safe_header_value(required.expected_value),
            safe_header_value(actual),
          )
        }
    }
  }
  match contract.body_kind {
    Some(expected) => {
      let actual = response_body_kind(self.body)
      if actual != expected {
        add_contract_violation(
          violations,
          BodyKindViolation,
          "body",
          expected.label(),
          actual.label(),
        )
      }
    }
    None => ()
  }
  if contract.json_fields.length() > 0 ||
    contract.optional_json_fields.length() > 0 ||
    contract.json_array_elements.length() > 0 {
    match self.body {
      Text(text) => {
        let parsed = @json.parse(text) catch {
          _ => {
            add_contract_violation(
              violations,
              InvalidJsonViolation,
              "body",
              "valid JSON text",
              "invalid JSON",
            )
            return { violations, }
          }
        }
        for field in contract.json_fields {
          let tokens = match parse_redaction_path(field.path) {
            Ok(tokens) => tokens
            Err(_) => {
              add_contract_violation(
                violations,
                InvalidJsonPathViolation,
                field.path,
                "valid JSON Pointer or dot path",
                "invalid path",
              )
              continue
            }
          }
          match json_value_at(parsed, tokens) {
            None =>
              add_contract_violation(
                violations,
                MissingJsonFieldViolation,
                field.path,
                field.expected_kind.label(),
                "missing",
              )
            Some(value) => {
              let actual = json_value_kind(value)
              if actual != field.expected_kind {
                add_contract_violation(
                  violations,
                  JsonTypeViolation,
                  field.path,
                  field.expected_kind.label(),
                  actual.label(),
                )
              }
            }
          }
        }
        for field in contract.optional_json_fields {
          let tokens = match parse_redaction_path(field.path) {
            Ok(tokens) => tokens
            Err(_) => {
              add_contract_violation(
                violations,
                InvalidJsonPathViolation,
                field.path,
                "valid JSON Pointer or dot path",
                "invalid path",
              )
              continue
            }
          }
          match json_value_at(parsed, tokens) {
            None => ()
            Some(value) => {
              let actual = json_value_kind(value)
              if actual != field.expected_kind {
                add_contract_violation(
                  violations,
                  JsonTypeViolation,
                  field.path,
                  field.expected_kind.label(),
                  actual.label(),
                )
              }
            }
          }
        }
        for rule in contract.json_array_elements {
          let tokens = match parse_redaction_path(rule.path) {
            Ok(tokens) => tokens
            Err(_) => {
              add_contract_violation(
                violations,
                InvalidJsonPathViolation,
                rule.path,
                "valid JSON Pointer or dot path",
                "invalid path",
              )
              continue
            }
          }
          match json_value_at(parsed, tokens) {
            None =>
              add_contract_violation(
                violations,
                MissingJsonFieldViolation,
                rule.path,
                "array",
                "missing",
              )
            Some(Array(items)) => {
              let mut index = 0
              for item in items {
                let actual = json_value_kind(item)
                if actual != rule.expected_kind {
                  add_contract_violation(
                    violations,
                    JsonTypeViolation,
                    rule.path + "/" + index.to_string(),
                    rule.expected_kind.label(),
                    actual.label(),
                  )
                }
                index += 1
              }
            }
            Some(other) =>
              add_contract_violation(
                violations,
                JsonTypeViolation,
                rule.path,
                "array",
                json_value_kind(other).label(),
              )
          }
        }
      }
      other =>
        add_contract_violation(
          violations,
          InvalidJsonViolation,
          "body",
          "JSON text",
          response_body_kind(other).label(),
        )
    }
  }
  { violations, }
}
