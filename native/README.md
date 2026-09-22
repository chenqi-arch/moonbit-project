# Native adapters

The root package is deliberately transport-agnostic and can be checked and
tested on MoonBit's portable targets. This directory adds the opt-in native
boundary for applications that need a real file or HTTP system:

- `archive.mbt` persists versioned JSON cassettes with a byte limit, synced
  temporary writes, and an explicit no-overwrite or replace operation;
- `http_transport.mbt` maps MoonVCR requests to MoonBit's official
  `moonbitlang/async` HTTP client, including text and Base64 request/response
  bodies;
- `record_http` performs one real request and feeds the response back through
  the core `Session::record_response` API.

The adapter does not install a proxy or intercept processes automatically.
Callers explicitly provide the request and decide when recording may access a
real network. Replay and strict-offline sessions remain core-only and do not
call this adapter.

## Verification

```text
moon check --target native
moon test --target native
moon run --target native cmd/moonvcr-native-demo
moon run --target native cmd/moonvcr-native-record
moon run --target native cmd/moonvcr-native-replay
```

The demos print `native archive roundtrip interactions=1`, then
`native record saved interactions=1` and `native replay offline status=200`.
The last two commands are intentionally separate processes and share only the
JSON file, so they cover the persistence boundary rather than an in-memory
round trip. The repository CI runs these native checks on Ubuntu. On Windows,
the MoonBit native target also needs a working C toolchain; the portable core
checks remain available without that compiler.
