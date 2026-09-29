//
//  Coding.swift
//  GermConvenienceUtilities
//

import Foundation

public enum TypedCodableError: Error {
	case typeMismatch
	case missingStoredValue
	case decode(String, Error)
}

extension TypedCodableError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .typeMismatch:
			"Typed JSON decoding mismatch between declared and expected type"
		case .missingStoredValue:
			"Expect stored value missing"
		case .decode(let string, let error):
			"Error decoding type \(string): \(error.localizedDescription)"
		}
	}
}

extension Encodable {
	public var encoded: Data {
		get throws { try JSONEncoder().encode(self) }
	}
}

///Captures type information when throwing a Json decoder error so we know what object it was trying to decode
extension Data {
	public func decoded<T: Decodable>() throws -> T {
		do {
			return try JSONDecoder().decode(T.self, from: self)
		} catch {
			throw TypedCodableError.decode("\(type(of: T.self))", error)
		}
	}
}
