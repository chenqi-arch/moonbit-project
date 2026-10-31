///|
fn audit_paths_record(
  text : String,
  required : Array[String],
  optional : Array[String],
  response_side : Bool,
) -> Result[Cassette, SessionError] {
  let rules = RedactionConfig::default()
  for path in required {
    rules.json_paths.push(path)
  }
  for path in optional {
    rules.optional_json_paths.push(path)
  }
  let defaults = RedactionConfig::default()
  let policy : RedactionPolicy = if response_side {
    { request: defaults, response: rules, }
  } else {
    { request: rules, response: defaults, }
  }
  let session = Session::new_with_redaction_policy(
    Cassette::empty(),
    Record,
    MatchConfig::default(),
    policy,
  )
  let request : Request = {
    method: "POST",
    url: "https://audit.test/",
    headers: [],
    body: if response_side {
      Empty
    } else {
      Text(text)
    },
  }
  let response : Response = {
    status: 200,
    headers: [],
    body: if response_side {
      Text(text)
    } else {
      Empty
    },
  }
  match session.record_response(request, response) {
    Ok(_) => Ok(session.cassette())
    Err(error) => {
      guard session.cassette().interactions.length() == 0 else {
        abort("failed path validation appended an interaction")
      }
      Err(error)
    }
  }
}

///|
fn audit_paths_encoded(
  text : String,
  required : Array[String],
  optional : Array[String],
  response_side : Bool,
) -> String {
  match audit_paths_record(text, required, optional, response_side) {
    Ok(cassette) => cassette.encode()
    Err(error) => abort(error.summary())
  }
}

///|
test "audit paths F1 whitespace pointer selects exact neighboring key on both sides" {
  for response_side in [false, true] {
    for optional in [false, true] {
      for
        (path, text) in [
          (
            "/token ", "{\"token \":\"audit-space-secret\",\"token\":\"public-visible\"}",
          ),
          (
            "/token\t", "{\"token\\t\":\"audit-tab-secret\",\"token\":\"public-visible\"}",
          ),
          (
            "/token\n", "{\"token\\n\":\"audit-newline-secret\",\"token\":\"public-visible\"}",
          ),
        ] {
        let encoded = audit_paths_encoded(
          text,
          if optional {
            []
          } else {
            [path]
          },
          if optional {
            [path]
          } else {
            []
          },
          response_side,
        )
        assert_true(!encoded.contains("audit-space-secret"))
        assert_true(!encoded.contains("audit-tab-secret"))
        assert_true(!encoded.contains("audit-newline-secret"))
        assert_true(encoded.contains("public-visible"))
        assert_true(encoded.contains(REDACTION_MARKER))
      }
    }
  }
}

///|
test "audit paths F1 optional whitespace key without trimmed neighbor is not skipped" {
  for response_side in [false, true] {
    for
      (path, text) in [
        ("/token ", "{\"token \":\"audit-space-secret\"}"),
        ("/token\t", "{\"token\\t\":\"audit-tab-secret\"}"),
        ("/token\n", "{\"token\\n\":\"audit-newline-secret\"}"),
      ] {
      let encoded = audit_paths_encoded(text, [], [path], response_side)
      assert_true(!encoded.contains("audit-space-secret"))
      assert_true(!encoded.contains("audit-tab-secret"))
      assert_true(!encoded.contains("audit-newline-secret"))
      assert_true(encoded.contains(REDACTION_MARKER))
    }
  }
}

///|
test "audit paths F1 empty and all whitespace object keys remain distinct" {
  let text = "{\"\":\"empty-secret\",\" \":\"space-secret\",\"\\t\":\"tab-secret\",\"\\n\":\"newline-secret\",\"visible\":\"public-visible\"}"
  let paths = ["/", "/ ", "/\t", "/\n"]
  for response_side in [false, true] {
    for optional in [false, true] {
      let encoded = audit_paths_encoded(
        text,
        if optional {
          []
        } else {
          paths
        },
        if optional {
          paths
        } else {
          []
        },
        response_side,
      )
      for
        secret in [
          "empty-secret", "space-secret", "tab-secret", "newline-secret",
        ] {
        assert_true(!encoded.contains(secret))
      }
      assert_true(encoded.contains("public-visible"))
    }
  }
}

///|
test "audit paths F1 nested array pointer preserves leaf whitespace and siblings" {
  let text = "{\"items\":[{\"token \":\"public-zero\"},{\"token \":\"nested-secret\",\"token\":\"public-one\"}]}"
  for response_side in [false, true] {
    for optional in [false, true] {
      let encoded = audit_paths_encoded(
        text,
        if optional {
          []
        } else {
          ["/items/1/token "]
        },
        if optional {
          ["/items/1/token "]
        } else {
          []
        },
        response_side,
      )
      assert_true(!encoded.contains("nested-secret"))
      assert_true(encoded.contains("public-zero"))
      assert_true(encoded.contains("public-one"))
    }
  }
}

///|
test "audit paths F1 absent whitespace key never falls back to trimmed neighbor" {
  for response_side in [false, true] {
    for path in ["/token ", "/token\t", "/token\n"] {
      let text = "{\"token\":\"public-visible\"}"
      assert_true(
        audit_paths_record(text, [path], [], response_side)
        is Err(RedactionFailed(MissingPath(_))),
      )
      let encoded = audit_paths_encoded(text, [], [path], response_side)
      assert_true(encoded.contains("public-visible"))
      assert_true(!encoded.contains(REDACTION_MARKER))
    }
  }
}

///|
test "audit paths F1 Unicode and escaped pointer tokens preserve whitespace" {
  for response_side in [false, true] {
    for optional in [false, true] {
      for
        (path, text) in [
          (
            "/🔑 ", "{\"🔑 \":\"unicode-secret\",\"🔑\":\"public-visible\"}",
          ),
          ("/a~1b ", "{\"a/b \":\"unicode-secret\",\"a/b\":\"public-visible\"}"),
          (
            "/a~0b\t", "{\"a~b\\t\":\"unicode-secret\",\"a~b\":\"public-visible\"}",
          ),
        ] {
        let encoded = audit_paths_encoded(
          text,
          if optional {
            []
          } else {
            [path]
          },
          if optional {
            [path]
          } else {
            []
          },
          response_side,
        )
        assert_true(!encoded.contains("unicode-secret"))
        assert_true(encoded.contains("public-visible"))
      }
    }
  }
}

///|
test "audit paths F1 pointer is not enabled by trimming leading whitespace" {
  for path in [" /token", "\t/token", "\n/token"] {
    assert_true(
      audit_paths_record("{\"token\":\"secret\"}", [path], [], false)
      is Err(RedactionFailed(InvalidPath(_))),
    )
    assert_true(
      audit_paths_record("{\"token\":\"secret\"}", [], [path], true)
      is Err(RedactionFailed(InvalidPath(_))),
    )
  }
  let encoded = audit_paths_encoded(
    "{\"credentials\":{\"token\":\"shorthand-secret\"}}",
    ["  credentials.token  "],
    [],
    false,
  )
  assert_true(!encoded.contains("shorthand-secret"))
}

///|
test "audit paths F6 arrays reject noncanonical indexes for required and optional paths" {
  let text = "{\"items\":[{\"token\":\"first\"},{\"token\":\"second\"}]}"
  for response_side in [false, true] {
    for optional in [false, true] {
      for index in ["00", "01", "001", "-1", "+1", "1.0", "-", "2147483648"] {
        let path = "/items/" + index + "/token"
        assert_true(
          audit_paths_record(
            text,
            if optional {
              []
            } else {
              [path]
            },
            if optional {
              [path]
            } else {
              []
            },
            response_side,
          )
          is Err(RedactionFailed(InvalidPath(_))),
        )
      }
    }
  }
}

///|
test "audit paths F6 object zero names and canonical array zero remain valid" {
  for response_side in [false, true] {
    for optional in [false, true] {
      for
        (path, text) in [
          (
            "/01/token", "{\"01\":{\"token\":\"object-secret\"},\"1\":\"public-visible\"}",
          ),
          (
            "/items/0/01/token", "{\"items\":[{\"01\":{\"token\":\"object-secret\"},\"visible\":\"public-visible\"}]}",
          ),
          (
            "/items/0/token", "{\"items\":[{\"token\":\"object-secret\",\"visible\":\"public-visible\"}]}",
          ),
        ] {
        let encoded = audit_paths_encoded(
          text,
          if optional {
            []
          } else {
            [path]
          },
          if optional {
            [path]
          } else {
            []
          },
          response_side,
        )
        assert_true(!encoded.contains("object-secret"))
        assert_true(encoded.contains("public-visible"))
      }
    }
  }
}

///|
test "audit paths F7 all required overlap permutations succeed with identical output" {
  let text = "{\"credentials\":{\"token\":\"parent-secret\",\"items\":[{\"token\":\"child-secret\"}]},\"visible\":\"public-visible\"}"
  let rules = [
    "/credentials", "/credentials/token", "/credentials/items/0/token",
  ]
  for response_side in [false, true] {
    let expected = audit_paths_encoded(text, rules, [], response_side)
    for
      order in [
        [0, 1, 2],
        [0, 2, 1],
        [1, 0, 2],
        [1, 2, 0],
        [2, 0, 1],
        [2, 1, 0],
      ] {
      let paths = order.map(index => rules[index])
      let encoded = audit_paths_encoded(text, paths, [], response_side)
      assert_eq(encoded, expected)
      assert_true(!encoded.contains("parent-secret"))
      assert_true(!encoded.contains("child-secret"))
      assert_true(encoded.contains("public-visible"))
    }
  }
}

///|
test "audit paths F7 overlapping optional and mixed paths have stable coverage" {
  let text = "{\"credentials\":{\"token\":\"overlap-secret\"},\"visible\":\"public-visible\"}"
  for response_side in [false, true] {
    let expected = audit_paths_encoded(
      text,
      ["/credentials"],
      [],
      response_side,
    )
    for
      (required, optional) in [
        ([], ["/credentials", "/credentials/token"]),
        ([], ["/credentials/token", "/credentials"]),
        (["/credentials"], ["/credentials/token"]),
        (["/credentials/token"], ["/credentials"]),
        (["credentials.token", "/credentials/token", "/credentials"], []),
      ] {
      let encoded = audit_paths_encoded(text, required, optional, response_side)
      assert_eq(encoded, expected)
      assert_true(!encoded.contains("overlap-secret"))
    }
  }
}

///|
test "audit paths F7 required descendants must exist in original JSON for all orders" {
  let text = "{\"credentials\":{\"token\":\"present-secret\"}}"
  for response_side in [false, true] {
    let first = audit_paths_record(
      text,
      ["/credentials", "/credentials/missing"],
      [],
      response_side,
    )
    let second = audit_paths_record(
      text,
      ["/credentials/missing", "/credentials"],
      [],
      response_side,
    )
    assert_eq(first, second)
    assert_true(
      first is Err(RedactionFailed(MissingPath("/credentials/missing"))),
    )
  }
}

///|
test "audit paths F7 ancestor cannot hide invalid optional array path" {
  let text = "{\"credentials\":{\"items\":[{\"token\":\"first\"},{\"token\":\"second\"}]}}"
  for response_side in [false, true] {
    assert_true(
      audit_paths_record(
        text,
        ["/credentials"],
        ["/credentials/items/01/token"],
        response_side,
      )
      is Err(RedactionFailed(InvalidPath(_))),
    )
  }
}

///|
test "audit paths contract exact whitespace fields reject target types and ignore neighbors" {
  for optional in [false, true] {
    for
      (path, invalid, valid) in [
        (
          "/id ", "{\"id \":\"wrong-type\",\"id\":123}", "{\"id \":123,\"id\":\"wrong-neighbor\"}",
        ),
        (
          "/id\t", "{\"id\\t\":\"wrong-type\",\"id\":123}", "{\"id\\t\":123,\"id\":\"wrong-neighbor\"}",
        ),
        (
          "/id\n", "{\"id\\n\":\"wrong-type\",\"id\":123}", "{\"id\\n\":123,\"id\":\"wrong-neighbor\"}",
        ),
      ] {
      let contract = ResponseContract::permissive()
      let rule : JsonFieldContract = { path, expected_kind: JsonNumber, }
      if optional {
        contract.optional_json_fields.push(rule)
      } else {
        contract.json_fields.push(rule)
      }
      let invalid_response : Response = {
        status: 200,
        headers: [],
        body: Text(invalid),
      }
      let invalid_report = invalid_response.validate_contract(contract)
      assert_eq(invalid_report.violations.length(), 1)
      assert_eq(invalid_report.violations[0].kind, JsonTypeViolation)
      assert_eq(invalid_report.violations[0].path, path)
      let valid_response : Response = {
        status: 200,
        headers: [],
        body: Text(valid),
      }
      assert_true(valid_response.validate_contract(contract).is_valid())
    }
  }
}

///|
test "audit paths contract absent whitespace optional field does not select neighbor" {
  let response : Response = {
    status: 200,
    headers: [],
    body: Text("{\"id\":\"wrong-neighbor\"}"),
  }
  for path in ["/id ", "/id\t", "/id\n"] {
    let optional = ResponseContract::permissive()
    optional.optional_json_fields.push({ path, expected_kind: JsonNumber, })
    assert_true(response.validate_contract(optional).is_valid())
    let required = ResponseContract::permissive()
    required.json_fields.push({ path, expected_kind: JsonNumber, })
    let report = response.validate_contract(required)
    assert_eq(report.violations.length(), 1)
    assert_eq(report.violations[0].kind, MissingJsonFieldViolation)
  }
}

///|
test "audit paths contract exact empty Unicode and escaped keys remain readable" {
  let response : Response = {
    status: 200,
    headers: [],
    body: Text(
      "{\"\":1,\" \":2,\"\\t\":3,\"🔑 \":4,\"a/b \":5,\"a~b\\n\":6,\"object\":{\"01\":7}}",
    ),
  }
  for optional in [false, true] {
    let contract = ResponseContract::permissive()
    for path in ["/", "/ ", "/\t", "/🔑 ", "/a~1b ", "/a~0b\n", "/object/01"] {
      let rule : JsonFieldContract = { path, expected_kind: JsonNumber, }
      if optional {
        contract.optional_json_fields.push(rule)
      } else {
        contract.json_fields.push(rule)
      }
    }
    assert_true(response.validate_contract(contract).is_valid())
  }
}

///|
test "audit paths contract array element rules locate exact whitespace key" {
  for
    (path, invalid, valid) in [
      (
        "/items ", "{\"items \":[false],\"items\":[{}]}", "{\"items \":[{}],\"items\":[false]}",
      ),
      (
        "/items\t", "{\"items\\t\":[false],\"items\":[{}]}", "{\"items\\t\":[{}],\"items\":[false]}",
      ),
      (
        "/items\n", "{\"items\\n\":[false],\"items\":[{}]}", "{\"items\\n\":[{}],\"items\":[false]}",
      ),
    ] {
    let contract = ResponseContract::permissive()
    contract.json_array_elements.push({ path, expected_kind: JsonObject, })
    let invalid_response : Response = {
      status: 200,
      headers: [],
      body: Text(invalid),
    }
    let report = invalid_response.validate_contract(contract)
    assert_eq(report.violations.length(), 1)
    assert_eq(report.violations[0].kind, JsonTypeViolation)
    let valid_response : Response = {
      status: 200,
      headers: [],
      body: Text(valid),
    }
    assert_true(valid_response.validate_contract(contract).is_valid())
  }
}

///|
test "audit paths contract invalid indexes fail in required optional and array rules" {
  let response : Response = {
    status: 200,
    headers: [],
    body: Text("{\"items\":[[1],[2]],\"object\":{\"01\":[3]}}"),
  }
  for index in ["00", "01", "001", "-1", "+1", "1.0", "-", "2147483648"] {
    let path = "/items/" + index
    for category in 0..<3 {
      let contract = ResponseContract::permissive()
      if category == 0 {
        contract.json_fields.push({ path, expected_kind: JsonArray, })
      } else if category == 1 {
        contract.optional_json_fields.push({ path, expected_kind: JsonArray, })
      } else {
        contract.json_array_elements.push({ path, expected_kind: JsonNumber, })
      }
      let report = response.validate_contract(contract)
      assert_eq(report.violations.length(), 1)
      assert_eq(report.violations[0].kind, InvalidJsonPathViolation)
    }
  }
  let valid = ResponseContract::permissive()
  valid.json_array_elements.push({
    path: "/items/0",
    expected_kind: JsonNumber,
  })
  valid.json_array_elements.push({
    path: "/object/01",
    expected_kind: JsonNumber,
  })
  valid.optional_json_fields.push({
    path: "/absent/01",
    expected_kind: JsonArray,
  })
  assert_true(response.validate_contract(valid).is_valid())
}

///|
test "audit paths duplicate rules preserve required validation on original JSON" {
  let text = "{\"\":{\"token\":\"empty-parent-secret\"},\"credentials\":{\"token\":\"duplicate-secret\"}}"
  for response_side in [false, true] {
    let encoded = audit_paths_encoded(
      text,
      [
        "/credentials/token", "credentials.token", "/credentials", "/", "//token",
        "/credentials",
      ],
      ["/credentials/token", "//token", "/", "/credentials/missing"],
      response_side,
    )
    assert_true(!encoded.contains("empty-parent-secret"))
    assert_true(!encoded.contains("duplicate-secret"))
    for
      (required, optional) in [
        (["/credentials", "/credentials/missing"], ["/credentials/missing"]),
        (["/credentials/missing", "/credentials"], ["/credentials/missing"]),
      ] {
      assert_true(
        audit_paths_record(text, required, optional, response_side)
        is Err(RedactionFailed(MissingPath("/credentials/missing"))),
      )
    }
  }
}
