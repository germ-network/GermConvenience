//
//  FormParameters.swift
//  GermConvenience
//
//  Created by Emelia on 4/11/26.
//
import Foundation

public struct FormParameters: Codable, Sendable {
	private var storage: [String: [String]]

	public static var contentType: HTTPContentType { .formUrlEncoded }

	public init() {
		self.storage = [:]
	}

	public init(parameters: [String: [String]]) {
		self.storage = parameters
	}

	public init(parameters: [String: String]) {
		self.storage = parameters.reduce(into: [:]) {
			storage, parameter in
			storage[parameter.key, default: []].append(parameter.value)
		}
	}

	public mutating func set(name: String, value: String) {
		var params = self.storage[name, default: []]
		params.append(value)

		self.storage[name] = params
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
				let encodedKey = parameter.key.addingPercentEncoding(
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

				return [encodedKey, encodedValue].joined(separator: "=")
			}
		}.joined(separator: "&").utf8Data
	}
}
