# ndk_signer

The `EventSigner` interface that NDK signers implement, whether they hold the
key (`Bip340EventSigner`), ask a remote bunker (NIP-46), a browser extension
(NIP-07) or a signer app (NIP-55). It comes with `LocalEventSignerFactory`,
the `PendingSignerRequest` that interactive signers expose while they wait for
the user, and the `SignerRequestRejectedException` and
`SignerRequestCancelledException` they throw.

It also holds the accounts NDK may authenticate as, and what decides when one
is revealed: to a relay that asks for NIP-42 authentication, or to a Blossom
server.

Pure Dart, interfaces only. A signer such as
[`ndk_bip340`](https://pub.dev/packages/ndk_bip340) or
[`ndk_post_quantum`](https://pub.dev/packages/ndk_post_quantum) only needs this package and
[`ndk_nip01`](https://pub.dev/packages/ndk_nip01), not `ndk_core`. So does a
package that authenticates on behalf of NDK accounts, such as
[`ndk_blossom`](https://pub.dev/packages/ndk_blossom).

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

## Accounts and authentication

- `Account`: a pubkey and the `EventSigner` that signs for it.
- `AuthAccounts`: where the logged-in account comes from, implemented by
  `Accounts` from [`ndk_accounts`](https://pub.dev/packages/ndk_accounts).
- `AuthPolicy`: what one operation may reveal. `never()` stays anonymous,
  `allow(account)` authenticates when asked, `require(account)` authenticates
  upfront and fails if it cannot.
- `AuthHandler`: asked before a pubkey is revealed on a url. Answering false
  keeps it from being revealed there.

```dart
final policy = AuthPolicy.allow(
  Account(
    type: AccountType.privateKey,
    pubkey: signer.getPublicKey(),
    signer: signer,
  ),
);

Future<bool> onlyMyRelay(String url, String pubkey) async =>
    url == 'wss://relay.example.com';
```

## Coming from `ndk`

`EventSigner`, `LocalEventSignerFactory` and `PendingSignerRequest` used to be
in `ndk_core`, and the two exceptions and `ConcurrencyLimiterMixin` in `ndk`. What changed is in the
[`ndk_core` changelog](https://pub.dev/packages/ndk_core/changelog).

`package:ndk_core/domain_layer/entities/account.dart`, `auth_policy.dart`,
`auth_handler.dart` and `package:ndk_core/domain_layer/repositories/auth_accounts.dart`
are now `package:ndk_signer/ndk_signer.dart`. `package:ndk/ndk.dart` and
`package:ndk_core/ndk_core.dart` still export it. `TimeoutPausable` stays in
`ndk_core`, in `package:ndk_core/domain_layer/entities/timeout_pausable.dart`.
