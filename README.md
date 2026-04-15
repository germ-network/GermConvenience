In support of the [AtprotoOauth](https://github.com/germ-network/AtprotoOAuth) family of modular packages,
shared helper implementations:
* an HTTPDataResponse type for the return value of `URLSession.data(for:)`
	* functional affordances for checking the success codes and decoding result and error types
	* HTTPFetcher, an abstraction of `URLSession.data(for)` to allow mocking of requests for test
* typed HTTP Method and URL shemes
* tryUnwrap
* String -> utf8 Data
* copy bytes from Contiguous bytes (primarily used to get random bytes for use as an identifier or mock data)



## Contributing and Collaboration
We welcome contributions!

Please follow our [guidelines for contributing code](./CONTRIBUTING.md)

To give clarity of what is expected of our members, Germ has adopted the
code of conduct defined by the Contributor Covenant. This document is used
across many open source communities, and we think it articulates our values
well. For more, see the [Code of Conduct](./CODE_OF_CONDUCT.md)
