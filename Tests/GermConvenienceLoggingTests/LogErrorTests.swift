//
//  LogErrorTests.swift
//  GermConvenienceLoggingTests
//

import Foundation
import GermConvenienceLogging
import Logging
import Testing

///Pins the one property that distinguishes `logError` from a flat, string-only
///log call: the error travels in `LogEvent.error`, not flattened into the
///message. A handler can therefore render type and description separately.
struct LogErrorTests {
	private struct Boom: Error {}

	final class CapturingHandler: LogHandler, @unchecked Sendable {
		final class Box: @unchecked Sendable {
			var message: String?
			var error: (any Error)?
			var file: String?
		}
		let box: Box
		var metadata: Logger.Metadata = [:]
		var logLevel: Logger.Level = .trace

		init(box: Box) { self.box = box }

		subscript(metadataKey key: String) -> Logger.Metadata.Value? {
			get { metadata[key] }
			set { metadata[key] = newValue }
		}

		///swift-log 1.15's primary requirement is `log(event:)`. Implementing
		///only a deprecated flat-parameter overload instead recurses forever
		///between the two compatibility defaults and blows the stack.
		func log(event: LogEvent) {
			box.message = event.message.description
			box.error = event.error
			box.file = event.file
		}
	}

	@Test func theErrorTravelsStructurallyNotInTheMessage() {
		let box = CapturingHandler.Box()
		let logger = Logger(label: "test") { _ in CapturingHandler(box: box) }

		logger.logError(Boom(), context: "opening the widget")

		#expect(box.error is Boom)
		#expect(box.message == "Error opening the widget")
		//The description is NOT stuffed into the message — that is the whole
		//difference from a flat, string-only log call.
		#expect(box.message?.contains("Boom") == false)
	}

	///Without forwarding `#fileID`, every line would be attributed to
	///ErrorStack.swift instead of the call site.
	@Test func sourceLocationIsTheCallerNotTheExtension() {
		let box = CapturingHandler.Box()
		let logger = Logger(label: "test") { _ in CapturingHandler(box: box) }

		logger.logError(Boom(), context: "somewhere")

		#expect(box.file?.contains("LogErrorTests") == true)
		#expect(box.file?.contains("ErrorStack") == false)
	}

	@Test func aNilErrorStillLogsTheContext() {
		let box = CapturingHandler.Box()
		let logger = Logger(label: "test") { _ in CapturingHandler(box: box) }

		logger.logError(nil, context: "no error here")

		#expect(box.error == nil)
		#expect(box.message == "Error no error here")
	}
}
