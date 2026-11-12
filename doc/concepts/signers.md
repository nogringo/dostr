# Signers

A signer signs events and encrypts and decrypts messages. Every signer implements `EventSigner` from [`dostr_signer`](https://pub.dev/packages/dostr_signer), so code that signs takes any of them.

## Signer types

| Type | Package | Description | Pending requests |
|------|---------|-------------|------------------|
| `Bip340EventSigner` | `dostr_bip340` | Local signer with the private key, pure Dart | No (instant) |
| `Nip46EventSigner` | `dostr_nip46` | Remote signer through a NIP-46 bunker | Yes |
| `Nip07EventSigner` | `dostr_nip07` | Browser extension (NIP-07) | Yes |
| `Nip55EventSigner` | `dostr_nip55` | Android signer app (NIP-55), Flutter plugin | Yes |

To keep several accounts and switch between them, see [Accounts](/usecases/accounts.md).

## Pending requests

External signers (NIP-46, NIP-07, NIP-55) wait for the user to approve each operation. The pending requests API lets your UI:

- Display pending operations to the user
- Cancel pending requests
- React to request completion

### Listening to pending requests

Read them on the signer, or on the `Account` that holds it:

```dart
signer.pendingRequestsStream.listen((requests) {
  print('${requests.length} pending request(s)');
  for (final request in requests) {
    print('- ${request.method.protocolString} (${request.id})');
  }
});

// synchronous snapshot
final current = account.pendingRequests;
```

### PendingSignerRequest properties

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

### Cancelling requests

```dart
final cancelled = account.cancelRequest(requestId);
```

The caller then receives a `SignerRequestCancelledException`. When the user rejects a request on the remote signer (bunker, browser extension, signer app), the caller receives a `SignerRequestRejectedException`:

```dart
try {
  await signer.sign(event);
} on SignerRequestRejectedException catch (e) {
  print('rejected on the remote signer: ${e.requestId}');
} on SignerRequestCancelledException catch (e) {
  print('cancelled locally: ${e.requestId}');
}
```

| Exception | When thrown |
|-----------|-------------|
| `SignerRequestCancelledException` | `cancelRequest()` called locally |
| `SignerRequestRejectedException` | User rejected on remote signer |

## UI example

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

## Disposing

Dispose a signer, or the account that holds it, when done:

```dart
await account.dispose();
```

## Writing a signer

Implement `EventSigner`, and `LocalEventSignerFactory` if it can be created from a private key. `ConcurrencyLimiterMixin` caps how many requests an interactive signer sends at once and queues the rest.
