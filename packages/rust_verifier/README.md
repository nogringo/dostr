# ndk_rust_verifier

A fast event verifier for [NDK](https://pub.dev/packages/ndk), written in Rust
and called through `dart:ffi`. `RustEventVerifier` checks the event id and the
BIP-340 signature in one native call, and is faster than `Bip340EventVerifier`.

Native platforms only (Android, iOS, Linux, macOS, Windows). On web,
`verify` throws `UnsupportedError`: use `Bip340EventVerifier`, or
`NdkEventVerifier` from `ndk_flutter`, which picks Web Crypto there.

`ndk` does not depend on this package, so apps that use plain `ndk` don't need
the Rust toolchain. `ndk_flutter` depends on it for `NdkEventVerifier`.

## Install

```yaml
dependencies:
  ndk_rust_verifier: ^0.6.0
```

The build hook compiles the crate in `rust/`, so the
[Rust toolchain](https://rustup.rs) must be installed. The version is pinned in
`rust/rust-toolchain.toml`.

## Usage

```dart
import 'package:ndk/ndk.dart';
import 'package:ndk_rust_verifier/ndk_rust_verifier.dart';

final ndk = Ndk(
  NdkConfig(
    eventVerifier: RustEventVerifier(),
    cache: MemCacheManager(),
  ),
);
```

## Coming from `ndk`

`package:ndk/ndk.dart` no longer exports `RustEventVerifier`. Import
`package:ndk_rust_verifier/ndk_rust_verifier.dart` instead. The post-quantum
signer, verifier and encryption are in [`ndk_post_quantum`](../post_quantum/).

Versions up to 0.5.0 were built with flutter_rust_bridge and needed Flutter.
From 0.6.0 a native assets hook builds the crate, and the package is pure Dart.
