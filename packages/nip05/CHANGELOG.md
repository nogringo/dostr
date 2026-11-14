## 0.1.0

 - Initial release, moved out of the `ndk` package. `Nip05Usecase` takes a `Nip05Cache` as `cache` instead of `database`. `Nip05Model` is gone: `Nip05HttpRepositoryImpl` returns a `Nip05`, and takes an `http.Client` as `client` instead of an `HttpRequestDS` as `httpDS`. The constants are in lowerCamelCase: `NIP_05_VALID_DURATION` is `nip05ValidDuration`.
