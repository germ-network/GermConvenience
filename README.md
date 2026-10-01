# GermConvenience

[![Apple](https://github.com/germ-network/GermConvenience/actions/workflows/ci-apple.yml/badge.svg)](https://github.com/germ-network/GermConvenience/actions/workflows/ci-apple.yml)
[![Linux](https://github.com/germ-network/GermConvenience/actions/workflows/ci-linux.yml/badge.svg)](https://github.com/germ-network/GermConvenience/actions/workflows/ci-linux.yml)
[![Android](https://github.com/germ-network/GermConvenience/actions/workflows/ci-android.yml/badge.svg)](https://github.com/germ-network/GermConvenience/actions/workflows/ci-android.yml)

In support of the [AtprotoOauth](https://github.com/germ-network/AtprotoOAuth) family of modular packages,
shared helper implementations:
* an HTTPDataResponse type for the return value of an HTTP fetch
	* functional affordances for checking the success codes and decoding result and error types
	* HTTPFetcher, an abstraction of `URLSession.data(for)` to allow mocking of requests for test
* typed HTTP Method and URL shemes
* tryUnwrap
* String -> utf8 Data
* copy bytes from Contiguous bytes (primarily used to get random bytes for use as an identifier or mock data)

Additional, separately-imported products, each isolating its own extra dependency so the base target stays dependency-free:
* `GermConvenienceURLSession` (swift-http-types' `HTTPTypesFoundation`): the `URLSession` conformers to `HTTPFetcher`/`HTTPStreamFetcher`, `URLSession.manualRedirect()`, `firstLine(request:)` and `URLSessionWebSocketConnecting`. `GermConvenienceHTTP` itself never references `URLSession` or imports FoundationNetworking, so a platform that supplies its own transport depends only on that and never links FoundationNetworking
* `GermConvenienceUtilities` (no extra dependency): `expectOne`/`expectOneOrLess` collection helpers, a short `Data` debug-preview string, and `DeleteFuse`, a guard that fails further work once a delete has begun
* `GermConvenienceCrypto` (swift-crypto): byte/`Data` accessors on `Digest`
* `GermConvenienceLogging` (swift-log): `Logger.logError`, which carries the error structurally rather than flattening it into the message



## Contributing and Collaboration
We welcome contributions!

Please follow our [guidelines for contributing code](./CONTRIBUTING.md)

To give clarity of what is expected of our members, Germ has adopted the
code of conduct defined by the Contributor Covenant. This document is used
across many open source communities, and we think it articulates our values
well. For more, see the [Code of Conduct](./CODE_OF_CONDUCT.md)
