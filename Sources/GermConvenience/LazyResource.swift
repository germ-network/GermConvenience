//
//  LazyResource.swift
//  OAuth
//
//  Created by Mark @ Germ on 2/25/26.
//

import Foundation

///wrapper for e.g. a remote resource which we can
///* lazily fetch
///* lazily re-fetch if prior fetches failed
public final class LazyResource<Resource: Sendable> {
	enum State {
		case fetched(Resource)
		case fetching(Task<Resource, Error>)
		case unknown
	}
	private var state: State

	private var makeFetchTask: () -> Task<Resource, Error>

	/// Creates a lazily fetched resource using `fetchTaskGenerator` when first accessed.
	public init(fetchTaskGenerator: @escaping () -> Task<Resource, Error>) {
		self.state = .unknown
		self.makeFetchTask = fetchTaskGenerator
	}

	//periphery:ignore:parameters isolation
	/// Returns the resource, fetching it once on first access and retrying after a failure.
	public func value(
		isolation: isolated (any Actor),
	) async throws -> Resource {
		switch state {
		case .fetched(let resource):
			return resource
		case .fetching(let task):
			return try await task.value
		case .unknown:
			let task = makeFetchTask()
			state = .fetching(task)

			do {
				let fetched = try await task.value
				state = .fetched(fetched)
				return fetched
			} catch {
				state = .unknown
				throw error
			}
		}
	}

	@available(*, deprecated, renamed: "value(isolation:)")
	public func lazyValue(
		isolation: isolated (any Actor),
	) async throws -> Resource {
		try await value(isolation: isolation)
	}
}
