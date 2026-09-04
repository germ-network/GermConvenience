---
"@germ-network/germ-convenience": minor
---

Add `GermHTTPSignature`, an RFC 9421 HTTP Message Signatures request signer, as
its own library product. `RFC9421.sign(method:url:nonce:keyid:created:body:sign:)`
builds the covered-component set (`@method`, `@authority`, `@path`, plus `@query`
when the URL carries one and `content-digest` when the body is non-empty), the
signature base, and the `Signature`/`Signature-Input`/`Content-Digest` headers —
signing via an injected closure so the caller owns the private key. Ed25519 (`alg="ed25519"`).

Shipped as a separate target/product so that swift-crypto (used only for the
content-digest SHA-256) stays off the base `GermConvenience` target — only a
consumer that imports `GermHTTPSignature` links it. Byte-identity of the
canonicalization is pinned by a known-answer vector suite.
