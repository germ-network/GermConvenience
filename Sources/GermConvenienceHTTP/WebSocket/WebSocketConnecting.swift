//
//  WebSocketConnecting.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 9/2/26.
//

import Foundation

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
