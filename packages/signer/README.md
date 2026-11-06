# ndk_signer

The `EventSigner` interface that NDK signers implement, whether they hold the
key (`Bip340EventSigner`), ask a remote bunker (NIP-46), a browser extension
(NIP-07) or a signer app (NIP-55). It comes with `LocalEventSignerFactory`,
the `PendingSignerRequest` that interactive signers expose while they wait for
the user, and the `SignerRequestRejectedException` and
`SignerRequestCancelledException` they throw.

Pure Dart, interfaces only. A signer such as
[`ndk_bip340`](https://pub.dev/packages/ndk_bip340) or
[`ndk_pq`](https://pub.dev/packages/ndk_pq) only needs this package and
[`ndk_nip01`](https://pub.dev/packages/ndk_nip01), not `ndk_core`.

[NDK](https://pub.dev/packages/ndk) and
[`ndk_core`](https://pub.dev/packages/ndk_core) depend on it and export it, so
apps that already use one of them don't need to add it.

## Install

```yaml
dependencies:
  ndk_signer: ^0.1.0
```

## Usage

Code that signs takes any `EventSigner`:

```dart
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_signer/ndk_signer.dart';

Future<Nip01Event?> signNote(EventSigner signer, String text) async {
  try {
    return await signer.sign(
      Nip01Event(
        pubKey: signer.getPublicKey(),
        kind: Nip01Event.kTextNoteKind,
        tags: [],
        content: text,
      ),
    );
  } on SignerRequestRejectedException {
    return null; // the user said no on the signer
  } on SignerRequestCancelledException {
    return null; // cancelled with cancelRequest
  }
}
```

An interactive signer lists what waits for the user in `pendingRequests` and
`pendingRequestsStream`, and `cancelRequest` drops one. A local signer always
has an empty list. `ConcurrencyLimiterMixin` caps how many requests an
interactive signer sends at once and queues the rest.

To plug a signer into NDK, implement `EventSigner`, and
`LocalEventSignerFactory` if NDK should create it from a private key.

## Coming from `ndk`

`EventSigner`, `LocalEventSignerFactory` and `PendingSignerRequest` used to be
in `ndk_core`, and the two exceptions and `ConcurrencyLimiterMixin` in `ndk`. What changed is in the
[`ndk_core` changelog](https://pub.dev/packages/ndk_core/changelog).
