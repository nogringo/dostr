# Dostr demo app

Example Flutter app built with Dostr packages.

Built on [dostr_core](https://pub.dev/packages/dostr_core), [dostr_flutter](https://pub.dev/packages/dostr_flutter) and the Dostr NIP packages.

## Getting Started

0. install the Rust toolchain, which [dostr_rust_verifier](https://pub.dev/packages/dostr_rust_verifier) needs on native platforms

1. clone repository
   `git clone https://github.com/nogringo/dostr.git`

2. change dir into the demo `cd ./packages/demo`

3. download packages `flutter pub get`

4. start app `flutter run`

## NIP-55 signer

A NIP-55 compatible external Nostr signer is optional for running this
application. The demo is not tied to any specific signer app.
