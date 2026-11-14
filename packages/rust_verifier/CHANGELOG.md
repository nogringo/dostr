## 0.1.0

 - `RustEventVerifier` moves here out of the `ndk` package. A native assets hook
   now builds the crate instead of flutter_rust_bridge, so the package no longer
   needs Flutter.
 - `RustEventVerifier` hashes the content and the tags as Dart holds them, NUL
   characters included, and the kind and `created_at` as 64-bit integers. It
   rejects an id, a pubkey or a sig that is not lowercase hex.
