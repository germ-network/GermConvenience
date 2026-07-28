---
"@germ-network/germ-convenience": patch
---

Add `ErrorResult.get(mapError:)` and `HTTPDataResponse.expectSuccess(orError:mapError:)`

- `get(mapError:)` returns the decoded result or throws a mapped error, replacing the
  switch callers were hand-rolling
- `expectSuccess(orError:mapError:)` for endpoints such as token revocation that return
  no success body. Lifted from oauth4swift
