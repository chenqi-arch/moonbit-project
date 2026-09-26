///|
fn main {
  let response : @moonvcr.Response = {
    status: 201,
    headers: [
      { name: "Content-Type", value: "text/plain", },
      { name: "X-Api-Version", value: "2026-08", },
    ],
    body: @moonvcr.Text(
      "{\"id\":\"42\",\"state\":\"created\",\"items\":[\"wrong\"]}",
    ),
  }
  let contract : @moonvcr.ResponseContract = {
    allowed_statuses: [201],
    required_headers: ["content-type", "x-api-version"],
    required_header_values: [
      { name: "content-type", expected_value: "application/json", },
      { name: "x-api-version", expected_value: "2026-09", },
    ],
    body_kind: Some(@moonvcr.ExpectTextBody),
    json_fields: [{ path: "/id", expected_kind: @moonvcr.JsonNumber, }],
    optional_json_fields: [],
    json_array_elements: [
      { path: "/items", expected_kind: @moonvcr.JsonObject, },
    ],
  }
  let report = response.validate_contract(contract)
  guard !report.is_valid() else {
    abort("order failure scenario unexpectedly passed")
  }
  abort(report.summary())
}
