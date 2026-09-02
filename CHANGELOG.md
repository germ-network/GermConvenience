# @germ-network/germ-convenience

## 0.5.0

### Minor Changes

- [#44](https://github.com/germ-network/GermConvenience/pull/44) [`724a6de`](https://github.com/germ-network/GermConvenience/commit/724a6def4d4f7366851cc230268ea3f3dc28d4e9) Thanks [@germ-mark](https://github.com/germ-mark)! - Add `WebSocketConnecting`, a WebSocket counterpart to `HTTPFetcher`/`HTTPStreamFetcher`:
  `connect(_ request: BundledHTTPRequest) async throws -> any WebSocketConnection`, with
  `WebSocketConnection.receive()/send(_:)/close()` and a `WebSocketMessage` enum of
  `.binary(Data)`/`.text(String)` — RFC 6455 / OkHttp frame naming, matching the shipped
  germ-atproto-pmr-client. Failures split
  into `WebSocketConnectError.handshakeFailed(status:)` (server responded, no upgrade) and
  `.transportFailed(any Error)` (no response at all — DNS/TLS/refused TCP), carrying the
  underlying error rather than discarding it.

  Additive; no existing API changes.

  A `#if canImport(Darwin)`-gated `URLSessionWebSocketConnecting` conformer ships alongside
  the protocol. The gate is architectural, not a capability gap — corelibs Foundation does
  support `URLSessionWebSocketTask` — the transport mechanism deliberately stays platform-side
  (a consumer supplies OkHttp on Android). The conformer always refuses redirects and sets a
  15s handshake timeout.

  No mock ships this pass — deferred until a consumer needs one. The Darwin conformer is
  compile-verified and exercised only by real usage: `URLProtocol` cannot intercept a
  WebSocket upgrade, so its handshake/receive path is not unit-testable with the stub trick
  the rest of this package's fetchers use.

## 0.4.0

### Minor Changes

- [#41](https://github.com/germ-network/GermConvenience/pull/41) [`f9d424c`](https://github.com/germ-network/GermConvenience/commit/f9d424c1e5484f9cf7279f46bf32763ee80befc6) Thanks [@germ-mark](https://github.com/germ-mark)! - Add `HTTPStreamFetcher`, a public streaming counterpart to `HTTPFetcher`:
  `URLSession.streamingData(for:) -> (response: HTTPResponse, bytes:
AsyncThrowingStream<Data, Error>)`, response known before any body byte, same
  contract `URLSession.bytes(for:)` already gives on Apple. Additive — no
  signature change to `HTTPFetcher` itself, so an existing conformer that only
  implements `data(for:)` is unaffected.

  On Apple, delegates to `bytes(for:)` and re-batches into `Data` chunks. On
  Linux/Android, where corelibs Foundation has no `bytes(for:)`, a
  `URLSessionDataDelegate` recovers the response and body from delegate
  callbacks directly, reusing the caller's `URLSessionConfiguration` rather than
  a hardcoded default.

  Verified: the Apple path is tested against a real `URLSession` conformance
  (not a mock) via a `URLProtocol` stub — response delivery, byte-identical
  round-trip across multiple chunks, non-2xx delivered rather than thrown, and
  empty-body completion. The round-trip test is mutation-verified: corrupting
  the byte-accumulation loop makes it fail. The Linux/Android delegate path
  compiles (confirmed by forcing that branch to type-check on this machine) but
  is not runtime-tested here — needs real Linux/Android CI to prove the
  response-then-body delegate ordering holds in practice.

## 0.3.0

### Minor Changes

- [#38](https://github.com/germ-network/GermConvenience/pull/38) [`83f028d`](https://github.com/germ-network/GermConvenience/commit/83f028dd6a9e86146839734b916448c054ffc33c) Thanks [@germ-mark](https://github.com/germ-mark)! - Make BundledHTTPRequest's init checks hold, and add Equatable

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

### Patch Changes

- [#32](https://github.com/germ-network/GermConvenience/pull/32) [`edbedaf`](https://github.com/germ-network/GermConvenience/commit/edbedaf33518588dd835a5c4b807e69087022546) Thanks [@ThisIsMissEm](https://github.com/ThisIsMissEm)! - Add GermConvenienceMocks library

  This provides us with a way to assert things for testing HTTPFetcher in oauth4swift.

  - FormParameters+Parsing: init(parsing:) extensions for Data, URLComponents, and [URLQueryItem]
  - MockHTTPFetcher: method-aware HTTP mock with per-URL handler queues, exact-to-any fallback, and request logging
  - HTTPResponseError: Equatable conformance to support error matching in tests

  `BundledHTTPRequest`'s Equatable conformance moved to the type itself in [#38](https://github.com/germ-network/GermConvenience/issues/38), so the
  copy this branch carried in GermConvenienceMocks is gone - it would otherwise have
  been a duplicate that silently shadowed the owner's.

- [#32](https://github.com/germ-network/GermConvenience/pull/32) [`46c6bce`](https://github.com/germ-network/GermConvenience/commit/46c6bcef3d0b85b55041bb90656ac330420a1350) Thanks [@ThisIsMissEm](https://github.com/ThisIsMissEm)! - Correctly throw on head requests sent with a body

- [#35](https://github.com/germ-network/GermConvenience/pull/35) [`cf1ca2d`](https://github.com/germ-network/GermConvenience/commit/cf1ca2d4a665a97f85615a453f3dc17a5a5b9e04) Thanks [@germ-mark](https://github.com/germ-mark)! - Add `ErrorResult.get(mapError:)` and `HTTPDataResponse.expectSuccess(orError:mapError:)`

  - `get(mapError:)` returns the decoded result or throws a mapped error, replacing the
    switch callers were hand-rolling
  - `expectSuccess(orError:mapError:)` for endpoints such as token revocation that return
    no success body. Lifted from oauth4swift

- [#34](https://github.com/germ-network/GermConvenience/pull/34) [`2ac42e1`](https://github.com/germ-network/GermConvenience/commit/2ac42e1a4d6084960d19d151f2b1a4edda523996) Thanks [@germ-mark](https://github.com/germ-mark)! - Fix `HTTPDataResponse.success` error handling

  `success(decodeResult:orError:)` and `success(code:decodeResult:orError:)` wrapped
  the status check and the result decode in one `do`, so a successful response whose
  body failed to decode was retried as an error body — returning a bogus `.error` for a
  2xx, or masking the real `DecodingError` with one about the error type. The status now
  selects the branch and decode failures propagate.

  A failure response whose body does not decode as the error type now throws
  `HTTPResponseError.unsuccessful`, preserving the status code and raw bytes, instead of
  a bare `DecodingError`.

  Every failure path in this module now reports `HTTPResponseError.unsuccessful`.
  `expectSuccess()` previously reported `.unsuccessfulString` whenever the body happened
  to be UTF-8, so the two differed for the same response, and an empty body arrived as
  `.unsuccessfulString(code, "")`. `.unsuccessfulString` remains in the enum for existing
  callers but is no longer thrown from here; read the body through the new `bodyString`
  accessor, which works on either case. `code` is also new.

## 0.2.4

### Patch Changes

- [#30](https://github.com/germ-network/GermConvenience/pull/30) [`bcb848f`](https://github.com/germ-network/GermConvenience/commit/bcb848f4f253fc3892583bb475e8386bffae71bd) Thanks [@germ-mark](https://github.com/germ-mark)! - enable successful android build

## 0.2.3

### Patch Changes

- [#28](https://github.com/germ-network/GermConvenience/pull/28) [`015721c`](https://github.com/germ-network/GermConvenience/commit/015721c745ae9622dd9085f52df398f4181c917e) Thanks [@germ-mark](https://github.com/germ-mark)! - restore firstline

## 0.2.2

### Patch Changes

- [#26](https://github.com/germ-network/GermConvenience/pull/26) [`7a1ccd4`](https://github.com/germ-network/GermConvenience/commit/7a1ccd47229e2c1f52f2f2a5c461157766c818d6) Thanks [@germ-mark](https://github.com/germ-mark)! - restore deleted urlscheme

## 0.2.1

### Patch Changes

- [#24](https://github.com/germ-network/GermConvenience/pull/24) [`770cc01`](https://github.com/germ-network/GermConvenience/commit/770cc01a876783dcb98551d02243696f6ab342eb) Thanks [@germ-mark](https://github.com/germ-mark)! - fix merge issue with renamed folder

## 0.2.0

### Minor Changes

- [#22](https://github.com/germ-network/GermConvenience/pull/22) [`0df31ef`](https://github.com/germ-network/GermConvenience/commit/0df31ef2f548e06eb0abb5e652ae49380b5679fb) Thanks [@germ-mark](https://github.com/germ-mark)! - consolidate on a single BundledHTTPRequest initializer that protects against a runtime crash

### Patch Changes

- [#22](https://github.com/germ-network/GermConvenience/pull/22) [`8e9ce21`](https://github.com/germ-network/GermConvenience/commit/8e9ce216aadb82b336cfcde655d3bab37a453398) Thanks [@germ-mark](https://github.com/germ-mark)! - remove base64url, recommend importing swift-libp2p/swift-bases instead

## 0.1.5

### Patch Changes

- [#20](https://github.com/germ-network/GermConvenience/pull/20) [`ed5fcf6`](https://github.com/germ-network/GermConvenience/commit/ed5fcf6b256d1184f8f8a4451ac6070570786eed) Thanks [@germ-mark](https://github.com/germ-mark)! - workaround linker issue with a firstline method

## 0.1.4

### Patch Changes

- [#17](https://github.com/germ-network/GermConvenience/pull/17) [`9410f02`](https://github.com/germ-network/GermConvenience/commit/9410f02441c5028818c2ae02600d3ffde379a3dd) Thanks [@germ-mark](https://github.com/germ-mark)! - public base64URLEncodedBytes method

## 0.1.3

### Patch Changes

- [#14](https://github.com/germ-network/GermConvenience/pull/14) [`e7c4b3f`](https://github.com/germ-network/GermConvenience/commit/e7c4b3f8ef1ef5ffc61dcb658abdfd175d08e721) Thanks [@ThisIsMissEm](https://github.com/ThisIsMissEm)! - Move LazyResource from OAuth4Swift to GermConvenience

## 0.1.2

### Patch Changes

- [#12](https://github.com/germ-network/GermConvenience/pull/12) [`03f45e6`](https://github.com/germ-network/GermConvenience/commit/03f45e66d776ef1301a49b0b83c52a25dcd7b646) Thanks [@ThisIsMissEm](https://github.com/ThisIsMissEm)! - Add a FormParameters struct for handling form data

- [#8](https://github.com/germ-network/GermConvenience/pull/8) [`bf741d4`](https://github.com/germ-network/GermConvenience/commit/bf741d4f57d28b90fb76b6ccecd0b112e02a9f91) Thanks [@nnabeyang](https://github.com/nnabeyang)! - Improve HTTPDataResponse debug visibility for better error diagnosis

## 0.1.1

### Patch Changes

- [#4](https://github.com/germ-network/GermConvenience/pull/4) [`50e0ccf`](https://github.com/germ-network/GermConvenience/commit/50e0ccf42f7fd9315b76acdb6882770f797f3f85) Thanks [@germ-mark](https://github.com/germ-mark)! - add content types for any and none

## 0.1.0

### Minor Changes

- [#1](https://github.com/germ-network/GermConvenience/pull/1) [`3d2e37d`](https://github.com/germ-network/GermConvenience/commit/3d2e37d1d4968104a8c6263f88a10079a1b9c465) Thanks [@germ-mark](https://github.com/germ-mark)! - Adopt swift-http-types

  - Changes our signature of `HTTPFetcher` from `data(for: URLRequest) async throws -> HTTPDataResponse` to ` data(for: BundledHTTPRequest) async throws -> HTTPDataResponse`
    - `BundledHTTPRequest` bundles swift-http-types HTTPRequest with an optional HTTP body.
  - Adds HTTPContentType defined values
