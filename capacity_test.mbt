///|
fn capacity_cassette(count : Int) -> Cassette {
  let interactions : Array[Interaction] = []
  for index in 0..<count {
    interactions.push({
      request: {
        method: "GET",
        url: "https://capacity.example.test/items?id=" + index.to_string(),
        headers: [{ name: "Accept", value: "application/json", }],
        body: Empty,
      },
      response: {
        status: 200,
        headers: [{ name: "Content-Type", value: "application/json", }],
        body: Text("{\"ok\":true}"),
      },
    })
  }
  { format_version: CURRENT_FORMAT_VERSION, interactions, }
}

///|
fn verify_capacity(count : Int) -> Unit raise {
  let encoded = capacity_cassette(count).encode()
  let decoded = Cassette::decode(encoded)
  assert_eq(decoded.interactions.length(), count)
  let session = Session::with_defaults(decoded, StrictOffline)
  let request : Request = {
    method: "GET",
    url: "https://capacity.example.test/items?id=" + (count - 1).to_string(),
    headers: [{ name: "Accept", value: "application/json", }],
    body: Empty,
  }
  match session.replay(request) {
    Ok(response) => assert_eq(response.status, 200)
    Err(_) => assert_true(false)
  }
  assert_eq(session.remaining_interactions(), count - 1)
}

///|
test "capacity: 100 interactions encode decode and replay" {
  verify_capacity(100)
}

///|
test "capacity: 1000 interactions encode decode and replay" {
  verify_capacity(1_000)
}

///|
test "capacity: 10000 interactions encode decode and replay" {
  verify_capacity(10_000)
}
