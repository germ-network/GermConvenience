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
		// A canonical CBOR value-model encoder/decoder, kept dependency-free
		// so it can't pull swift-http-types or swift-crypto onto a consumer
		// that only wants CBOR.
		.library(
			name: "GermCBOR",
			targets: ["GermCBOR"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
		.package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
	],
	targets: [
		// Targets are the basic building blocks of a package, defining a module or a test suite.
		// Targets can depend on other targets in this package and products from dependencies.
		.target(
			name: "GermConvenience",
			dependencies: [
				.product(name: "HTTPTypes", package: "swift-http-types"),
				.product(name: "HTTPTypesFoundation", package: "swift-http-types"),
			]
		),
		.target(
			name: "GermConvenienceMocks",
			dependencies: [
				"GermConvenience",
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
		.testTarget(
			name: "GermConvenienceTests",
			dependencies: ["GermConvenience", "GermConvenienceMocks"]
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
	]
)
