# dostr_nip07

[NIP-07](https://github.com/nostr-protocol/nips/blob/master/07.md) signer for Nostr: sign events and encrypt or decrypt NIP-04 and NIP-44 messages with the user's browser extension (Alby, nos2x, etc.), through `window.nostr`.

It implements the `NostrSigner` of [`dostr_signer`](https://pub.dev/packages/dostr_signer), so Dostr accounts can use it, and it does not depend on Flutter: any Dart web app can use it.
It only signs on the web.
Elsewhere `isAvailable` and `canSign` are `false` and the other methods throw an `UnsupportedError`, so shared code still compiles.

## Install

```yaml
dependencies:
  dostr_nip07: ^0.1.0
```

[`dostr_flutter`](https://pub.dev/packages/dostr_flutter) depends on it and exports it, so Flutter apps that use it don't need to add it.

## Usage

```dart
import 'package:dostr_nip07/dostr_nip07.dart';

if (await Nip07Signer.waitForExtension()) {
  final signer = await Nip07Signer.connect();
  accounts.loginExternalSigner(signer: signer);
}
```

`accounts` is an `Accounts` from [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).

An extension may add `window.nostr` a moment after the page loads.
`waitForExtension` waits for it, up to one second by default, where `isAvailable` only tells whether it is there now.

The extension asks the user to approve each request.
While it waits, the request is in `pendingRequests` and `pendingRequestsStream`, and `cancelRequest` drops it.
When the extension rejects a request, it throws a `SignerRequestRejectedException`, whether the user refused it or the extension failed: NIP-07 does not tell the two apart.
An answer the signer cannot use, such as an event signed by another account after the user switched accounts in the extension, throws a `SignerRequestFailedException`.
Without an extension, every request throws a `StateError`.

`connect` asks the extension for the user's pubkey, which the extension may ask the user to approve first, and completes once it has it: `publicKey` never throws.
Without a pubkey within its `timeout`, 10 minutes by default, it throws a `SignerRequestFailedException`.
Pass a known key to `Nip07Signer(publicKey: pubkey)` when restoring an account.

The signer checks the id and the pubkey of each event the extension signs.
Give it a `verifier`, such as the `Bip340EventVerifier` of [`dostr_bip340`](https://pub.dev/packages/dostr_bip340), to check the signature too:

```dart
final signer = await Nip07Signer.connect(verifier: Bip340EventVerifier());
```

At most `maxConcurrentRequests` requests (100 by default) go to the extension at once.
The rest wait in a queue.

## Coming from `ndk_flutter` or `nip07_event_signer`

`Nip07EventSigner` is now `Nip07Signer`.
`package:ndk_flutter/ndk_flutter.dart` and `package:ndk_flutter/signers/nip07_event_signer.dart` are now `package:dostr_flutter/dostr_flutter.dart`, which still exports it.
Without Flutter, `package:nip07_event_signer/nip07_event_signer.dart` is now `package:dostr_nip07/dostr_nip07.dart`.
