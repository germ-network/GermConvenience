---
"@germ-network/germ-convenience": minor
---

Un-gate `URLSessionWebSocketConnecting` / `URLSessionWebSocketConnection` off Apple. corelibs Foundation's `FoundationNetworking` implements `URLSessionWebSocketTask` and `URLSessionWebSocketDelegate`, so the URLSession-backed conformer now compiles on Linux and Android instead of being Darwin-only. The `WebSocketConnecting` seam is unchanged: a consumer that prefers its own transport (e.g. OkHttp on Android) still supplies its own conformer.
