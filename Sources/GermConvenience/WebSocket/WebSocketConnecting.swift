//
//  WebSocketConnecting.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 9/2/26.
//

import Foundation
import HTTPTypesFoundation

/// The WebSocket counterpart to `HTTPFetcher`/`HTTPStreamFetcher`: `connect`
/// takes a `BundledHTTPRequest` so all three transport seams share one
/// request currency. A WS upgrade is a GET with headers and no body.
public protocol WebSocketConnecting: Sendable {
	func connect(_ request: BundledHTTPRequest) async throws -> any WebSocketConnection
}

/// One open socket. `receive()` is not safe to call concurrently from more
/// than one task — an adapter backed by `URLSessionWebSocketTask` (which
/// forbids concurrent reads) should be an actor to enforce this.
public protocol WebSocketConnection: Sendable {
	func receive() async throws -> WebSocketMessage
	func send(_ data: Data) async throws
	func close() async
}

/// RFC 6455 / OkHttp naming (binary vs text frame), so a germ-owned enum does
/// not privilege one platform's `URLSessionWebSocketTask.Message` vocabulary.
public enum WebSocketMessage: Sendable, Equatable {
	case binary(Data)
	case text(String)
}

/// No germ-owned close-code type: the only consumer needs a no-arg `close()`.
/// A future one must keep semantics within 1000–1999 — Android's corelibs
/// collapses application-range close codes (3000–4999) to 1003 on the wire.
public enum WebSocketConnectError: Error, Sendable {
	/// The server completed the handshake but did not upgrade (non-101).
	case handshakeFailed(status: Int?)
	/// No HTTP response at all — DNS/TLS/refused TCP. Carries the underlying
	/// error rather than discarding it.
	case transportFailed(any Error)
}

// Darwin-gated by architectural choice, not capability: transport mechanism
// stays platform-side (a consumer supplies OkHttp on Android), even though
// corelibs Foundation does implement `URLSessionWebSocketTask`.
#if canImport(Darwin)

	/// A `URLSession`-backed `WebSocketConnecting`.
	///
	/// Two things that silently break a socket if missed, both addressed
	/// here:
	///
	/// 1. `URLSessionWebSocketTask` never hands back the HTTP response on its
	///    own; recovering the handshake status (or the transport error, when
	///    there was never a response at all) takes a delegate.
	/// 2. `receive()` on one task must not be called concurrently — the
	///    returned connection is an `actor`.
	public struct URLSessionWebSocketConnecting: WebSocketConnecting {
		private let session: URLSession

		public init(session: URLSession = .shared) {
			self.session = session
		}

		public func connect(_ request: BundledHTTPRequest) async throws
			-> any WebSocketConnection
		{
			var urlRequest = try URLRequest(httpRequest: request.request).tryUnwrap
			urlRequest.timeoutInterval = 15

			let task = session.webSocketTask(with: urlRequest)
			// The delegate is the only way to recover the handshake outcome —
			// without it `didOpenWithProtocol` is never observed and
			// `waitForOpen` never resumes.
			let handshake = HandshakeDelegate()
			task.delegate = handshake

			try await handshake.waitForOpen(resuming: task)
			return URLSessionWebSocketConnection(task: task)
		}
	}

	/// Bridges `URLSessionWebSocketDelegate`'s `didOpenWithProtocol` (success)
	/// and `URLSessionTaskDelegate`'s `didCompleteWithError` (failure) into
	/// one awaitable outcome.
	///
	/// **`task.resume()` happens inside the continuation closure, after the
	/// continuation is stored — not before.** Calling `resume()` first would
	/// race a delegate callback that fires before `waitForOpen` gets a chance
	/// to register anything to resolve, silently dropping the event and
	/// hanging forever. This ordering is the fix, not a defensive extra.
	private final class HandshakeDelegate: NSObject, URLSessionWebSocketDelegate,
		@unchecked Sendable
	{
		private let lock = NSLock()
		private var continuation: CheckedContinuation<Void, Error>?

		func waitForOpen(resuming task: URLSessionWebSocketTask) async throws {
			try await withCheckedThrowingContinuation { continuation in
				lock.withLock { self.continuation = continuation }
				task.resume()
			}
		}

		/// A signed upgrade always refuses redirects: forwarding the
		/// `Authorization` header (including the live challenge nonce) to
		/// wherever a 3xx points would leak it.
		func urlSession(
			_ session: URLSession, task: URLSessionTask,
			willPerformHTTPRedirection response: HTTPURLResponse,
			newRequest request: URLRequest
		) async -> URLRequest? {
			nil
		}

		func urlSession(
			_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
			didOpenWithProtocol protocol: String?
		) {
			resolve(.success(()))
		}

		func urlSession(
			_ session: URLSession, task: URLSessionTask,
			didCompleteWithError error: Error?
		) {
			// A `nil` error here after a successful open is ordinary task
			// teardown, already resolved by `didOpenWithProtocol` —
			// `resolve`'s own guard makes this a no-op rather than a second
			// (incorrect) resolution.
			guard let error else { return }
			guard let response = task.response as? HTTPURLResponse else {
				// No response at all: DNS/TLS/refused TCP. Carry the error
				// rather than collapsing it to `handshakeFailed(status: nil)`.
				resolve(.failure(WebSocketConnectError.transportFailed(error)))
				return
			}
			resolve(
				.failure(
					WebSocketConnectError.handshakeFailed(
						status: response.statusCode)))
		}

		private func resolve(_ result: Result<Void, Error>) {
			let pending: CheckedContinuation<Void, Error>? = lock.withLock {
				defer { continuation = nil }
				return continuation
			}
			switch result {
			case .success: pending?.resume()
			case .failure(let error): pending?.resume(throwing: error)
			}
		}
	}

	private actor URLSessionWebSocketConnection: WebSocketConnection {
		private let task: URLSessionWebSocketTask

		init(task: URLSessionWebSocketTask) {
			self.task = task
		}

		func receive() async throws -> WebSocketMessage {
			do {
				return try await withTaskCancellationHandler {
					switch try await task.receive() {
					case .data(let data): return .binary(data)
					case .string(let text): return .text(text)
					@unknown default: return .binary(Data())
					}
				} onCancel: {
					// `URLSessionWebSocketTask.receive()` does not observe
					// Swift task cancellation on its own — it's a plain
					// async wrapper over a completion-handler API.
					// Cancelling the underlying task is what actually
					// unblocks the pending `receive()` call below.
					task.cancel(with: .goingAway, reason: nil)
				}
			} catch {
				// `task.cancel()` above resolves the pending receive with a
				// transport-level error (typically `URLError.cancelled`),
				// not Swift's own `CancellationError` — normalized here so a
				// receive loop can tell "this was cancelled" apart from
				// "this was a real failure" regardless of which
				// `WebSocketConnection` is behind it. Only reclassify when
				// the enclosing task actually was cancelled; an unrelated
				// failure that happens to race cancellation still surfaces
				// as itself.
				if Task.isCancelled { throw CancellationError() }
				throw error
			}
		}

		func send(_ data: Data) async throws {
			try await task.send(.data(data))
		}

		func close() async {
			task.cancel(with: .normalClosure, reason: nil)
		}
	}

#endif
