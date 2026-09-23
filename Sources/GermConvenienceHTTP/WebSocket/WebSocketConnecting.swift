//
//  WebSocketConnecting.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 9/2/26.
//

import Foundation
import GermConvenience
import HTTPTypesFoundation

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

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

// Not Darwin-gated: corelibs Foundation's FoundationNetworking implements
// `URLSessionWebSocketTask` and `URLSessionWebSocketDelegate`, so the
// URLSession-backed conformer compiles on Linux and Android too. Transport
// mechanism still stays the consumer's choice — a consumer preferring OkHttp
// on Android supplies its own `WebSocketConnecting` through the same seam.

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
///
/// A third, corelibs-only distinction: off Apple, `URLSession` only routes
/// WebSocket lifecycle callbacks (open/close/complete) to its *session*
/// delegate — a task-level delegate is never consulted there, so `connect`
/// builds its own per-connection delegate session off Apple. The injected
/// `session` contributes its configuration only in that case, not its
/// delegate.
public struct URLSessionWebSocketConnecting: WebSocketConnecting {
	private let session: URLSession
	private let handshakeTimeout: TimeInterval

	/// `handshakeTimeout` sets the upgrade request's `timeoutInterval`.
	public init(session: URLSession = .shared, handshakeTimeout: TimeInterval = 15) {
		self.session = session
		self.handshakeTimeout = handshakeTimeout
	}

	public func connect(_ request: BundledHTTPRequest) async throws
		-> any WebSocketConnection
	{
		try Task.checkCancellation()

		var urlRequest = try URLRequest(httpRequest: request.request).tryUnwrap
		urlRequest.timeoutInterval = handshakeTimeout

		let handshake = HandshakeDelegate()
		let task = try await handshake.waitForOpen {
			#if canImport(FoundationNetworking)
				let connectingSession = URLSession(
					configuration: session.configuration, delegate: handshake,
					delegateQueue: nil)
				let task = connectingSession.webSocketTask(with: urlRequest)
				// Not deferred to close()/deinit: invalidateAndCancel()
				// would send close code 0 on corelibs.
				connectingSession.finishTasksAndInvalidate()
				return task
			#else
				let task = session.webSocketTask(with: urlRequest)
				task.delegate = handshake
				return task
			#endif
		}
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
	/// Guards against `onCancel` racing the continuation being stored.
	private var cancelled = false
	private var task: URLSessionWebSocketTask?

	/// `makeTask` runs only once cancellation is ruled out under `lock`, so a
	/// cancelled caller never creates a task that's then never resumed.
	func waitForOpen(makeTask: () -> URLSessionWebSocketTask) async throws
		-> URLSessionWebSocketTask
	{
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				let task: URLSessionWebSocketTask? = lock.withLock {
					guard !cancelled else { return nil }
					let task = makeTask()
					self.task = task
					self.continuation = continuation
					return task
				}
				guard let task else {
					continuation.resume(throwing: CancellationError())
					return
				}
				task.resume()
			}
		} onCancel: {
			let pending: CheckedContinuation<Void, Error>? = lock.withLock {
				cancelled = true
				defer { continuation = nil }
				return continuation
			}
			// A handshake that already resolved keeps its connection. On
			// corelibs this cancel doesn't stop an in-flight transfer: it
			// runs to the handshake timeout, or gets a close frame if a 101 arrives.
			guard let pending else { return }
			pending.resume(throwing: CancellationError())
			lock.withLock { task }?.cancel(with: .goingAway, reason: nil)
		}
		return lock.withLock { task }!
	}

	/// A signed upgrade always refuses redirects: forwarding the
	/// `Authorization` header (including the live challenge nonce) to
	/// wherever a 3xx points would leak it.
	///
	/// The completion-handler form: the only one corelibs dispatches, and
	/// the same selector as `async` on Darwin. In practice only reached on
	/// Darwin — libcurl refuses a non-101 WebSocket upgrade before any
	/// redirect handling runs.
	func urlSession(
		_ session: URLSession, task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping @Sendable (URLRequest?) -> Void
	) {
		completionHandler(nil)
	}

	/// On corelibs a non-101 handshake response still reaches this callback
	/// (Darwin fails the task before ever calling it) — the status has to
	/// be checked here rather than assumed successful. No `task.cancel()`
	/// on the failure path: libcurl has already failed the transfer by the
	/// time this fires there.
	func urlSession(
		_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
		didOpenWithProtocol protocol: String?
	) {
		if let response = webSocketTask.response as? HTTPURLResponse,
			response.statusCode != 101
		{
			resolve(
				.failure(
					WebSocketConnectError.handshakeFailed(
						status: response.statusCode)))
			return
		}
		resolve(.success(()))
	}

	/// Required off Apple: Darwin's `URLSessionWebSocketDelegate` is an
	/// `@objc` protocol whose methods are all optional, so leaving this out
	/// still conforms there — corelibs' is a plain Swift protocol, so the
	/// witness is mandatory. Only reachable before the handshake resolves
	/// (a close frame implies something opened, and a successful open has
	/// already resolved); `resolve`'s guard makes it a no-op otherwise.
	func urlSession(
		_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
		didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
		reason: Data?
	) {
		resolve(.failure(WebSocketConnectError.handshakeFailed(status: nil)))
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
