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
			try Self.checkBodyMethod(request)
			guard var urlRequest = URLRequest(httpRequest: request.request) else {
				throw HTTPRequestError.missingScheme
			}
			urlRequest.httpBody = request.body

			let (byteStream, urlResponse) = try await self.bytes(for: urlRequest)
			guard let response = (urlResponse as? HTTPURLResponse)?.httpResponse else {
				throw HTTPRequestError.nonHTTPResponse
			}
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
			try Self.checkBodyMethod(request)
			guard var urlRequest = URLRequest(httpRequest: request.request) else {
				throw HTTPRequestError.missingScheme
			}
			urlRequest.httpBody = request.body
			//Reuses self's configuration rather than .default, so a caller's
			//timeout/cache/protocol-class customization (including a test's
			//injected URLProtocol) applies here exactly as it would to any
			//other method called on this same URLSession instance.
			return try await StreamingResponseDelegate.streamingData(
				from: urlRequest, configuration: self.configuration)
		}
	#endif

	fileprivate static let streamChunkSize = 64 * 1024

	//Mirrors `HTTPFetcher.data(for:)`'s guard; `BundledHTTPRequest.init`
	//already rejects this, so unreachable in practice - defence in depth.
	fileprivate static func checkBodyMethod(_ request: BundledHTTPRequest) throws {
		guard request.body != nil,
			request.request.method == .get || request.request.method == .head
		else { return }
		throw HTTPRequestError.getMethodWithBody
	}
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
		private let lock = NSLock()
		private var responseContinuation: CheckedContinuation<HTTPResponse, Error>?
		private var responseResumed = false
		private var cancelled = false
		private var task: URLSessionDataTask?
		private let onBytesReceived: @Sendable (Data) -> Void
		private let onComplete: @Sendable (Error?) -> Void

		private init(
			onBytesReceived: @escaping @Sendable (Data) -> Void,
			onComplete: @escaping @Sendable (Error?) -> Void
		) {
			self.onBytesReceived = onBytesReceived
			self.onComplete = onComplete
		}

		//Resolves inside `didReceive response` itself, not its completion handler; the lock guards this against `waitForResponse` storing the continuation.
		private func resolveResponse(_ result: Result<HTTPResponse, Error>) {
			let pending: CheckedContinuation<HTTPResponse, Error>? = lock.withLock {
				guard !responseResumed else { return nil }
				responseResumed = true
				defer { responseContinuation = nil }
				return responseContinuation
			}
			switch result {
			case .success(let response): pending?.resume(returning: response)
			case .failure(let error): pending?.resume(throwing: error)
			}
		}

		//Store-then-check: if `onCancel` already ran by the time this stores
		//`task`, cancel it here instead of resuming - corelibs then reports
		//`URLError(.cancelled)` through `didCompleteWithError` exactly once,
		//resolving the response through the same path as any other failure.
		func waitForResponse(task: URLSessionDataTask) async throws -> HTTPResponse {
			try await withTaskCancellationHandler {
				try await withCheckedThrowingContinuation { continuation in
					let alreadyCancelled: Bool = lock.withLock {
						responseContinuation = continuation
						self.task = task
						return cancelled
					}
					if alreadyCancelled {
						task.cancel()
					} else {
						task.resume()
					}
				}
			} onCancel: {
				let task: URLSessionDataTask? = lock.withLock {
					cancelled = true
					return self.task
				}
				task?.cancel()
			}
		}

		//The only form corelibs dispatches - the async witness is silently
		//skipped there, and its protocol-extension default is `.allow`. Must
		//match corelibs' declared signature exactly, or it's shadowed the
		//same way.
		func urlSession(
			_ session: URLSession, dataTask: URLSessionDataTask,
			didReceive response: URLResponse,
			completionHandler:
				@escaping @Sendable (URLSession.ResponseDisposition) -> Void
		) {
			guard let http = (response as? HTTPURLResponse)?.httpResponse else {
				resolveResponse(.failure(HTTPRequestError.nonHTTPResponse))
				completionHandler(.cancel)
				dataTask.cancel()
				return
			}
			resolveResponse(.success(http))
			completionHandler(.allow)
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
			if let error {
				resolveResponse(.failure(error))
			} else if let http = (task.response as? HTTPURLResponse)?.httpResponse {
				//corelibs never calls `didReceive response` for a 3xx with no
				//(or an invalid) Location - it just completes with a nil
				//error, the response already set on the task by then.
				resolveResponse(.success(http))
			} else {
				resolveResponse(.failure(HTTPRequestError.nonHTTPResponse))
			}
			onComplete(error)
		}

		static func streamingData(
			from urlRequest: URLRequest, configuration: URLSessionConfiguration
		) async throws -> (response: HTTPResponse, bytes: AsyncThrowingStream<Data, Error>)
		{
			let (bodyStream, bodyContinuation) = AsyncThrowingStream<Data, Error>
				.makeStream()
			let delegate = StreamingResponseDelegate(
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
				configuration: configuration, delegate: delegate, delegateQueue: nil
			)
			let task = session.dataTask(with: urlRequest)
			//A session retains its delegate until invalidated.
			session.finishTasksAndInvalidate()

			//Only on cancellation - installed before `waitForResponse` so a
			//normal `finish()` isn't later reported as `.cancelled` when the
			//stream is simply dropped.
			bodyContinuation.onTermination = { termination in
				if case .cancelled = termination {
					task.cancel()
				}
			}

			let response = try await delegate.waitForResponse(task: task)
			return (response, bodyStream)
		}
	}
#endif
