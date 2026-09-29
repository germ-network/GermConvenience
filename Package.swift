// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "GermConvenience",
	platforms: [.iOS(.v15), .macOS(.v12)],
	products: [
		// Products define the executables and libraries a package produces, making them visible to other packages.
		.library(
			name: "GermConvenience",
			targets: ["GermConvenience"]
		),
		// The HTTPTypes/URLSession helpers, split out so the base GermConvenience
		// (tryUnwrap, form encoding, etc.) carries no swift-http-types dependency.
		.library(
			name: "GermConvenienceHTTP",
			targets: ["GermConvenienceHTTP"]
		),
		.library(
			name: "GermConvenienceMocks",
			targets: ["GermConvenienceMocks"]
		),
		// The RFC 9421 request signer is its own product so swift-crypto stays
		// off the base GermConvenience target — only a consumer that imports
		// GermHTTPSignature links it.
		.library(
			name: "GermHTTPSignature",
			targets: ["GermHTTPSignature"]
		),
		// A canonical CBOR value-model encoder/decoder for the COSE (RFC 9052)
		// profile — kept dependency-free so it can't pull swift-http-types or
		// swift-crypto onto a consumer that only wants COSE CBOR.
		.library(
			name: "GermCBOR",
			targets: ["GermCBOR"]
		),
		// Foundation-only helpers (typed JSON decode errors, `expectOne`, a
		// delete-in-progress guard). Their own product rather than part of the
		// base target, so upgrading GermConvenience alone never introduces these
		// names into a module that didn't ask for them — a consumer opts in by
		// importing GermConvenienceUtilities. (An intermediate library that
		// itself publicly imports this product can still leak these extension
		// members to ITS importers, absent MemberImportVisibility — a caveat
		// for consumers of this package, not for this package itself.)
		.library(
			name: "GermConvenienceUtilities",
			targets: ["GermConvenienceUtilities"]
		),
		// swift-crypto `Digest` byte accessors — split out, like GermHTTPSignature,
		// so swift-crypto stays off every target that doesn't need it.
		.library(
			name: "GermConvenienceCrypto",
			targets: ["GermConvenienceCrypto"]
		),
		// `Logger.logError` — its own product so swift-log is linked only by a
		// consumer that imports GermConvenienceLogging.
		.library(
			name: "GermConvenienceLogging",
			targets: ["GermConvenienceLogging"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
		.package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0"),
		// 1.12.0 is the first release whose log methods take `error:`, which
		// logError forwards; 1.11.0 added LogEvent.
		.package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
	],
	targets: [
		// Targets are the basic building blocks of a package, defining a module or a test suite.
		// Targets can depend on other targets in this package and products from dependencies.
		.target(
			name: "GermConvenience"
		),
		.target(
			name: "GermConvenienceHTTP",
			dependencies: [
				"GermConvenience",
				.product(name: "HTTPTypes", package: "swift-http-types"),
				.product(name: "HTTPTypesFoundation", package: "swift-http-types"),
			]
		),
		.target(
			name: "GermConvenienceMocks",
			dependencies: [
				"GermConvenience",
				"GermConvenienceHTTP",
				.product(name: "HTTPTypes", package: "swift-http-types"),
			]),
		.target(
			name: "GermHTTPSignature",
			dependencies: [
				.product(name: "Crypto", package: "swift-crypto")
			]
		),
		.target(
			name: "GermCBOR"
		),
		.target(
			name: "GermConvenienceUtilities"
		),
		.target(
			name: "GermConvenienceCrypto",
			dependencies: [
				.product(name: "Crypto", package: "swift-crypto")
			]
		),
		.target(
			name: "GermConvenienceLogging",
			dependencies: [
				.product(name: "Logging", package: "swift-log")
			]
		),
		.testTarget(
			name: "GermConvenienceTests",
			dependencies: [
				"GermConvenience", "GermConvenienceMocks", "GermConvenienceHTTP",
				.product(name: "Crypto", package: "swift-crypto"),
			]
		),
		.testTarget(
			name: "GermHTTPSignatureTests",
			dependencies: [
				"GermHTTPSignature",
				.product(name: "Crypto", package: "swift-crypto"),
			]
		),
		.testTarget(
			name: "GermCBORTests",
			dependencies: ["GermCBOR"]
		),
		.testTarget(
			name: "GermConvenienceUtilitiesTests",
			dependencies: ["GermConvenienceUtilities"]
		),
		.testTarget(
			name: "GermConvenienceCryptoTests",
			dependencies: [
				"GermConvenienceCrypto",
				.product(name: "Crypto", package: "swift-crypto"),
			]
		),
		.testTarget(
			name: "GermConvenienceLoggingTests",
			dependencies: [
				"GermConvenienceLogging",
				.product(name: "Logging", package: "swift-log"),
			]
		),
	]
)
