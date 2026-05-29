//
//  HTTPFetcher.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 3/7/26.
//

import Foundation
import HTTPTypesFoundation

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

///This protocol wraps the HTTP types of https://github.com/apple/swift-http-types
///to provide a mockable fetch interface
///While we intend to primarily depend on Foundation, it is possible to use HTTPTypes independently
///of foundation and define your own extensions of your preferred fetch implementation
public protocol HTTPFetcher: Sendable {
	func data(for: BundledHTTPRequest) async throws -> HTTPDataResponse
}

///Authorization fetches should not follow redirects. This includes
///the protected resource metadata
///https://www.rfc-editor.org/rfc/rfc9728.html#section-3.2
///and auth server metadata
///https://datatracker.ietf.org/doc/html/rfc8414#section-3.2
extension URLSession {
	static public func manualRedirect() -> URLSession {
		URLSession(
			configuration: .default,
			delegate: ManualRedirect(),
			delegateQueue: nil
		)
	}
}

///The default (shared) urlsession does follow redirects, which is permitted for resource requests
extension URLSession: HTTPFetcher {
	public func data(
		for request: BundledHTTPRequest
	) async throws -> HTTPDataResponse {
		if let body = request.body {
			guard request.request.method != .get else {
				throw HTTPRequestError.getMethodWithBody
			}
			let (data, httpResponse) = try await upload(
				for: request.request,
				from: body
			)
			return .init(data: data, response: httpResponse)
		} else {
			let (data, httpResponse) = try await data(for: request.request)
			return .init(data: data, response: httpResponse)
		}
	}
}

final class ManualRedirect: NSObject, URLSessionTaskDelegate {
	func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest
	) async -> URLRequest? {
		nil
	}
}

//we use this to resolve well-known
//works around what appears to be a linking issue with test bundles and
//HTTPTypesFoundationMethods
//https://forums.swift.org/t/asyncbytes-and-asynclinesequence-not-available-on-linux/73601
#if os(Linux) || os(Android)
//don't have URLSession.bytes(for), so need to use the sessionDelegate
final class StreamingDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
	let onBytesReceived: (@Sendable (Data) -> Void)?
	let onComplete: (@Sendable (Error?) -> Void)?
	
	init(
		onBytesReceived: (@Sendable(Data) -> Void)?,
		onComplete: (@Sendable(Error?) -> Void)?
	) {
		self.onBytesReceived = onBytesReceived
		self.onComplete = onComplete
	}
	
	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		onBytesReceived?(data)
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		onComplete?(error)
	}
	
	// 2. Wrap the delegate inside an AsyncStream wrapper
	static func streamBytes(from urlRequest: URLRequest) -> AsyncThrowingStream<Data, Error> {
		return AsyncThrowingStream { continuation in
			let delegate = StreamingDelegate() {
				continuation.yield($0)
			} onComplete: { error in
				if let error = error {
					continuation.finish(throwing: error)
				} else {
					continuation.finish()
				}
			}

			let configuration = URLSessionConfiguration.default
			let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
			
			
			let task = session.dataTask(with: urlRequest)
			task.resume()
		}
	}
}

extension URLSession {
	public func firstLine(request: HTTPRequest) async throws -> String? {
		let stream = StreamingDelegate.streamBytes(
			from: try URLRequest(httpRequest: request).tryUnwrap
		)
		let firstLine = try await stream.first(where: { _ in true })
		guard let firstLine else {
			return nil
		}
		return String(bytes: firstLine, encoding: .utf8)

	}
}
#else
extension URLSession {
	public func firstLine(request: HTTPRequest) async throws -> String? {
		let (byteStream, response) = try await URLSession.shared.bytes(
			for: request)
		guard response.status == .ok else {
			var collectedData = Data()
			for try await byte in byteStream {
				collectedData.append(byte)
			}
			throw
				HTTPResponseError
				.unsuccessful(response.status.code, collectedData)
		}
		
		return try await byteStream.lines.first(where: { _ in true })
	}
}
#endif
