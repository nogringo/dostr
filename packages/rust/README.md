# ndk_rust

Native Rust crypto for [NDK](https://pub.dev/packages/ndk), called through
`dart:ffi` and built by a native assets hook:

- `RustEventVerifier`: checks the event id and the BIP-340 signature in one
  native call. Faster than `Bip340EventVerifier`.
- `QsRustEventSigner` and `QsRustEventVerifier`: ML-DSA (FIPS 204) event
  signatures.
- `PqEncryption`: post-quantum hybrid encryption (ML-KEM-1024 combined with the
  NIP-44 conversation key), wire-compatible with
  [`@nostr-wot/pq`](https://github.com/nostr-wot/nostr-wot-sdk/tree/main/packages/pq).

Native platforms only (Android, iOS, Linux, macOS, Windows). On web the
verifiers and the signer throw `UnsupportedError`, and `PqEncryption` does not
compile.

`ndk` does not depend on this package, so apps that use plain `ndk` don't need
the Rust toolchain. `ndk_flutter` depends on it for `NdkEventVerifier`.

## Install

```yaml
dependencies:
  ndk_rust: ^0.1.0
```

The build hook compiles the crate in `rust/`, so the
[Rust toolchain](https://rustup.rs) must be installed. The version is pinned in
`rust/rust-toolchain.toml`.

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_rust/ndk_rust.dart';

final ndk = Ndk(
  NdkConfig(
    eventVerifier: RustEventVerifier(),
    cache: MemCacheManager(),
  ),
);
```

`PqEncryption` has its own library because it has no web stub:

```dart
import 'package:ndk_rust/pq_encryption.dart';
```

## Coming from `ndk`

`package:ndk/ndk.dart` no longer exports `RustEventVerifier`. Import
`package:ndk_rust/ndk_rust.dart` instead. The quantum-secure signer and
verifier moved from `package:ndk/data_layer/repositories/...` to the same
library, and `package:ndk/shared/nips/pq/pq_encryption.dart` is now
`package:ndk_rust/pq_encryption.dart`.
