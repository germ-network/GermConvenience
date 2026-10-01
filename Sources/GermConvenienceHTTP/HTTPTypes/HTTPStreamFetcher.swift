//
//  HTTPStreamFetcher.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 9/2/26.
//

import Foundation
import HTTPTypes

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
