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
a bare `DecodingError`. `HTTPResponseError` gains `code` and `bodyString` accessors so
callers can read either case without matching on both.
