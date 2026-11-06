## 0.1.0

 - Initial release, moved out of the `ndk_flutter` package. It does not depend on `ndk` or `ndk_flutter`. `ndk_flutter` depends on it and still exports `Nip55Signer`, `Nip55EventSigner`, `Nip55Permission` and `Nip55LoginResult`. The native side is now its own Android plugin, `Nip55Plugin`, on the `ndk_nip55` method channel.
