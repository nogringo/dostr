# dostr_rust_verifier

A fast Nostr event verifier, written in Rust and called through `dart:ffi`.
`RustEventVerifier` checks the event id and the BIP-340 signature in one native call.
With `dart run` on an Apple Silicon Mac, it verifies a short note about 25 times faster than `Bip340EventVerifier`, and an event with 264 KiB of tags and content about 5 times faster (`tool/benchmark_rust_event_verifier.dart`).

Native platforms only (Android, iOS, Linux, macOS, Windows).
On web, `RustEventVerifier()` throws `UnsupportedError`: use `Bip340EventVerifier`, or `DostrEventVerifier` from `dostr_flutter`, which picks `WebEventVerifier` from `dostr_noble` there.

`DostrEventVerifier` from `dostr_flutter` verifies in Dart on native platforms: pass a `RustEventVerifier` instead to verify faster.

## Install

```yaml
dependencies:
  dostr_rust_verifier: ^0.1.0
  dostr_core: ^0.1.0
```

The build hook compiles the crate in `rust/` on the machine that builds the app, so that machine needs [rustup](https://rustup.rs).
On the first build, rustup installs the Rust version pinned in `rust/rust-toolchain.toml`, with the 12 targets listed there.
The crate also compiles the C code of libsecp256k1, so the build needs a C compiler for the target: the Android NDK 27 or newer for Android, Xcode for iOS and macOS, the Visual Studio C++ build tools on Windows, and gcc or clang on Linux.

## Usage

```dart
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_rust_verifier/dostr_rust_verifier.dart';

final relayManager = RelayManager(
  nostrTransportFactory: webSocketTransportFactory(),
);
final reqs = RelayReqs(
  relayManager: relayManager,
  eventVerifier: RustEventVerifier(),
);
```

## Coming from `ndk`

Import `RustEventVerifier` from `package:dostr_rust_verifier/dostr_rust_verifier.dart` instead of `package:ndk/ndk.dart`.

`ndk_rust_verifier`, up to 0.5.0, was built with flutter_rust_bridge and needed Flutter.
`dostr_rust_verifier` builds the crate with a native assets hook, and does not need Flutter.
