---
"@germ-network/germ-convenience": minor
---

Add `URL.origin`

The origin is the lowercased scheme plus the `URLAuthority`, e.g. `https://example.com:8443`, so equivalent spellings of a URL produce the same origin. Compared with the oauth4swift version, IPv6 hosts now keep their brackets, mixed-case schemes drop their default port, and `ws`/`wss` default ports are omitted. It throws `URLError(.unsupportedURL)` when the URL has no scheme, and rethrows `URLAuthority.Errors`.

Moved to GermConvenience from oauth4swift, where it was used for DPoP `htu` and nonce-cache keys.
