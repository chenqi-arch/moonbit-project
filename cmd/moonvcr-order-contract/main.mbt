///|
fn contract() -> @moonvcr.ResponseContract {
  {
    allowed_statuses: [200, 201],
    required_headers: ["content-type", "x-api-version"],
    required_header_values: [
      { name: "content-type", expected_value: "application/json", },
      { name: "x-api-version", expected_value: "2026-09", },
    ],
    body_kind: Some(@moonvcr.ExpectTextBody),
    json_fields: [
      { path: "/id", expected_kind: @moonvcr.JsonNumber, },
      { path: "/state", expected_kind: @moonvcr.JsonString, },
    ],
    optional_json_fields: [
      { path: "/note", expected_kind: @moonvcr.JsonString, },
    ],
    json_array_elements: [
      { path: "/items", expected_kind: @moonvcr.JsonObject, },
    ],
  }
}

///|
fn main {
  let response : @moonvcr.Response = {
    status: 201,
    headers: [
      { name: "Content-Type", value: "application/json", },
      { name: "X-Api-Version", value: "2026-09", },
    ],
    body: @moonvcr.Text(
      "{\"id\":42,\"state\":\"created\",\"items\":[{\"sku\":\"demo\"}]}",
    ),
  }
  let report = response.validate_contract(contract())
  guard report.is_valid() else { abort(report.summary()) }
  println(
    "order compatibility contract passed status headers JSON array optional-field",
  )
}
