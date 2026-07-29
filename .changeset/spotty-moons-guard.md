---
"@germ-network/germ-convenience": minor
---

Make BundledHTTPRequest's init checks hold, and add Equatable

**Source-breaking — callers that mutate a `BundledHTTPRequest` must migrate.**
`request` and `body` are no longer publicly settable, so the checks in `init`
cannot be undone after construction. Previously a caller could assign a body onto
a `.get`, or flip the method of one that had a body, and reach a state `init`
rejects. Code that assigned header fields in place:

```swift
var output = request
output.request.headerFields[.authorization] = value
```

becomes:

```swift
let output = request.settingHeader(value, for: .authorization)
```

SwiftPM's `from:` is `upToNextMajor`, so `minor` does not gate this for consumers
already on 0.x — oauth4swift is the only one that mutates, and needs its companion
change released in step.

- `init` rejects a url `HTTPRequest` cannot represent (`urn:`, `mailto:`) with the
  new `HTTPRequestError.unrepresentableURL`, rather than building a request whose
  `url` is nil, which could never be sent and compared equal to every other url of
  that shape
- the `missingScheme` path no longer `assert(false)`s before throwing, so it
  surfaces the error in debug builds instead of trapping
- `BundledHTTPRequest` and `HTTPRequestError` are now `Equatable`
