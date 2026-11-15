# dostr_signer

The `NostrSigner` interface that Dostr signers implement, whether they hold the key (`Bip340Signer`), ask a remote bunker (NIP-46), a browser extension (NIP-07) or a signer app (NIP-55).
It comes with `LocalSignerFactory`, the `PendingSignerRequest` that interactive signers expose while they wait for the user, and the `SignerRequestRejectedException` and `SignerRequestCancelledException` they throw.

It also holds the accounts the Dostr packages may authenticate as, and what decides when one is revealed: to a relay that asks for NIP-42 authentication, or to a Blossom server.

Pure Dart, interfaces only.
A signer such as [`dostr_bip340`](https://pub.dev/packages/dostr_bip340) needs this package and [`dostr_nip01`](https://pub.dev/packages/dostr_nip01), not `dostr_core`.
So does a package that authenticates on behalf of Dostr accounts, such as [`dostr_blossom`](https://pub.dev/packages/dostr_blossom).

[`dostr_core`](https://pub.dev/packages/dostr_core) depends on it and exports it, so apps that already use `dostr_core` don't need to add it.

## Install

```yaml
dependencies:
  dostr_signer: ^0.1.0
```

## Usage

Code that signs takes any `NostrSigner`:

```dart
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

Future<Nip01Event?> signNote(NostrSigner signer, String text) async {
  try {
    return await signer.sign(
      Nip01Event(
        pubkey: signer.getPublicKey(),
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

An interactive signer lists what waits for the user in `pendingRequests` and `pendingRequestsStream`, and `cancelRequest` drops one.
A local signer always has an empty list.
`ConcurrencyLimiterMixin` caps how many requests an interactive signer sends at once and queues the rest.

To write a signer, implement `NostrSigner`, and `LocalSignerFactory` if the Dostr packages should create it from a private key.

## Signers

| Type | Package | Description | Pending requests |
|------|---------|-------------|------------------|
| `Bip340Signer` | [`dostr_bip340`](https://pub.dev/packages/dostr_bip340) | Local signer with the private key, pure Dart | No (instant) |
| `Nip46Signer` | [`dostr_nip46`](https://pub.dev/packages/dostr_nip46) | Remote signer through a NIP-46 bunker | Yes |
| `Nip07Signer` | [`dostr_nip07`](https://pub.dev/packages/dostr_nip07) | Browser extension (NIP-07) | Yes |
| `Nip55Signer` | [`dostr_nip55`](https://pub.dev/packages/dostr_nip55) | Android signer app (NIP-55), Flutter plugin | Yes |

To keep several accounts and switch between them, see [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).

## Pending requests

External signers (NIP-46, NIP-07, NIP-55) wait for the user to approve each operation.
Read what waits on the signer, or on the `Account` that holds it:

```dart
signer.pendingRequestsStream.listen((requests) {
  for (final request in requests) {
    print('${request.method.protocolString} (${request.id})');
  }
});

// synchronous snapshot
final current = account.pendingRequests;
```

A `PendingSignerRequest` holds:

```dart
class PendingSignerRequest {
  final String id;
  final SignerMethod method;          // signEvent, nip44Encrypt, etc.
  final DateTime createdAt;
  final String signerPubkey;
  final Nip01Event? event;            // for signEvent
  final String? plaintext;            // for encrypt
  final String? ciphertext;           // for decrypt
  final String? counterpartyPubkey;   // for encrypt and decrypt

  String? get content;                // plaintext or ciphertext
}
```

`account.cancelRequest(requestId)` drops one, and the caller receives a `SignerRequestCancelledException`.
When the user rejects a request on the remote signer, the caller receives a `SignerRequestRejectedException`.

A Flutter list of the pending requests, with a cancel button on each:

```dart
StreamBuilder<List<PendingSignerRequest>>(
  stream: account.pendingRequestsStream,
  builder: (context, snapshot) {
    final requests = snapshot.data ?? [];
    if (requests.isEmpty) return Text('No pending requests');

    return ListView.builder(
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final request = requests[index];
        return ListTile(
          title: Text(request.method.protocolString),
          subtitle: Text('Created ${request.createdAt}'),
          trailing: IconButton(
            icon: Icon(Icons.cancel),
            onPressed: () => account.cancelRequest(request.id),
          ),
        );
      },
    );
  },
)
```

Dispose a signer, or the account that holds it, when done: `await account.dispose()`.

## Accounts and authentication

- `Account`: a pubkey and the `NostrSigner` that signs for it.
- `AuthAccounts`: where the logged-in account comes from, implemented by `Accounts` from [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).
- `AuthPolicy`: what one operation may reveal. `never()` stays anonymous, `allow(account)` authenticates when asked, `require(account)` authenticates upfront and fails if it cannot.
- `AuthHandler`: asked before a pubkey is revealed on a url. Answering false keeps it from being revealed there.

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

`PendingSignerRequest`, the two exceptions and `ConcurrencyLimiterMixin` used to be in `ndk`, and so did `NostrSigner` and `LocalSignerFactory`, as `EventSigner` and `LocalEventSignerFactory`.
What changed is in the [`dostr_core` changelog](https://pub.dev/packages/dostr_core/changelog).

`package:ndk/domain_layer/entities/account.dart`, `auth_policy.dart`, `auth_handler.dart` and `package:ndk/domain_layer/repositories/auth_accounts.dart` are now `package:dostr_signer/dostr_signer.dart`, which `package:dostr_core/dostr_core.dart` exports too.
`TimeoutPausable`, which was in `auth_handler.dart`, is in `package:dostr_core/dostr_core.dart` instead.
