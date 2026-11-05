# ndk_pq

Post-quantum crypto for [NDK](https://pub.dev/packages/ndk), written in Rust and
called through `dart:ffi`. Experimental.

- `QsRustEventSigner` and `QsRustEventVerifier`: ML-DSA (FIPS 204) event
  signatures, with the 44, 65 and 87 parameter sets.
- `PqEncryption`: hybrid encryption for direct messages, combining ML-KEM-1024
  with the NIP-44 conversation key. Wire-compatible with
  [`@nostr-wot/pq`](https://github.com/nostr-wot/nostr-wot-sdk/tree/main/packages/pq).

Native platforms only (Android, iOS, Linux, macOS, Windows). On web the signer
and the verifier throw `UnsupportedError`, and `PqEncryption` does not compile.

## Install

```yaml
dependencies:
  ndk_pq: ^0.1.0
```

The build hook compiles the crate in `rust/`, so the
[Rust toolchain](https://rustup.rs) must be installed. The version is pinned in
`rust/rust-toolchain.toml`.

## Usage

```dart
import 'package:ndk_pq/ndk_pq.dart';

final keypair = QsRustEventSigner.generateKeypair(level: 87);
final signer = QsRustEventSigner(keypair: keypair, level: 87);
final verifier = QsRustEventVerifier(level: 87);
```

`PqEncryption` has its own library because it has no web stub:

```dart
import 'package:ndk_pq/pq_encryption.dart';
```

## Coming from `ndk`

The quantum-secure signer and verifier moved from
`package:ndk/data_layer/repositories/...` to `package:ndk_pq/ndk_pq.dart`, and
`package:ndk/shared/nips/pq/pq_encryption.dart` is now
`package:ndk_pq/pq_encryption.dart`.
