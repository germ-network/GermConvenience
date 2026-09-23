---
"@germ-network/germ-convenience": patch
---

Fix `URLSession.streamingData(for:)` (`HTTPStreamFetcher`) never returning on Linux/Android, and dropping the request body on every platform.

Off Apple, `streamingData` relied on the `async` form of `URLSessionDataDelegate`'s response-delivery method, which swift-corelibs-foundation's `FoundationNetworking` never calls — the response side never resolved once any response arrived (a transport failure before any response came back did still surface). Now uses the completion-handler form corelibs actually dispatches, and a 3xx with no usable `Location` (which corelibs never delivers to that callback) is recovered from the completed task instead of hanging. Cancelling a pending `streamingData` call now ends it off Apple too, surfacing as `URLError(.cancelled)`, matching Darwin.

Separately, `request.body` was silently discarded by `streamingData` on every platform, Apple included — now attached as `httpBody`. Consumers that stream a request body through `streamingData(for:)` need this version to actually send it.
