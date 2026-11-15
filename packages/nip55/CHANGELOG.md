## 0.1.0

 - Initial release, moved out of the `ndk_flutter` package. It does not depend on `dostr_flutter`. The native side is now its own Android plugin, `Nip55Plugin`, on the `dostr_nip55` method channel.
 - `Nip55EventSigner` is now `Nip55Signer`, after the `NostrSigner` it implements. The `Nip55Signer` that talks to the signer app is now `Nip55SignerApp`, and `Nip55Signer` takes it as `signerApp` instead of `nip55Signer`.
