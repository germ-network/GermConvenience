//
//  HTTPStreamFetcher.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 9/2/26.
//

import Foundation
import HTTPTypes
import HTTPTypesFoundation

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

///Additive to `HTTPFetcher`, not a signature change to it — a conformer that
///only implements `data(for:)` is unaffected. Split into its own protocol
///because a streamed response cannot share `HTTPFetcher`'s single-return-value
///shape: the whole point is inspecting the status before the caller commits to
///reading (or, on Apple, even allocating) the body — the same "status known
///before any byte" contract `URLSession.bytes(for:)` already gives on Apple.
public protocol HTTPStreamFetcher: Sendable {
	func streamingData(for request: BundledHTTPRequest) async throws -> (
		response: HTTPResponse, bytes: AsyncThrowingStream<Data, Error>
	)
}

extension URLSession: HTTPStreamFetcher {
	#if canImport(Darwin)
		public func streamingData(
			for request: BundledHTTPRequest
		) async throws -> (response: HTTPResponse, bytes: AsyncThrowingStream<Data, Error>)
		{
			let (byteStream, response) = try await self.bytes(for: request.request)
			let stream = AsyncThrowingStream<Data, Error> { continuation in
				let task = Task {
					do {
						var buffer = Data()
						buffer.reserveCapacity(Self.streamChunkSize)
						for try await byte in byteStream {
							buffer.append(byte)
							if buffer.count >= Self.streamChunkSize {
								continuation.yield(buffer)
								buffer.removeAll(
									keepingCapacity: true)
							}
						}
						if !buffer.isEmpty {
							continuation.yield(buffer)
						}
						continuation.finish()
					} catch {
						continuation.finish(throwing: error)
					}
				}
				continuation.onTermination = { _ in task.cancel() }
			}
			return (response, stream)
		}
	#else
		public func streamingData(
			for request: BundledHTTPRequest
		) async throws -> (response: HTTPResponse, bytes: AsyncThrowingStream<Data, Error>)
		{
			guard let urlRequest = URLRequest(httpRequest: request.request) else {
				throw HTTPRequestError.missingScheme
			}
			//Reuses self's configuration rather than .default, so a caller's
			//timeout/cache/protocol-class customization (including a test's
			//injected URLProtocol) applies here exactly as it would to any
			//other method called on this same URLSession instance.
			return try await StreamingResponseDelegate.streamingData(
				from: urlRequest, configuration: self.configuration)
		}
	#endif

	fileprivate static let streamChunkSize = 64 * 1024
}

#if !canImport(Darwin)
	///Linux/Android only: corelibs Foundation has no `bytes(for:)`
	///(https://forums.swift.org/t/asyncbytes-and-asynclinesequence-not-available-on-linux/73601),
	///so the response and the body have to be recovered from the delegate
	///callbacks by hand, in the order they actually arrive — headers, then
	///zero or more body chunks, then completion.
	final class StreamingResponseDelegate: NSObject, URLSessionTaskDelegate,
		URLSessionDataDelegate,
		@unchecked Sendable
	{
		//`didReceive response` and `didCompleteWithError` can each resolve the
		//response side exactly once (the latter only if the task fails before
		//headers ever arrive) — the lock is what makes "exactly once" true
		//across two delegate callbacks that are not otherwise ordered against
		//each other.
		private let lock = NSLock()
		private var responseResumed = false
		private let onResponse: @Sendable (Result<HTTPResponse, Error>) -> Void
		private let onBytesReceived: @Sendable (Data) -> Void
		private let onComplete: @Sendable (Error?) -> Void

		private init(
			onResponse: @escaping @Sendable (Result<HTTPResponse, Error>) -> Void,
			onBytesReceived: @escaping @Sendable (Data) -> Void,
			onComplete: @escaping @Sendable (Error?) -> Void
		) {
			self.onResponse = onResponse
			self.onBytesReceived = onBytesReceived
			self.onComplete = onComplete
		}

		private func resolveResponse(_ result: Result<HTTPResponse, Error>) {
			lock.lock()
			let alreadyResumed = responseResumed
			responseResumed = true
			lock.unlock()
			guard !alreadyResumed else { return }
			onResponse(result)
		}

		func urlSession(
			_ session: URLSession, dataTask: URLSessionDataTask,
			didReceive response: URLResponse
		) async -> URLSession.ResponseDisposition {
			guard let http = (response as? HTTPURLResponse)?.httpResponse else {
				resolveResponse(.failure(HTTPRequestError.nonHTTPResponse))
				return .cancel
			}
			resolveResponse(.success(http))
			return .allow
		}

		func urlSession(
			_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
		) {
			onBytesReceived(data)
		}

		func urlSession(
			_ session: URLSession, task: URLSessionTask,
			didCompleteWithError error: Error?
		) {
			//A task that fails before headers arrive (DNS/TLS/connection reset)
			//never calls `didReceive response` at all — this is what stops the
			//caller of `streamingData` waiting forever for a response that is
			//never coming.
			if let error {
				resolveResponse(.failure(error))
			}
			onComplete(error)
		}

		static func streamingData(
			from urlRequest: URLRequest, configuration: URLSessionConfiguration
		) async throws -> (response: HTTPResponse, bytes: AsyncThrowingStream<Data, Error>)
		{
			let (bodyStream, bodyContinuation) = AsyncThrowingStream<Data, Error>
				.makeStream()
			//The delegate and the task are both created and started inside the
			//continuation closure, so no callback can possibly fire before the
			//continuation it resumes exists. No second exactly-once guard here:
			//`resolveResponse`'s own lock already guarantees `onResponse` fires
			//at most once, so this closure runs at most once too — a second
			//guard around it would be a plain `var` mutated from a
			//non-isolated closure, exactly the unsafe shape that lock exists
			//to avoid.
			return try await withCheckedThrowingContinuation { responseContinuation in
				let delegate = StreamingResponseDelegate(
					onResponse: { result in
						switch result {
						case .success(let response):
							responseContinuation.resume(
								returning: (response, bodyStream))
						case .failure(let error):
							responseContinuation.resume(throwing: error)
						}
					},
					onBytesReceived: { bodyContinuation.yield($0) },
					onComplete: { error in
						if let error {
							bodyContinuation.finish(throwing: error)
						} else {
							bodyContinuation.finish()
						}
					}
				)
				let session = URLSession(
					configuration: configuration, delegate: delegate,
					delegateQueue: nil)
				let task = session.dataTask(with: urlRequest)
				task.resume()
			}
		}
	}
#endif
