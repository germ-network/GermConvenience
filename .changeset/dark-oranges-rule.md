---
"@germ-network/germ-convenience": patch
---

Add GermConvenienceMocks library

This provides us with a way to assert things for testing HTTPFetcher in oauth4swift.

- FormParameters+Parsing: init(parsing:) extensions for Data, URLComponents, and [URLQueryItem]
- MockHTTPFetcher: method-aware HTTP mock with per-URL handler queues, exact-to-any fallback, and request logging
- HTTPResponseError: Equatable conformance to support error matching in tests
- BundledHTTPRequest: Equatable conformance, so requests can be asserted against
