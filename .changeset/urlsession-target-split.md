---
"@germ-network/germ-convenience": minor
---

Split URLSession conformers into their own target so non-Apple platforms can depend on the fetcher-based API.

`GermConvenienceHTTP` now holds only the portable API (`HTTPFetcher`, `HTTPStreamFetcher`, `WebSocketConnecting` and its connection/message/error types, `BundledHTTPRequest`, `HTTPDataResponse`, `HTTPResponseError`, `RetryingHTTPFetcher`). It no longer depends on `HTTPTypesFoundation` and nothing in it imports FoundationNetworking, so depending on it alone never links `libFoundationNetworking` on Android.

Breaking: the following moved to a new `GermConvenienceURLSession` product, and a consumer that used any of them must add that product to its target dependencies and `import GermConvenienceURLSession`:

- `URLSession: HTTPFetcher` and `URLSession: HTTPStreamFetcher`
- `URLSession.manualRedirect()`
- `URLSession.firstLine(request:)`
- `URLSessionWebSocketConnecting`

Their signatures are unchanged.

Breaking: the minimum `swift-http-types` is now `1.5.0` (was `1.0.0`), the first release with `HTTPRequest.url` and `HTTPRequest(method:url:headerFields:)` in core `HTTPTypes` rather than `HTTPTypesFoundation`.
