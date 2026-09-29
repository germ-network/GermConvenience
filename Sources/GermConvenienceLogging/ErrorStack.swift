//
//  ErrorStack.swift
//  GermConvenienceLogging
//

import Foundation
import Logging

/// Unified error logging on swift-log.
///
/// The error is carried structurally (`LogEvent.error`) rather than flattened
/// into the message, so handlers can render type and description separately —
/// `StreamLogHandler` emits `error.message` / `error.type`. Source location is
/// forwarded so lines are attributed to the caller, not here.
extension Logging.Logger {
	public func logError(
		_ error: (any Error)?,
		context: String,
		file: String = #fileID,
		function: String = #function,
		line: UInt = #line
	) {
		self.error(
			"Error \(context)",
			error: error,
			file: file,
			function: function,
			line: line
		)
	}
}
