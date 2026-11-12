## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it, re-exports it and still exposes it as `ndk.zaps` and `ndk.lnurl`. `LnurlTransportHttpImpl` takes an `http.Client` instead of an `HttpRequestDS`.
