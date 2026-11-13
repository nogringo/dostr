# dostr_rust_verifier

A fast Nostr event verifier, written in Rust and called through `dart:ffi`.
`RustEventVerifier` checks the event id and the BIP-340 signature in one native
call, and is faster than `Bip340EventVerifier`.

Native platforms only (Android, iOS, Linux, macOS, Windows). On web,
`verify` throws `UnsupportedError`: use `Bip340EventVerifier`, or
`DostrEventVerifier` from `dostr_flutter`, which picks Web Crypto there.

`dostr_flutter` depends on it for `DostrEventVerifier`.

## Install

```yaml
dependencies:
  dostr_rust_verifier: ^0.6.0
  dostr_core: ^0.11.0-dev.2
```

The build hook compiles the crate in `rust/`, so the
[Rust toolchain](https://rustup.rs) must be installed. The version is pinned in
`rust/rust-toolchain.toml`.

## Usage

```dart
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_rust_verifier/dostr_rust_verifier.dart';

final relayManager = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relayManager,
  eventVerifier: RustEventVerifier(),
);
```

## Coming from `ndk`

Import `RustEventVerifier` from
`package:dostr_rust_verifier/dostr_rust_verifier.dart` instead of
`package:ndk/ndk.dart`.

`ndk_rust_verifier`, up to 0.5.0, was built with flutter_rust_bridge and needed
Flutter. From 0.6.0 a native assets hook builds the crate, and the package is
pure Dart.
