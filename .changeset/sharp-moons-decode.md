---
"@germ-network/germ-convenience": patch
---

Fix `HTTPDataResponse.success` error handling

`success(decodeResult:orError:)` and `success(code:decodeResult:orError:)` wrapped
the status check and the result decode in one `do`, so a successful response whose
body failed to decode was retried as an error body — returning a bogus `.error` for a
2xx, or masking the real `DecodingError` with one about the error type. The status now
selects the branch and decode failures propagate.

A failure response whose body does not decode as the error type now throws
`HTTPResponseError.unsuccessful`, preserving the status code and raw bytes, instead of
a bare `DecodingError`.

Every failure path in this module now reports `HTTPResponseError.unsuccessful`.
`expectSuccess()` previously reported `.unsuccessfulString` whenever the body happened
to be UTF-8, so the two differed for the same response, and an empty body arrived as
`.unsuccessfulString(code, "")`. `.unsuccessfulString` remains in the enum for existing
callers but is no longer thrown from here; read the body through the new `bodyString`
accessor, which works on either case. `code` is also new.
