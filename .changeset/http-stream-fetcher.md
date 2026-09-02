---
"@germ-network/germconvenience": minor
---

Add `HTTPStreamFetcher`, a public streaming counterpart to `HTTPFetcher`:
`URLSession.streamingData(for:) -> (response: HTTPResponse, bytes:
AsyncThrowingStream<Data, Error>)`, response known before any body byte, same
contract `URLSession.bytes(for:)` already gives on Apple. Additive — no
signature change to `HTTPFetcher` itself, so an existing conformer that only
implements `data(for:)` is unaffected.

On Apple, delegates to `bytes(for:)` and re-batches into `Data` chunks. On
Linux/Android, where corelibs Foundation has no `bytes(for:)`, a
`URLSessionDataDelegate` recovers the response and body from delegate
callbacks directly, reusing the caller's `URLSessionConfiguration` rather than
a hardcoded default.

Verified: the Apple path is tested against a real `URLSession` conformance
(not a mock) via a `URLProtocol` stub — response delivery, byte-identical
round-trip across multiple chunks, non-2xx delivered rather than thrown, and
empty-body completion. The round-trip test is mutation-verified: corrupting
the byte-accumulation loop makes it fail. The Linux/Android delegate path
compiles (confirmed by forcing that branch to type-check on this machine) but
is not runtime-tested here — needs real Linux/Android CI to prove the
response-then-body delegate ordering holds in practice.
