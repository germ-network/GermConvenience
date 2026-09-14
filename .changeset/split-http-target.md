---
"@germ-network/germ-convenience": minor
---

Split the HTTPTypes/URLSession helpers into a new `GermConvenienceHTTP` product so the base `GermConvenience` (`tryUnwrap`, form encoding, `HTTPContentType`, etc.) carries no swift-http-types dependency. BREAKING for consumers of the HTTP fetchers / WebSocket helpers: add the `GermConvenienceHTTP` product and `import GermConvenienceHTTP` (base-convenience consumers are unaffected).
