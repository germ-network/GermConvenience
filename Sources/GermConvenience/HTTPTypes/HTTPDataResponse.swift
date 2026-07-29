//
//  HTTPDataResponse.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 2/25/26.
//

import Foundation
import HTTPTypes

//type the (data, response) tuple so we can chain handling
public struct HTTPDataResponse: Sendable {
	public let data: Data
	public let response: HTTPResponse

	public init(data: Data, response: HTTPResponse) {
		self.data = data
		self.response = response
	}

	public func expect(statusCode: Int) throws -> Data {
		guard response.status.code == statusCode else {
			throw HTTPResponseError.unsuccessful(response.status.code, data)
		}
		return data
	}

	public func expectSuccess() throws -> Data {
		try expect(status: .successful)

		return data
	}

	func expect(status: HTTPResponse.Status.Kind) throws {
		guard response.status.kind == status else {
			throw HTTPResponseError.unsuccessful(response.status.code, data)
		}
	}

	public enum ErrorResult<R: Decodable, E: Decodable> {
		case result(R)
		case error(E, HTTPResponse.Status)
	}

	//discards the decoding failure but preserves the status and every original byte,
	//so nothing about the response is lost - only the decoder's complaint about a
	//type the body was never going to be
	private func decodedError<E: Decodable>(_ errorType: E.Type) throws -> E {
		guard let decoded = try? data.decode() as E else {
			throw HTTPResponseError.unsuccessful(response.status.code, data)
		}
		return decoded
	}

	public func success<R: Decodable, E: Decodable>(
		code: Int,
		decodeResult resultType: R.Type,
		orError errorType: E.Type,
	) throws -> ErrorResult<R, E> {
		guard response.status.code == code else {
			return .error(try decodedError(errorType), response.status)
		}
		return .result(try data.decode())
	}

	public func success<R: Decodable, E: Decodable>(
		decodeResult resultType: R.Type,
		orError errorType: E.Type,
	) throws -> ErrorResult<R, E> {
		guard response.status.kind == .successful else {
			return .error(try decodedError(errorType), response.status)
		}
		return .result(try data.decode())
	}

	/// Returns normally when the status is 2xx.
	///
	/// Otherwise decodes the body as `E` and throws whatever `mapError` returns,
	/// falling back to `HTTPResponseError.unsuccessful` - status code and raw bytes
	/// intact - when the body does not decode as `E`.
	///
	/// For endpoints that return no success body. When there is a result to decode,
	/// use `success(decodeResult:orError:)` with `get(mapError:)`.
	public func expectSuccess<E: Decodable>(
		orError errorType: E.Type,
		mapError: (E, HTTPResponse.Status) -> any Error
	) throws {
		guard response.status.kind != .successful else { return }
		throw mapError(try decodedError(errorType), response.status)
	}
}

extension HTTPDataResponse.ErrorResult {
	/// Returns the decoded result, or throws the error produced by `mapError`.
	public func get(mapError: (E, HTTPResponse.Status) -> any Error) throws -> R {
		switch self {
		case .result(let result):
			return result
		case .error(let error, let status):
			throw mapError(error, status)
		}
	}
}

extension HTTPDataResponse: CustomStringConvertible {
	public var description: String {
		let bodyDisplay: String
		if let body = String(data: data, encoding: .utf8) {
			bodyDisplay = body.isEmpty ? "<empty>" : #""\#(body)""#
		} else {
			bodyDisplay = "<\(data.count) bytes>"
		}
		return
			"\(_typeName(Self.self, qualified: true))(status: \(response.status.code), data: \(bodyDisplay))"
	}
}

extension Data {
	//If the return type is Data we don't try to decode it
	public func decode<R: Decodable>() throws -> R {
		if R.self == Data?.self || R.self == Data.self,
			let rawData = self as? R
		{
			rawData
		} else {
			try JSONDecoder().decode(R.self, from: self)
		}
	}
}

public enum HTTPResponseError: Error, Equatable {
	case unsuccessful(Int, Data)

	//no longer thrown from this module - every failure path reports .unsuccessful
	//and reads the body through bodyString. Kept so existing callers still compile
	case unsuccessfulString(Int, String)

	//the status the response actually carried, which for expect(statusCode:) and
	//success(code:) may itself be a 2xx that simply was not the one required
	public var code: Int {
		switch self {
		case .unsuccessful(let code, _), .unsuccessfulString(let code, _): code
		}
	}

	public var bodyString: String? {
		switch self {
		case .unsuccessful(_, let data): String(data: data, encoding: .utf8)
		case .unsuccessfulString(_, let body): body
		}
	}
}
