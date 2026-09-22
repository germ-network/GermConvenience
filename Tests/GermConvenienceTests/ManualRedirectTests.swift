//
//  ManualRedirectTests.swift
//  GermConvenienceTests
//
//  Not gated to Darwin: this regression is corelibs-only.
//

import Foundation
import GermConvenienceHTTP
import HTTPTypes
import Testing

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

@Suite("URLSession.manualRedirect()")
struct ManualRedirectTests {
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("refuses to follow a redirect", .timeLimit(.minutes(1)))
	func refusesRedirect() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/redirect": .found(location: "http://127.0.0.1:\(port)/target"),
			"/target": .ok(body: "target"),
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/redirect")!)
		let response = try await URLSession.manualRedirect().data(for: request)

		#expect(response.response.status.code == 302)
		#expect(
			response.response.headerFields[.location]
				== "http://127.0.0.1:\(port)/target")
		//non-vacuity would be lost if /target were ever hit - this is the
		//actual regression check
		#expect(server.recordedPaths == ["/redirect"])
	}

	//pins that the server's redirect is one the platform stack actually
	//follows, so refusesRedirect() above can't be passing vacuously against
	//a server that never redirects at all
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("an ordinary session follows the same redirect", .timeLimit(.minutes(1)))
	func controlFollowsRedirect() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/redirect": .found(location: "http://127.0.0.1:\(port)/target"),
			"/target": .ok(body: "target"),
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/redirect")!)
		let session = URLSession(configuration: .ephemeral)
		let response = try await session.data(for: request)

		#expect(response.response.status.code == 200)
		#expect(response.data == Data("target".utf8))
		#expect(server.recordedPaths.contains("/target"))
	}
}
