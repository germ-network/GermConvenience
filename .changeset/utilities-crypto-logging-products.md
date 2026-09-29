---
"@germ-network/germ-convenience": minor
---

Add three opt-in library products of general-purpose helpers. None is part of the base `GermConvenience` product, so an existing consumer's own build is unaffected until it adds and imports one — though resolving this release does add a new `swift-log` package dependency (`from: "1.12.0"`) to every consumer's resolved graph, because SwiftPM resolves every package dependency a manifest declares, even ones only used by products the consumer doesn't import. This is lockfile churn, not a break, for every known consumer of this package — but a consumer that caps its own `swift-log` requirement below 1.12.0 will fail to resolve this release.

- `GermConvenienceUtilities` (no extra dependency): `Array.expectOne()` / `expectOneOrLess()`; `Data.debugPrefix`; and `DeleteFuse`, a guard that fails further work with `DeletionError.alreadyDeleting` once a delete has begun. (Does not include `Encodable.encoded`/`Data.decoded()` — the JSON round-trip pair, unlike these, is dropped rather than carried over: `decoded()`'s generic return type is inferred purely from calling context, a real type-inference footgun in practice, and JSON itself isn't the intended long-term wire/storage format here.)
- `GermConvenienceCrypto` (swift-crypto): `Digest.bytes` / `Digest.data`.
- `GermConvenienceLogging` (swift-log, `from: "1.12.0"`, linked only by this product): `Logger.logError(_:context:)`, which passes the error to the handler structurally (`LogEvent.error`) rather than flattening it into the message, and attributes the line to the caller.
