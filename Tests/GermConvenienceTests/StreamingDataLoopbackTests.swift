//
//  StreamingDataLoopbackTests.swift
//  GermConvenienceTests
//
//  Not gated to Darwin: the regression this guards against (streamingData
//  never returning) is corelibs-only, so it needs to run everywhere that
//  delegate path does.
//

import Foundation
import GermConvenienceHTTP
import HTTPTypes
import Testing

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

@Suite("URLSession: streamingData(for:) loopback")
struct StreamingDataLoopbackTests {
	private static func session() -> URLSession {
		URLSession(configuration: .ephemeral)
	}

	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test(
		"the response is delivered, and the body reassembles byte-identical",
		.timeLimit(.minutes(1))
	)
	func responseAndBodyRoundTrip() async throws {
		let body = Data((0..<200_000).map { UInt8($0 % 256) })
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/stream": .response(
				.init(status: 200, reason: "OK", headers: [:], body: body))
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/stream")!)
		let (response, stream) = try await Self.session().streamingData(for: request)
		#expect(response.status.code == 200)

		var reassembled = Data()
		for try await chunk in stream {
			reassembled.append(chunk)
		}
		#expect(reassembled == body)
	}

	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test(
		"a non-2xx status is delivered, not thrown — the caller decides",
		.timeLimit(.minutes(1)))
	func nonSuccessStatusIsNotThrown() async throws {
		let body = Data("not found".utf8)
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/missing": .response(
				.init(status: 404, reason: "Not Found", headers: [:], body: body))
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/missing")!)
		let (response, stream) = try await Self.session().streamingData(for: request)
		#expect(response.status.code == 404)

		var reassembled = Data()
		for try await chunk in stream {
			reassembled.append(chunk)
		}
		#expect(reassembled == body)
	}

	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test(
		"an empty body still finishes the stream, not just the response",
		.timeLimit(.minutes(1)))
	func emptyBodyFinishesCleanly() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/empty": .response(
				.init(status: 204, reason: "No Content", headers: [:], body: Data())
			)
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/empty")!)
		let (response, stream) = try await Self.session().streamingData(for: request)
		#expect(response.status.code == 204)

		var sawAnyChunk = false
		for try await _ in stream { sawAnyChunk = true }
		#expect(!sawAnyChunk)
	}

	//corelibs never calls `didReceive response` for a 3xx with no Location -
	//it only completes with a nil error, leaving the `didCompleteWithError`
	//fallback as the only thing that resolves this at all
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("a redirect with no Location is still delivered", .timeLimit(.minutes(1)))
	func redirectWithNoLocationIsDelivered() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/redirect": .response(
				.init(status: 302, reason: "Found", headers: [:], body: Data()))
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/redirect")!)
		let (response, stream) = try await Self.session().streamingData(for: request)
		#expect(response.status.code == 302)

		for try await _ in stream {}
	}

	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("a closed port throws", .timeLimit(.minutes(1)))
	func closedPortThrows() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.stop()

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/anything")!)
		await #expect(throws: URLError.self) {
			_ = try await Self.session().streamingData(for: request)
		}
	}

	//the request-body drop: both platforms silently sent an empty body
	//regardless of what the caller passed
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("a POST body reaches the server exactly, byte for byte", .timeLimit(.minutes(1)))
	func postBodyIsSent() async throws {
		let body = Data([0x00, 0xFF, 0x80, 0x01, 0xFE, 0x10, 0x20, 0x30])
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/upload": .ok(body: "ok")
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			method: .post, url: URL(string: "http://127.0.0.1:\(port)/upload")!,
			body: body)
		let (response, stream) = try await Self.session().streamingData(for: request)
		#expect(response.status.code == 200)
		for try await _ in stream {}

		let recorded = server.recordedRequests
		#expect(recorded.count == 1)
		#expect(recorded.first?.method == "POST")
		#expect(recorded.first?.body == body)
	}

	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("cancellation ends a pending response wait", .timeLimit(.minutes(1)))
	func cancellationEndsThePendingWait() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/never")!)
		let child = Task {
			try await Self.session().streamingData(for: request)
		}
		try await Task.sleep(for: .milliseconds(300))
		child.cancel()

		do {
			_ = try await child.value
			Issue.record("expected URLError(.cancelled)")
		} catch let error as URLError where error.code == .cancelled {
			// expected
		} catch {
			Issue.record("expected URLError(.cancelled), got \(error)")
		}
	}

	//exercises `waitForResponse`'s `alreadyCancelled` branch: cancellation
	//that arrives before the task is ever resumed
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("a cancel before the request starts still throws", .timeLimit(.minutes(1)))
	func cancelBeforeStartThrows() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/immediate": .ok(body: "ok")
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/immediate")!)
		let child = Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return try await Self.session().streamingData(for: request)
		}

		do {
			_ = try await child.value
			Issue.record("expected URLError(.cancelled)")
		} catch let error as URLError where error.code == .cancelled {
			// expected
		} catch {
			Issue.record("expected URLError(.cancelled), got \(error)")
		}
	}

	//callers check the status before committing to the body, so the
	//response must resolve while the body is still arriving
	@available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
	@Test("the response resolves before the body finishes", .timeLimit(.minutes(1)))
	func responseResolvesBeforeBodyFinishes() async throws {
		let server = LoopbackHTTPServer()
		let port = try server.bindSocket()
		server.startAccepting(routes: [
			"/slow": .partialBodyHold(
				status: 200, reason: "OK", contentLength: 1_000_000,
				chunk: Data("partial".utf8))
		])
		defer { server.stop() }

		let request = try BundledHTTPRequest(
			url: URL(string: "http://127.0.0.1:\(port)/slow")!)
		//not read from: the Darwin branch buffers up to 64 KB before
		//yielding a chunk, and this body never reaches that
		let (response, _) = try await Self.session().streamingData(for: request)
		#expect(response.status.code == 200)
	}
}
