## 0.1.0

 - Initial release. `BlossomServerUrl.tryParse` normalizes a Blossom server url as `RelayUrl.tryParse`, from `dostr_relay_url`, normalizes a relay url, and returns a `BlossomServerUrl`, an extension type on `String` that only it, `BlossomServerUrl.parse` and `BlossomServerUrl.fromUserInput` make, short of a cast.
 - `BlossomServerUrl.parse` throws a `FormatException` where `BlossomServerUrl.tryParse` returns null.
 - `BlossomServerUrl.fromUserInput` normalizes a server url a person typed: it reads a url without a scheme as an `https` url. Without a scheme, the host must be `localhost`, an IP address or a name holding a dot.
 - It replaces the private normalization of `dostr_fetchers`, which also kept a url with user info or a query, and kept its fragment and the trailing dot of its host.
