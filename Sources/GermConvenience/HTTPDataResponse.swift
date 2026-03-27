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
			if let stringResponse = String(data: data, encoding: .utf8) {
				throw
					HTTPResponseError
					.unsuccessfulString(response.status.code, stringResponse)
			} else {
				throw HTTPResponseError.unsuccessful(response.status.code, data)
			}
		}
	}

	public enum ErrorResult<R: Decodable, E: Decodable> {
		case result(R)
		case error(E, HTTPResponse.Status)
	}

	public func success<R: Decodable, E: Decodable>(
		code: Int,
		decodeResult resultType: R.Type,
		orError error: E.Type,
	) throws -> ErrorResult<R, E> {
		do {
			let result: R = try expect(statusCode: code)
				.decode()

			return .result(result)
		} catch {
			return .error(try data.decode(), response.status)
		}
	}

	public func success<R: Decodable, E: Decodable>(
		kind: HTTPResponse.Status.Kind,
		decodeResult resultType: R.Type,
		orError error: E.Type,
	) throws -> ErrorResult<R, E> {
		do {
			try expect(status: kind)

			return .result(try data.decode())
		} catch {
			return .error(try data.decode(), response.status)
		}

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

public enum HTTPResponseError: Error {
	case unsuccessful(Int, Data)
	case unsuccessfulString(Int, String)
}
