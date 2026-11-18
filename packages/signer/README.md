# dostr_signer

The `NostrSigner` interface that Dostr signers implement, whether they hold the key (`Bip340Signer`), ask a remote bunker (NIP-46), a browser extension (NIP-07) or a signer app (NIP-55).
It comes with `LocalSignerFactory`, the `PendingSignerRequest` that interactive signers expose while they wait for the user, and the `SignerRequestRejectedException`, `SignerRequestCancelledException` and `SignerRequestFailedException` they throw, all a `SignerRequestException`.

It also holds the accounts the Dostr packages may authenticate as, and what decides when one is revealed: to a relay that asks for NIP-42 authentication, or to a Blossom server.

Pure Dart: interfaces, and the `ConcurrencyLimiterMixin` that interactive signers share.
A signer such as [`dostr_bip340`](https://pub.dev/packages/dostr_bip340) needs this package and [`dostr_nip01`](https://pub.dev/packages/dostr_nip01), not `dostr_core`.
So does a package that authenticates on behalf of Dostr accounts, such as [`dostr_blossom`](https://pub.dev/packages/dostr_blossom).

[`dostr_core`](https://pub.dev/packages/dostr_core) depends on it and exports it, so apps that already use `dostr_core` don't need to add it.

## Install

```yaml
dependencies:
  dostr_signer: ^0.2.0
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
        pubkey: signer.publicKey,
        kind: Nip01Event.kTextNoteKind,
        tags: [],
        content: text,
      ),
    );
  } on SignerRequestException {
    return null; // rejected, cancelled, or no valid result came back
  }
}
```

`encryptNip44` and `decryptNip44` work the same way: they complete with the text, or throw.
A `SignerRequestRejectedException` means the signer turned the request down, a `SignerRequestCancelledException` that `cancelRequest` dropped it, and a `SignerRequestFailedException` that no valid result came back, such as a ciphertext that does not decrypt or an event signed by another pubkey.

A signer knows its pubkey from the moment it exists, so `publicKey` never throws: an interactive signer asks for it before it is created, as `Nip07Signer.connect()` does.
`sign` takes an event of that pubkey, and the event it returns has that pubkey too, although an interactive signer may change other fields before it signs.
Misusing a signer throws an `Error` instead of a `SignerRequestException`: `sign` with an event of another pubkey throws an `ArgumentError`, and a signer whose `canSign` is false throws from every operation.

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
Read what waits on the signer:

```dart
signer.pendingRequestsStream.listen((requests) {
  for (final request in requests) {
    print('${request.id} waits since ${request.createdAt}');
  }
});

// synchronous snapshot
final current = signer.pendingRequests;
```

A `PendingSignerRequest` has an `id`, a `createdAt` and the `signerPubkey` it waits on.
It is a sealed class, with what each request waits for:

```dart
final details = switch (request) {
  PendingSignRequest(:final event) => 'kind ${event.kind}',
  PendingEncryptRequest(:final scheme, :final plaintext, :final recipientPubkey) =>
    '${scheme.name} encrypt for $recipientPubkey: $plaintext',
  PendingDecryptRequest(:final scheme, :final ciphertext, :final senderPubkey) =>
    '${scheme.name} decrypt from $senderPubkey: $ciphertext',
};
```

The `scheme` of an encryption or a decryption, an `EncryptionScheme`, tells NIP-04 from NIP-44.
Only what the user approves waits there: a NIP-46 ping, for example, does not.

`signer.cancelRequest(requestId)` drops one, and the caller receives a `SignerRequestCancelledException`.
When the user rejects a request on the remote signer, the caller receives a `SignerRequestRejectedException`.

A Flutter list of the pending requests, with a cancel button on each:

```dart
StreamBuilder<List<PendingSignerRequest>>(
  stream: signer.pendingRequestsStream,
  builder: (context, snapshot) {
    final requests = snapshot.data ?? [];
    if (requests.isEmpty) return Text('No pending requests');

    return ListView.builder(
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final request = requests[index];
        return ListTile(
          title: Text(switch (request) {
            PendingSignRequest() => 'Sign',
            PendingEncryptRequest() => 'Encrypt',
            PendingDecryptRequest() => 'Decrypt',
          }),
          subtitle: Text('Created ${request.createdAt}'),
          trailing: IconButton(
            icon: Icon(Icons.cancel),
            onPressed: () => signer.cancelRequest(request.id),
          ),
        );
      },
    );
  },
)
```

Dispose a signer when done: `await signer.dispose()`.

## Accounts and authentication

- `AuthAccounts`: the accounts a request may authenticate as, each one the `NostrSigner` of its pubkey, and the logged-in one. `Accounts` from [`dostr_accounts`](https://pub.dev/packages/dostr_accounts) implements it.
- `AuthPolicy`: what one operation may reveal. `never()` stays anonymous, `allow(signer)` authenticates when asked, `require(signer)` authenticates upfront and fails if it cannot.
- `AuthHandler`: asked before a pubkey is revealed on a url. Answering false keeps it from being revealed there.

```dart
final policy = AuthPolicy.allow(signer);

Future<bool> onlyMyRelay(String url, String pubkey) async =>
    url == 'wss://relay.example.com';
```

## Coming from `ndk`

`PendingSignerRequest`, the `SignerRequestRejectedException` and `SignerRequestCancelledException` and `ConcurrencyLimiterMixin` used to be in `ndk`, and so did `NostrSigner` and `LocalSignerFactory`, as `EventSigner` and `LocalEventSignerFactory`.
What changed is in [Coming from `ndk`](https://github.com/nogringo/dostr/blob/master/doc/coming-from-ndk.md).

`package:ndk/domain_layer/entities/auth_policy.dart`, `auth_handler.dart` and `package:ndk/domain_layer/repositories/auth_accounts.dart` are now `package:dostr_signer/dostr_signer.dart`, which `package:dostr_core/dostr_core.dart` exports too.
`Account`, from `account.dart`, is gone: an account is its `NostrSigner`, which `AuthPolicy` takes and `AuthAccounts` returns.
`TimeoutPausable`, which was in `auth_handler.dart`, is in `package:dostr_core/dostr_core.dart` instead.
