# ndk_nip07

[NIP-07](https://github.com/nostr-protocol/nips/blob/master/07.md) signer for Nostr: sign events and encrypt or decrypt NIP-04 and NIP-44 messages with the user's browser extension (Alby, nos2x, etc.), through `window.nostr`.

It implements the `EventSigner` of [`ndk_signer`](https://pub.dev/packages/ndk_signer), so NDK accounts can use it, and it depends neither on `ndk` nor on Flutter: any Dart web app can use it. It only signs on the web. Elsewhere `canSign()` returns `false` and the other methods throw an `UnsupportedError`, so shared code still compiles.

## Install

```yaml
dependencies:
  ndk_nip07: ^0.1.0
```

[`ndk_flutter`](https://pub.dev/packages/ndk_flutter) depends on it and exports it, so Flutter apps that use it don't need to add it.

## Usage

```dart
import 'package:ndk_nip07/ndk_nip07.dart';

final signer = Nip07EventSigner();
if (signer.canSign()) {
  await signer.getPublicKeyAsync();
  ndk.accounts.loginExternalSigner(signer: signer);
}
```

The extension asks the user to approve each request. While it waits, the request is in `pendingRequests` and `pendingRequestsStream`, and `cancelRequest` drops it. A refusal throws a `SignerRequestRejectedException`.

`getPublicKey()` is synchronous and throws until the public key is known, because the extension only answers asynchronously. Call `getPublicKeyAsync()` once, or pass a known key to `Nip07EventSigner(cachedPublicKey: pubkey)` when restoring an account.

At most `maxConcurrentRequests` requests (100 by default) go to the extension at once. The rest wait in a queue.

## Coming from `ndk_flutter` or `nip07_event_signer`

`Nip07EventSigner` is the same class. `package:ndk_flutter/ndk_flutter.dart` and `package:ndk_flutter/signers/nip07_event_signer.dart` still export it. Without Flutter, `package:nip07_event_signer/nip07_event_signer.dart` is now `package:ndk_nip07/ndk_nip07.dart`.
