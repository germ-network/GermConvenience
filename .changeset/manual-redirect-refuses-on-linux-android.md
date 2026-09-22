---
"@germ-network/germ-convenience": patch
---

Fix two Linux/Android-only bugs in `GermConvenienceHTTP`.

`URLSession.manualRedirect()` followed redirects instead of refusing them there — its delegate relied on the `async` form of the redirect method, which swift-corelibs-foundation's `FoundationNetworking` never calls. Now refuses (the returned 3xx has an empty body there; status and headers are unaffected). Darwin was never affected (its importer treats the async and completion-handler forms as the same selector).

`URLSessionWebSocketConnecting.connect` never returned on Linux/Android, on success as much as on failure — corelibs only dispatches WebSocket lifecycle callbacks to a *session* delegate, and `connect` was only ever setting a *task* delegate there. Now completes; a non-101 handshake response fails with `WebSocketConnectError.handshakeFailed(status:)`, and `connect` honours task cancellation instead of hanging past it. Off Apple, the `URLSession` passed to `URLSessionWebSocketConnecting.init` now contributes its configuration only, not its delegate. Darwin behaviour is unchanged except that cancelling now actually ends a pending `connect`.
