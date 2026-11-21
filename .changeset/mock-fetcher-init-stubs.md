---
"@germ-network/germ-convenience": minor
---

`MockHTTPFetcher.init(_:)` takes initial stubs, built the same way as live registrations with `.on(…).enqueue(…)` / `.always(…)`, so mocks can register default responses without an async context. Registrations made later through `on(…)` queue after them, and a later `always` replaces one given here. `MockHTTPFetcher()` still works and starts empty.

```swift
let fetcher = MockHTTPFetcher([
	.on(metadataURL, method: .get).always(.success(.ok(metadata))),
	.on(parURL, method: .post).enqueue(.success(.ok(parBody))),
])
```
