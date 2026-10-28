---
"@germ-network/germ-convenience": minor
---

Align public API names with Swift conventions. Migrations: `HTTPContentType.formUrlEncoded` → `.formURLEncoded`; `.formEncoded` → `.makeMultipartFormDataHeader()`; `FormParameters.asQueryItems()` → `.queryItems` and `.data` → `.encodedData`; `Optional.tryUnwrap` → `.unwrapped` / `unwrap(or:)`; `LazyResource.lazyValue(isolation:)` → `.value(isolation:)`; `Array.expectOne()` / `expectOneOrLess()` → `.singleElement()` / `.singleElementIfAny()`; `HTTPResponseError.code` → `.statusCode`; `HTTPDataResponse.success(code:)` → `success(statusCode:)`; `RFC9421.SignedRequest.base` → `.signatureBase`; and `DeleteFuse.test()` → `.checkNotDeleting()`. Deprecated aliases remain for one release where practical.
