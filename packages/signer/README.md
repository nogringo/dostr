# dostr_signer

The `EventSigner` interface that Dostr signers implement, whether they hold the
key (`Bip340EventSigner`), ask a remote bunker (NIP-46), a browser extension
(NIP-07) or a signer app (NIP-55). It comes with `LocalEventSignerFactory`,
the `PendingSignerRequest` that interactive signers expose while they wait for
the user, and the `SignerRequestRejectedException` and
`SignerRequestCancelledException` they throw.

It also holds the accounts the Dostr packages may authenticate as, and what
decides when one is revealed: to a relay that asks for NIP-42 authentication,
or to a Blossom server.

Pure Dart, interfaces only. A signer such as
[`dostr_bip340`](https://pub.dev/packages/dostr_bip340) needs this package and
[`dostr_nip01`](https://pub.dev/packages/dostr_nip01), not `dostr_core`. So does a
package that authenticates on behalf of Dostr accounts, such as
[`dostr_blossom`](https://pub.dev/packages/dostr_blossom).

[`dostr_core`](https://pub.dev/packages/dostr_core) depends on it and exports
it, so apps that already use `dostr_core` don't need to add it.

## Install

```yaml
dependencies:
  dostr_signer: ^0.1.0
```

## Usage

Code that signs takes any `EventSigner`:

```dart
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

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

To write a signer, implement `EventSigner`, and `LocalEventSignerFactory` if
the Dostr packages should create it from a private key.

## Accounts and authentication

- `Account`: a pubkey and the `EventSigner` that signs for it.
- `AuthAccounts`: where the logged-in account comes from, implemented by
  `Accounts` from [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).
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

`EventSigner`, `LocalEventSignerFactory`, `PendingSignerRequest`, the two
exceptions and `ConcurrencyLimiterMixin` used to be in `ndk`. What changed is
in the [`dostr_core` changelog](https://pub.dev/packages/dostr_core/changelog).

`package:ndk/domain_layer/entities/account.dart`, `auth_policy.dart`,
`auth_handler.dart` and `package:ndk/domain_layer/repositories/auth_accounts.dart`
are now `package:dostr_signer/dostr_signer.dart`, which
`package:dostr_core/dostr_core.dart` exports too. `TimeoutPausable`, which was in
`auth_handler.dart`, is in `dostr_core` instead, in
`package:dostr_core/domain_layer/entities/timeout_pausable.dart`.
