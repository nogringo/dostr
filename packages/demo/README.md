# example

Example flutter app using NDK

Built on [dostr_core](https://pub.dev/packages/dostr_core), [dostr_flutter](https://pub.dev/packages/dostr_flutter) and the NIP packages of NDK.

## Getting Started

0. install the Rust toolchain, which [dostr_rust_verifier](https://pub.dev/packages/dostr_rust_verifier) needs on native platforms

1. clone repository
   `git clone https://github.com/relaystr/ndk.git`

2. change dir into sample app `cd ./packages/demo`

3. download packages `flutter pub get`

4. start app `flutter run`

## NIP-55 signer

A NIP-55 compatible external Nostr signer is optional for running this
application. The sample app is not tied to any specific signer app.
