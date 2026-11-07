## 0.1.0

 - Initial release, split out of `ndk_rust` with the ML-DSA signer and verifier and `PqEncryption`.
 - `QsRustEventVerifier` rejects an event whose id does not match its payload.
 - `QsRustEventVerifier` rejects a sig or a pubkey that is not lowercase hex. It used to accept uppercase hex, and a `+` or `-` sign in place of a digit.
 - `QsRustEventSigner.sign` signs the id of the event carrying its public key. It used to sign the id computed before it set that key, so the signed event had a wrong id.
