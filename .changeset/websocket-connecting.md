---
"@germ-network/germ-convenience": minor
---

Add `WebSocketConnecting`, a WebSocket counterpart to `HTTPFetcher`/`HTTPStreamFetcher`:
`connect(_ request: BundledHTTPRequest) async throws -> any WebSocketConnection`, with
`WebSocketConnection.receive()/send(_:)/close()` and a `WebSocketMessage` enum of
`.binary(Data)`/`.text(String)` — RFC 6455 / OkHttp frame naming, matching the shipped
germ-atproto-pmr-client. Failures split
into `WebSocketConnectError.handshakeFailed(status:)` (server responded, no upgrade) and
`.transportFailed(any Error)` (no response at all — DNS/TLS/refused TCP), carrying the
underlying error rather than discarding it.

Additive; no existing API changes.

A `#if canImport(Darwin)`-gated `URLSessionWebSocketConnecting` conformer ships alongside
the protocol. The gate is architectural, not a capability gap — corelibs Foundation does
support `URLSessionWebSocketTask` — the transport mechanism deliberately stays platform-side
(a consumer supplies OkHttp on Android). The conformer always refuses redirects and sets a
15s handshake timeout.

No mock ships this pass — deferred until a consumer needs one. The Darwin conformer is
compile-verified and exercised only by real usage: `URLProtocol` cannot intercept a
WebSocket upgrade, so its handshake/receive path is not unit-testable with the stub trick
the rest of this package's fetchers use.
