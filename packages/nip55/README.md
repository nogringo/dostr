# dostr_nip55

[NIP-55](https://github.com/nostr-protocol/nips/blob/master/55.md) signing for Nostr on Android: log in with a signer app installed on the device, then sign events and encrypt or decrypt NIP-04 and NIP-44 messages through it.

It implements the `NostrSigner` of [`dostr_signer`](https://pub.dev/packages/dostr_signer), so Dostr accounts can use it.
It is a Flutter plugin for Android and does not depend on `dostr_flutter`.

## With `dostr_flutter`

`dostr_flutter` depends on this package and exports it.
Its `NLogin` widget offers the signer app login, and `DostrFlutter` saves and restores these accounts.

## Standalone

```yaml
dependencies:
  dostr_nip55: ^0.1.0
```

```dart
import 'package:dostr_nip55/dostr_nip55.dart';

const signerApp = Nip55SignerApp();
if (await signerApp.isAppInstalled()) {
  final login = await signerApp.login();
  final signer = Nip55Signer(
    publicKey: login.pubkey,
    signerApp: Nip55SignerApp(package: login.package),
  );
  accounts.loginExternalSigner(signer: signer);
}
```

`accounts` is an `Accounts` from [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).

`login()` asks the signer app for the user's public key and pre-authorizes `Nip55SignerApp.defaultPermissions`, so later requests can be answered silently, without opening the signer app.
Pass your own list of `Nip55Permission` to ask for other ones.
It throws a `SignerRequestRejectedException` when the user refuses, and a `SignerRequestFailedException` when no key comes back, such as when the signer app cannot be opened.
Keep `login.package` and pass it to `Nip55SignerApp(package:)`: requests then go straight to the same signer app.
With no package, each request opens a signer app.

To restore the account in a later session, store `login.pubkey` and `login.package` and build the same `Nip55Signer` from them: nothing reaches the signer app until the first request.
`Nip55SignerApp(package: login.package).isAppInstalled()` tells whether that signer app is still installed.

The signer app may ask the user to approve each request.
While it waits, the request is in `pendingRequests` and `pendingRequestsStream`, and `cancelRequest` drops it.
A refusal throws a `SignerRequestRejectedException`, also when the user told the signer app to always reject that request.
A request with no usable answer throws a `SignerRequestFailedException`: the signer app could not be opened, closed without a result, or signed as another account.
`sign` returns the event the signer app actually signed, which can differ from the one you passed, so read the id from the signed event.
Pass a `verifier`, such as the `Bip340EventVerifier` of `dostr_bip340`, to also check the signature of every signed event.
At most `maxConcurrentRequests` requests (100 by default) go out at once.
The rest wait in a queue.
`dispose` fails every request that has no answer yet with a `SignerRequestFailedException`.

On other platforms than Android, `Nip55SignerApp.isSupported`, `isAppInstalled()` and `Nip55Signer.canSign` are false, and every request throws an `UnsupportedError`.

## Coming from `ndk_flutter`

`Nip55EventSigner` is now `Nip55Signer`.
The `Nip55Signer` that talks to the signer app is now `Nip55SignerApp`, and `Nip55Signer` takes it as `signerApp` instead of `nip55Signer`.
Its `getPublicKey` and `getPublicKeyHex` are gone: `login` returns the pubkey, in hex, and the signer app package.
`login` throws a `SignerRequestRejectedException` or a `SignerRequestFailedException` instead of returning `null`.
`package:ndk_flutter/ndk_flutter.dart` is now `package:dostr_flutter/dostr_flutter.dart`, which still exports them.
The deep imports `package:ndk_flutter/data_layer/data_sources/nip55_signer.dart` and `package:ndk_flutter/data_layer/repositories/signers/nip55_event_signer.dart` are now `package:dostr_nip55/dostr_nip55.dart`.
The method channel is now `dostr_nip55` instead of `ndk`.
