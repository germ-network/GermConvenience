---
"@germ-network/germ-convenience": minor
---

Widen the `swift-crypto` dependency to `from: "5.0.0"`.

Part of the org-wide move to swift-crypto 5 (its span-based API is already
adopted by `swift-secret-bytes`). Builds and the full test suite pass against
5.0.0 unchanged.
