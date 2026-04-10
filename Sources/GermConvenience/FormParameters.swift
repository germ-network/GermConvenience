//
//  FormParameters.swift
//  GermConvenience
//
//  Created by Emelia on 4/11/26.
//
import Foundation

public struct FormParameters: Codable, Sendable {
	typealias Storage = [String: [String]]
	private var storage: Storage

	public static var contentType: HTTPContentType { .formUrlEncoded }

	public init() {
		self.storage = [:]
	}

	public init(parameters: [String: [String]]) {
		self.storage = parameters
	}

	public init(parameters: [String: String]) {
		self.storage = parameters.reduce(
			into: Storage(),
			{
				storage, parameter in
				storage[parameter.key] = [parameter.value]
			})
	}

	public mutating func set(name: String, value: String) {
		if var params = self.storage[name] {
			params.append(value)
			self.storage[name] = params
		} else {
			self.storage[name] = [value]
		}
	}

	public func get(name: String) -> [String]? {
		return self.storage[name]
	}

	public func asQueryItems() -> [URLQueryItem] {
		self.storage.flatMap({ parameter -> [URLQueryItem] in
			parameter.value.map({ value -> URLQueryItem in
				.init(name: parameter.key, value: value)
			})
		})
	}

	public func encode() throws -> Data {
		return self.storage.flatMap { parameter -> [String] in
			guard
				let key = parameter.key.addingPercentEncoding(
					withAllowedCharacters: .urlQueryAllowed)
			else {
				return []
			}

			return parameter.value.compactMap { value -> String? in
				guard
					let encodedValue = value.addingPercentEncoding(
						withAllowedCharacters: .urlQueryAllowed)
				else {
					return nil
				}

				return [key, encodedValue].joined(separator: "=")
			}
		}.joined(separator: "&").utf8Data
	}
}
