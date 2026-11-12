## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it, re-exports it and still exposes it as `ndk.nip05`. `Nip05Usecase` takes a `Nip05Cache`, which `CacheManager` implements, as `cache` instead of `database`. `Nip05Model` is gone: `Nip05HttpRepositoryImpl` returns a `Nip05`, and takes an `http.Client` as `client` instead of an `HttpRequestDS` as `httpDS`.
