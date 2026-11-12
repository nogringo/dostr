# NIP-42 Authentication

The `RelayManager` of [`dostr_core`](https://pub.dev/packages/dostr_core) handles NIP-42 relay authentication: when a relay requires it, it signs and sends the AUTH event, then retries the original request.

A connection carries at most one identity, chosen when it is opened and immutable for its whole lifetime, so a request that authenticates moves to its own connection.

## Which identity

Each REQ and EVENT says which identity it may be attributed to with an `AuthPolicy`, from `dostr_signer`:

- `AuthPolicy.never()` stays on the anonymous connection and never sends AUTH. A relay that refuses the request without an identity does not serve it.
- `AuthPolicy.allow(account)` starts anonymous and moves to a connection bound to `account` only once a relay refused the request without an identity.
- `AuthPolicy.require(account)` goes out on a connection bound to `account` from the start.

```dart
final req = reqs.req(
  relays: {'wss://private.example.com': [filter]},
  auth: AuthPolicy.allow(account),
);
```

[Relay REQs](/usecases/relay-reqs.md), [Relay publishes](/usecases/relay-publishes.md) and [Negentropy](/usecases/negentropy.md) all take `auth`.

Without `auth`, a request authenticates as the account the `RelayManager` gets from its `accounts`, an `AuthAccounts` such as `Accounts` from [`dostr_accounts`](/usecases/accounts.md), and only where the `AuthHandler` agrees.

## AuthHandler

Asked before a pubkey authenticates on a relay or a Blossom server. Without one, a request that does not pass `auth` reveals no identity.

```dart
final relays = RelayManager(
  nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  accounts: accounts,
  authHandler: (url, pubkey) => askUser(url, pubkey),
);
```

- `never()` is never asked about. `allow(a)`, `require(a)` and a request without `auth` authenticate only where the handler returns true.
- `require` asks before sending, so a relay or server it refuses receives nothing. The rest asks once a relay or server refused.
- A relay is asked when a connection bound to that pubkey opens, a Blossom server once per operation.
- The time spent waiting on the handler does not count against the request timeout.

`authHandler: (_, _) async => true` authenticates as the logged-in account wherever asked.
