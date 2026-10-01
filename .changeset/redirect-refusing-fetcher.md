---
"@germ-network/germ-convenience": minor
---

Add `RedirectRefusingHTTPFetcher`, an `HTTPFetcher` refinement for fetchers that return a 3xx as the response instead of following it, so a caller that depends on that can require it in its signature. `GermConvenienceURLSession` adds `ManualRedirectFetcher`, a conformer backed by `URLSession.manualRedirect()`, and `MockHTTPFetcher` conforms. `URLSession.manualRedirect()` is unchanged.
