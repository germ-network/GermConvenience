//
//  WebSocketConnectingTests.swift
//  GermConvenienceTests
//
//  Off Apple, `URLSession` only calls a *session* delegate for WebSocket
//  lifecycle callbacks - a task-scoped delegate never observes them.
//

import Foundation
import GermConvenienceHTTP
import Testing

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

@Suite("URLSessionWebSocketConnecting")
struct WebSocketConnectingTests {
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("connects, receives a frame, and closes", .timeLimit(.minutes(1)))
	func connects() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/ws-connect": .webSocketUpgrade
		])
		defer { server.stop() }

		let connecting = URLSessionWebSocketConnecting(
			session: URLSession(configuration: .ephemeral), handshakeTimeout: 60)
		let request = try BundledHTTPRequest(
			url: URL(string: "ws://127.0.0.1:\(port)/ws-connect")!)

		//the positive control: proves the hang fix on corelibs, and that
		//the failure tests below aren't just "connect always fails"
		let connection = try await connecting.connect(request)
		#expect(try await connection.receive() == .text("hello"))
		await connection.close()
	}

	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("refuses to follow a redirect on the handshake", .timeLimit(.minutes(1)))
	func refusesHandshakeRedirect() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/ws-redirect": .found(location: "ws://127.0.0.1:\(port)/target", body: "")
		])
		defer { server.stop() }

		let connecting = URLSessionWebSocketConnecting(
			session: URLSession(configuration: .ephemeral), handshakeTimeout: 60)
		let request = try BundledHTTPRequest(
			url: URL(string: "ws://127.0.0.1:\(port)/ws-redirect")!)

		//on Darwin our redirect delegate refuses the 3xx; on corelibs
		//libcurl itself refuses any non-101 WebSocket upgrade before the
		//delegate is consulted - either way, not followed. Only "throws,
		//not the hang-fix's own cancellation" is asserted, since the
		//failure shape otherwise differs by platform.
		do {
			_ = try await connecting.connect(request)
			Issue.record("expected connect to throw")
		} catch is CancellationError {
			Issue.record("connect was cancelled rather than failing on its own")
		} catch {
			// expected: the handshake never upgrades
		}

		//non-vacuity: the handshake really reached the server
		#expect(server.recordedPaths.contains("/ws-redirect"))
		//the actual regression check
		#expect(!server.recordedPaths.contains("/target"))
	}

	//on Darwin a 404 arrives via didCompleteWithError - this only pins
	//the didOpenWithProtocol status check off Apple (verified on Android)
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("a non-101 response fails fast with its status", .timeLimit(.minutes(1)))
	func non101FailsFast() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [:])
		defer { server.stop() }

		let connecting = URLSessionWebSocketConnecting(
			session: URLSession(configuration: .ephemeral), handshakeTimeout: 60)
		let request = try BundledHTTPRequest(
			url: URL(string: "ws://127.0.0.1:\(port)/missing")!)

		do {
			_ = try await connecting.connect(request)
			Issue.record("expected connect to throw")
		} catch WebSocketConnectError.handshakeFailed(let status) {
			#expect(status == 404)
		} catch {
			Issue.record("expected .handshakeFailed(status: 404), got \(error)")
		}
	}

	//the server binds and listens but never accepts, so `connect` would
	//otherwise hang until its handshake timeout - this pins that cancelling
	//the caller ends it without waiting for that timeout at all
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("connect honors cancellation", .timeLimit(.minutes(1)))
	func connectHonorsCancellation() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		defer { server.stop() }

		let connecting = URLSessionWebSocketConnecting(
			session: URLSession(configuration: .ephemeral), handshakeTimeout: 60)
		let request = try BundledHTTPRequest(
			url: URL(string: "ws://127.0.0.1:\(port)/never")!)

		let child = Task { try await connecting.connect(request) }
		try await Task.sleep(for: .milliseconds(300))
		child.cancel()

		do {
			_ = try await child.value
			Issue.record("expected CancellationError")
		} catch is CancellationError {
			// expected
		} catch {
			Issue.record("expected CancellationError, got \(error)")
		}
	}
}
