## 0.1.0

 - Initial release, moved out of the `ndk` package. `Nip05Usecase` is now `Nip05Resolver`, and takes an optional `Nip05Cache` as `cache` instead of `database`: without one, it keeps what it resolved in memory. `Nip05Model` is gone: `Nip05HttpRepositoryImpl`, now `HttpNip05Repository`, returns a `Nip05`, and takes an `http.Client` as `client` instead of an `HttpRequestDS` as `httpDS`. The constants are in lowerCamelCase: `NIP_05_VALID_DURATION` is `nip05ValidDuration`.
 - `Nip05.pubKey` is now `pubkey`, in its constructor and `copyWith` too.
