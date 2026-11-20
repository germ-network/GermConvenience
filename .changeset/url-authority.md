---
"@germ-network/germ-convenience": minor
---

Add `URLAuthority`, a normalized, comparable URL authority

`URLAuthority(of:)` produces a `Hashable` host and port, whose `description` is the authority string (`example.com`, `example.com:8443`, `[::1]:8080`):

- The host is lowercased, and internationalized hosts are converted to punycode.
- Hosts that contain, or percent-decode to, a WHATWG forbidden domain code point (control characters, space, `#%/:<>?@[\]^|`) are rejected.
- IPv6 literals are bracketed and serialized in RFC 5952 canonical form (`[0:0::1]` becomes `[::1]`); zone IDs and IPvFuture literals are rejected.
- Hosts ending in a number are parsed as IPv4 per the WHATWG URL Standard and serialized as a dotted quad (`0x7f.1` becomes `127.0.0.1`); malformed ones are rejected.
- The scheme's default port (80 for `http`/`ws`, 443 for `https`/`wss`) is omitted, and ports outside 0-65535 are rejected.
- Failures throw `URLAuthority.Errors`.

Used for the RFC 9421 `@authority` component, and for `URL.origin`.
