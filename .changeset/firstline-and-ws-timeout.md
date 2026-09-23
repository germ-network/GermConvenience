---
"@germ-network/germ-convenience": minor
---

Fix two issues in `GermConvenienceHTTP`.

Off Apple, `firstLine(request:)` created a `URLSession` per call and never invalidated it, leaking the session and its delegate, and never cancelled the underlying data task once the caller stopped reading — so a caller that only wanted the first line still downloaded the whole body. Now invalidates the session right after creating the task, and cancels the task if the stream is dropped before it finishes on its own.

`URLSessionWebSocketConnecting.connect` hard-coded a 15-second handshake timeout. `init` now takes a defaulted `handshakeTimeout: TimeInterval` (default 15, matching prior behavior) so a caller — most usefully a test — can widen it.
