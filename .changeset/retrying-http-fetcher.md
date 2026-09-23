---
"@germ-network/germ-convenience": minor
---

Add `RetryingHTTPFetcher`, an `HTTPFetcher` decorator that retries idempotent
(GET/HEAD) requests around 429 rate limiting, transient network errors, and
5xx responses, with bounded exponential backoff and a per-attempt timeout.
Available on iOS 16 / macOS 13 / tvOS 16 / watchOS 9 and newer.
