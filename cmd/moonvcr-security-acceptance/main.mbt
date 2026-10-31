///|
fn require(condition : Bool, message : String) -> Unit {
  guard condition else { abort(message) }
}

///|
fn main {
  let encoded_secret = "eyJ0b2tlbiI6InN5bnRoZXRpYy1zZWNyZXQifQ=="
  let bodies : Array[@moonvcr.Body] = [
    @moonvcr.Empty,
    @moonvcr.Base64(encoded_secret),
    @moonvcr.Text("not-json"),
  ]
  let mut rejected = 0
  for optional in [false, true] {
    for response_side in [false, true] {
      let rules = @moonvcr.RedactionConfig::default()
      if optional {
        rules.optional_json_paths.push("/token")
      } else {
        rules.json_paths.push("/token")
      }
      let defaults = @moonvcr.RedactionConfig::default()
      let policy : @moonvcr.RedactionPolicy = if response_side {
        { request: defaults, response: rules, }
      } else {
        { request: rules, response: defaults, }
      }
      for body in bodies {
        let session = @moonvcr.Session::new_with_redaction_policy(
          @moonvcr.example_cassette(),
          @moonvcr.Record,
          @moonvcr.MatchConfig::default(),
          policy,
        )
        let before = session.cassette().encode()
        let request : @moonvcr.Request = {
          method: "POST",
          url: "https://test.invalid",
          headers: [],
          body: if response_side {
            @moonvcr.Empty
          } else {
            body
          },
        }
        let response : @moonvcr.Response = {
          status: 200,
          headers: [],
          body: if response_side {
            body
          } else {
            @moonvcr.Empty
          },
        }
        require(
          session.record_response(request, response) is Err(_),
          "unsafe JSON body was recorded",
        )
        require(
          session.cassette().encode() == before,
          "failed redaction changed cassette",
        )
        require(
          !session.cassette().encode().contains(encoded_secret),
          "Base64 secret persisted",
        )
        rejected += 1
      }
    }
  }
  let plain = ["t", "o", "k", "e", "n"]
  let lower = ["%74", "%6f", "%6b", "%65", "%6e"]
  let upper = ["%54", "%4F", "%4B", "%45", "%4E"]
  for combination in 0..<1024 {
    let mut choices = combination
    let mut name = ""
    for index in 0..<5 {
      name += match choices % 4 {
        0 => plain[index]
        1 => plain[index].to_upper()
        2 => lower[index]
        _ => upper[index]
      }
      choices /= 4
    }
    let session = @moonvcr.Session::with_defaults(
      @moonvcr.Cassette::empty(),
      @moonvcr.Record,
    )
    let request : @moonvcr.Request = {
      method: "GET",
      url: "https://test.invalid/?" + name + "=query-secret#fragment-secret",
      headers: [],
      body: @moonvcr.Empty,
    }
    let response : @moonvcr.Response = {
      status: 200,
      headers: [],
      body: @moonvcr.Empty,
    }
    require(
      session.record_response(request, response) is Ok(_),
      "safe query recording failed",
    )
    let text = session.cassette().encode()
    require(
      !text.contains("query-secret") && !text.contains("fragment-secret"),
      "encoded query or fragment leaked",
    )
  }
  let cassette = @moonvcr.example_cassette()
  let request = cassette.interactions[0].request
  let offline = @moonvcr.Session::with_defaults(
    cassette,
    @moonvcr.StrictOffline,
  )
  let response : @moonvcr.Response = {
    status: 200,
    headers: [],
    body: @moonvcr.Empty,
  }
  require(
    offline.record_response(request, response) is Err(_),
    "offline session recorded a response",
  )
  require(offline.replay(request) is Ok(_), "offline replay failed")
  require(offline.assert_complete() is Ok(_), "offline cassette incomplete")
  let recorder = @moonvcr.Session::with_defaults(
    @moonvcr.Cassette::empty(),
    @moonvcr.Record,
  )
  let transport = (_ : @moonvcr.Request) => {
    Err(@moonvcr.TransportError::Failed("transport-secret"))
  }
  match recorder.send(request, transport) {
    Err(error) =>
      require(
        !@debug.to_string(error).contains("transport-secret"),
        "transport Debug leaked",
      )
    Ok(_) => abort("failing transport unexpectedly succeeded")
  }
  println(
    "security acceptance passed rejected=" +
    rejected.to_string() +
    " encoded_names=1024 retained_secrets=0",
  )
}
