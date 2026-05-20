# @germ-network/germ-convenience

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
