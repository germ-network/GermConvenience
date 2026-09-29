---
"@germ-network/germ-convenience": minor
---

Add three opt-in library products of general-purpose helpers. None is part of the base `GermConvenience` product, so an existing consumer's own build is unaffected until it adds and imports one — though resolving this release does add a new `swift-log` package dependency (`from: "1.12.0"`) to the graph for every consumer, since SwiftPM's resolver pins a package dependency once any target in the graph needs it, not only once a consumer imports the target that uses it.

- `GermConvenienceUtilities` (no extra dependency): `Encodable.encoded` / `Data.decoded()` JSON helpers, with decode failures wrapped in `TypedCodableError.decode` naming the target type; `Array.expectOne()` / `expectOneOrLess()`; `Data.debugPrefix`; and `DeleteFuse`, a guard that fails further work with `DeletionError.alreadyDeleting` once a delete has begun.
- `GermConvenienceCrypto` (swift-crypto): `Digest.bytes` / `Digest.data`.
- `GermConvenienceLogging` (swift-log, `from: "1.12.0"`, linked only by this product): `Logger.logError(_:context:)`, which passes the error to the handler structurally (`LogEvent.error`) rather than flattening it into the message, and attributes the line to the caller.
