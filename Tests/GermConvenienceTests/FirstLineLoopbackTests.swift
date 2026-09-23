//
//  FirstLineLoopbackTests.swift
//  GermConvenienceTests
//
//  Off Apple firstLine returns the first received chunk, not a line;
//  assertions hold for both.
//

import Foundation
import GermConvenienceHTTP
import HTTPTypes
import Testing

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

@Suite("URLSession.firstLine(request:) loopback")
struct FirstLineLoopbackTests {
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("returns the text of a small single-line body", .timeLimit(.minutes(1)))
	func singleLineBody() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/line": .ok(body: "hello world")
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/line")!)
		let line = try await URLSession.shared.firstLine(request: request.request)

		#expect(line == "hello world")
	}

	//pins that firstLine doesn't wait for the rest of the body: the route
	//sends a first chunk and then holds the connection open indefinitely
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test(
		"returns promptly against a body that never finishes", .timeLimit(.minutes(1))
	)
	func partialBodyHold() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			//needs a newline for Darwin's .lines to yield a first line at all
			"/slow": .partialBodyHold(
				status: 200, reason: "OK", contentLength: 1_000_000,
				chunk: Data("first line\n".utf8))
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/slow")!)
		let line = try await URLSession.shared.firstLine(request: request.request)

		//Darwin's .lines strips the newline; the off-Apple path hands back
		//the raw chunk (newline included) - assert only the shared prefix
		#expect(line?.hasPrefix("first line") == true)

		//the actual regression check: the abandoned download's connection
		//closes on its own rather than being held open past firstLine's return
		let deadline = Date().addingTimeInterval(30)
		while server.holdsEndedByPeer < 1, Date() < deadline {
			try await Task.sleep(for: .milliseconds(50))
		}
		#expect(server.holdsEndedByPeer == 1)
	}
}
