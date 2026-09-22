//
//  LoopbackHTTPServer.swift
//  GermConvenienceTests
//
//  A minimal POSIX-socket HTTP/1.1 server, test-only. Redirect handling on
//  corelibs Foundation lives entirely inside its libcurl-backed URLProtocol,
//  which a URLProtocol stub cannot reach and manualRedirect()'s hard-coded
//  `.default` configuration cannot have one injected into anyway - so
//  ManualRedirectTests needs a real server for the platform's real HTTP
//  stack to talk to.
//

import Crypto
import Dispatch
import Foundation

#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Android)
	import Android
#elseif canImport(Musl)
	import Musl
#endif

/// Serves a fixed table of canned responses over real loopback sockets, and
/// records the request path of every connection it accepts.
final class LoopbackHTTPServer: @unchecked Sendable {
	struct Response: Sendable {
		var status: Int
		var reason: String
		var headers: [String: String]
		var body: Data

		static func ok(body: String) -> Response {
			Response(status: 200, reason: "OK", headers: [:], body: Data(body.utf8))
		}

		static func found(location: String, body: String = "redirecting") -> Response {
			Response(
				status: 302, reason: "Found", headers: ["Location": location],
				body: Data(body.utf8))
		}

		static let notFound = Response(
			status: 404, reason: "Not Found", headers: [:], body: Data())
	}

	/// A route either serves a fixed canned `Response`, or upgrades to a
	/// WebSocket — the latter can't be a canned `Response` since
	/// `Sec-WebSocket-Accept` is computed per-request from the client's key.
	enum RouteHandler: Sendable {
		case response(Response)
		case webSocketUpgrade

		static func ok(body: String) -> RouteHandler { .response(.ok(body: body)) }
		static func found(location: String, body: String = "redirecting") -> RouteHandler {
			.response(.found(location: location, body: body))
		}
		static let notFound = RouteHandler.response(.notFound)
	}

	enum ServerError: Error {
		case socketCreationFailed(Int32)
		case bindFailed(Int32)
		case listenFailed(Int32)
		case getsocknameFailed(Int32)
	}

	private let lock = NSLock()
	private var routes: [String: RouteHandler] = [:]
	private var recordedRequestPaths: [String] = []
	private var listeningSocket: Int32 = -1
	private var acceptLoopShouldStop = false
	private var acceptLoopStarted = false
	private let acceptLoopDidStop = DispatchSemaphore(value: 0)

	private(set) var port: UInt16 = 0

	var recordedPaths: [String] {
		lock.withLock { recordedRequestPaths }
	}

	/// Binds `127.0.0.1:<ephemeral port>` and starts listening, returning the
	/// assigned port. Split from `startAccepting(routes:)` because routes
	/// that redirect back into this same server need the port to build their
	/// `Location` header, and that's only known once bound.
	func bindSocket() throws -> UInt16 {
		#if canImport(Glibc)
			//Glibc's SOCK_STREAM imports as an enum, not a plain Int32
			let streamType = Int32(SOCK_STREAM.rawValue)
		#else
			let streamType = SOCK_STREAM
		#endif

		let fd = socket(AF_INET, streamType, 0)
		guard fd >= 0 else { throw ServerError.socketCreationFailed(errno) }

		var reuse: Int32 = 1
		setsockopt(
			fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

		var addr = sockaddr_in()
		addr.sin_family = sa_family_t(AF_INET)
		addr.sin_port = 0
		//127.0.0.1 in network byte order - built directly rather than via
		//INADDR_LOOPBACK, whose imported type (Int32 vs UInt32) varies by platform
		addr.sin_addr = in_addr(s_addr: UInt32(0x7f00_0001).bigEndian)
		#if canImport(Darwin)
			addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		#endif

		let bindResult = withUnsafePointer(to: &addr) { addrPointer -> Int32 in
			addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				sockaddrPointer in
				bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard bindResult == 0 else {
			let savedErrno = errno
			close(fd)
			throw ServerError.bindFailed(savedErrno)
		}

		guard listen(fd, 16) == 0 else {
			let savedErrno = errno
			close(fd)
			throw ServerError.listenFailed(savedErrno)
		}

		var boundAddr = sockaddr_in()
		var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
		let getsocknameResult = withUnsafeMutablePointer(to: &boundAddr) {
			addrPointer -> Int32 in
			addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				sockaddrPointer in
				getsockname(fd, sockaddrPointer, &boundLen)
			}
		}
		guard getsocknameResult == 0 else {
			let savedErrno = errno
			close(fd)
			throw ServerError.getsocknameFailed(savedErrno)
		}

		listeningSocket = fd
		port = UInt16(bigEndian: boundAddr.sin_port)
		return port
	}

	/// Starts the background accept loop serving `routes`; any other path 404s.
	func startAccepting(routes: [String: RouteHandler]) {
		lock.withLock {
			self.routes = routes
			acceptLoopStarted = true
		}
		let thread = Thread { [self] in
			self.runAcceptLoop()
		}
		thread.name = "LoopbackHTTPServer"
		thread.start()
	}

	/// Stops the accept loop and waits for it to actually exit before closing
	/// the listening socket. On Linux, closing an fd that's blocked inside
	/// `accept` does not wake it - the loop polls with a short timeout
	/// instead, so stopping just has to wait for the next poll to notice.
	/// A no-op past closing the socket if `startAccepting` was never called
	/// - nothing signals `acceptLoopDidStop` in that case.
	func stop() {
		if lock.withLock({ acceptLoopStarted }) {
			lock.withLock { acceptLoopShouldStop = true }
			acceptLoopDidStop.wait()
		}
		if listeningSocket >= 0 {
			close(listeningSocket)
			listeningSocket = -1
		}
	}

	private func runAcceptLoop() {
		while true {
			if lock.withLock({ acceptLoopShouldStop }) { break }

			var pfd = pollfd(fd: listeningSocket, events: Int16(POLLIN), revents: 0)
			let pollResult = poll(&pfd, 1, 100)
			guard pollResult > 0, Int32(pfd.revents) & POLLIN != 0 else { continue }

			let clientSocket = accept(listeningSocket, nil, nil)
			guard clientSocket >= 0 else { continue }
			handle(clientSocket: clientSocket)
		}
		acceptLoopDidStop.signal()
	}

	private func handle(clientSocket: Int32) {
		#if canImport(Darwin)
			var one: Int32 = 1
			setsockopt(
				clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &one,
				socklen_t(MemoryLayout<Int32>.size))
		#endif

		// Bounds a client that never finishes sending its request headers -
		// without this, a blocking read() here would keep the accept thread
		// (and so `stop()`) stuck past the poll-based accept loop entirely.
		var receiveTimeout = timeval()
		receiveTimeout.tv_sec = 5
		setsockopt(
			clientSocket, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout,
			socklen_t(MemoryLayout<timeval>.size))

		guard let requestText = readRequestText(from: clientSocket),
			let path = requestPath(fromRequestText: requestText)
		else {
			close(clientSocket)
			return
		}
		lock.withLock { recordedRequestPaths.append(path) }

		let handler = lock.withLock { routes[path] } ?? .notFound
		switch handler {
		case .webSocketUpgrade:
			handleWebSocketUpgrade(clientSocket: clientSocket, requestText: requestText)
		case .response(let response):
			defer { close(clientSocket) }
			sendAll(clientSocket, encode(response))
		}
	}

	/// Replies `101 Switching Protocols`, sends one unmasked text frame
	/// ("hello"), then holds the TCP connection open until either the peer
	/// sends anything (typically a close frame — corelibs' `close()` only
	/// ever sends one, it never closes the TCP connection itself) or the
	/// server itself is stopping. Connections are handled on the accept
	/// thread, so this has to poll rather than block in a single `read()`,
	/// or `stop()` would deadlock waiting for this to return.
	private func handleWebSocketUpgrade(clientSocket: Int32, requestText: String) {
		defer { close(clientSocket) }

		guard let key = parseHeaders(fromRequestText: requestText)["sec-websocket-key"]
		else {
			sendAll(clientSocket, encode(.notFound))
			return
		}

		var head = "HTTP/1.1 101 Switching Protocols\r\n"
		head += "Upgrade: websocket\r\n"
		head += "Connection: Upgrade\r\n"
		head += "Sec-WebSocket-Accept: \(Self.webSocketAccept(forKey: key))\r\n"
		head += "\r\n"
		sendAll(clientSocket, Array(head.utf8))

		//FIN + text opcode, then the unmasked 7-bit length, then the raw
		//payload - server-to-client frames are never masked (RFC 6455 §5.1)
		let payload = Array("hello".utf8)
		sendAll(clientSocket, [0x81, UInt8(payload.count)] + payload)

		var buffer = [UInt8](repeating: 0, count: 256)
		while true {
			if lock.withLock({ acceptLoopShouldStop }) { return }
			var pfd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)
			guard poll(&pfd, 1, 100) > 0 else { continue }
			let revents = Int32(pfd.revents)
			guard revents & POLLIN != 0 else {
				//a hangup/error with no data pending would otherwise poll
				//as ready forever, busy-spinning this loop
				if revents & (POLLHUP | POLLERR | POLLNVAL) != 0 { return }
				continue
			}
			//either real bytes arrived or the peer closed (read returns 0) -
			//either way this connection is done
			_ = buffer.withUnsafeMutableBytes { raw -> Int in
				read(clientSocket, raw.baseAddress, raw.count)
			}
			return
		}
	}

	private static func webSocketAccept(forKey key: String) -> String {
		let magicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
		let digest = Insecure.SHA1.hash(data: Data((key + magicGUID).utf8))
		return Data(digest).base64EncodedString()
	}

	private func readRequestText(from fd: Int32) -> String? {
		var data = Data()
		let capacity = 64 * 1024
		var buffer = [UInt8](repeating: 0, count: 4096)

		while data.count < capacity {
			let bytesRead = buffer.withUnsafeMutableBytes { raw -> Int in
				read(fd, raw.baseAddress, raw.count)
			}
			guard bytesRead > 0 else { break }
			data.append(contentsOf: buffer[0..<bytesRead])
			if let text = String(data: data, encoding: .utf8), text.contains("\r\n\r\n")
			{
				return text
			}
		}
		return String(data: data, encoding: .utf8)
	}

	private func requestPath(fromRequestText text: String) -> String? {
		guard
			let requestLine = text.split(
				separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false
			).first
		else { return nil }
		let tokens = requestLine.split(separator: " ")
		guard tokens.count >= 2 else { return nil }
		return String(tokens[1])
	}

	private func parseHeaders(fromRequestText text: String) -> [String: String] {
		var headers: [String: String] = [:]
		for line in text.split(separator: "\r\n", omittingEmptySubsequences: false)
			.dropFirst()
		{
			guard let colonIndex = line.firstIndex(of: ":") else { continue }
			let name = line[line.startIndex..<colonIndex]
				.trimmingCharacters(in: .whitespaces)
			let value = line[line.index(after: colonIndex)...]
				.trimmingCharacters(in: .whitespaces)
			headers[name.lowercased()] = value
		}
		return headers
	}

	private func encode(_ response: Response) -> [UInt8] {
		var head = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
		head += "Content-Length: \(response.body.count)\r\n"
		head += "Connection: close\r\n"
		for (name, value) in response.headers {
			head += "\(name): \(value)\r\n"
		}
		head += "\r\n"
		return Array(head.utf8) + Array(response.body)
	}

	private func sendAll(_ fd: Int32, _ bytes: [UInt8]) {
		bytes.withUnsafeBytes { raw in
			var offset = 0
			while offset < raw.count {
				let pointer = raw.baseAddress!.advanced(by: offset)
				let remaining = raw.count - offset
				#if canImport(Darwin)
					let sent = write(fd, pointer, remaining)
				#else
					let sent = send(fd, pointer, remaining, Int32(MSG_NOSIGNAL))
				#endif
				guard sent > 0 else { break }
				offset += sent
			}
		}
	}
}
