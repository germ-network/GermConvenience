# @germ-network/germ-convenience

## 0.1.2

### Patch Changes

- [#12](https://github.com/germ-network/GermConvenience/pull/12) [`03f45e6`](https://github.com/germ-network/GermConvenience/commit/03f45e66d776ef1301a49b0b83c52a25dcd7b646) Thanks [@germ-mark](https://github.com/germ-mark)! - Add a FormParameters struct for handling form data

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
