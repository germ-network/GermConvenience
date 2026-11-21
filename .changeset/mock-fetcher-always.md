---
"@germ-network/germ-convenience": minor
---

Add `always(_:)` alongside `enqueue(_:)` on `MockHTTPFetcher`'s `on(_:method:)` registrations, which answers every request for a url and method with the same response once any enqueued responses are used up. The most specific registration wins: a request takes its exact method's enqueued responses, then that method's `always`, and only then anything registered for `.any`. `allRequested` ignores `always` responses, since they are never used up.

Both can be combined in one chain, e.g. to answer the first token request with a DPoP nonce challenge and every later one with a token:

```swift
let fetcher = await MockHTTPFetcher()
	// token requests:
	.on(tokenURL, method: .post)
	.enqueue(.success(.status(.badRequest)))
	.on(tokenURL, method: .post)
	.always(.success(.ok(token)))
	// jwks requests
	.on(jwksURL, method: .get)
	.always(.success(.ok(jwks)))
```
