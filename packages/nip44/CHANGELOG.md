## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - `Nip04` only exposes `encrypt` and `decrypt`, and takes the same keys as `Nip44`.
 - `Nip44.decryptMessage` rejects a payload whose padding is not the one NIP-44 requires.
