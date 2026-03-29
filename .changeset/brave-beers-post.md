---
"@germ-network/germ-convenience": minor
---

Adopt swift-http-types

* Changes our signature of `HTTPFetcher`  from `data(for: URLRequest) async throws -> HTTPDataResponse` to ` data(for: BundledHTTPRequest) async throws -> HTTPDataResponse`
	* `BundledHTTPRequest` bundles swift-http-types HTTPRequest with an optional HTTP body.
* Adds HTTPContentType defined values