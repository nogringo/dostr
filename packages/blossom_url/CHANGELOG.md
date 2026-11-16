## 0.1.0

 - Initial release. `cleanBlossomServerUrl` normalizes a Blossom server url the way `dostr_relay_url` normalizes a relay url, and returns a `BlossomServerUrl`, an extension type on `String` that only it and `BlossomServerUrl.parse` make. `cleanBlossomServerUrls` does it for a list.
 - `BlossomServerUrl.parse` throws a `FormatException` where `cleanBlossomServerUrl` returns null.
 - It replaces the private normalization of `dostr_fetchers`, which also kept a url with user info or a query, and kept its fragment.
