Shared implementations across packages:
* an HTTPDataResponse type for the return value of `URLSession.data(for:)`
	* functional affordances for checking the success codes and decoding result and error types
	* HTTPFetcher, an abstraction of `URLSession.data(for)` to allow mocking of requests for test
* typed HTTP Method and URL shemes
* tryUnwrap
* String -> utf8 Data
* copy bytes from Contiguous bytes (primarily used to get random bytes for use as an identifier or mock data)