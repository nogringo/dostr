# ndk_auth

The accounts NDK may authenticate as, and what decides when one is revealed:
to a relay that asks for NIP-42 authentication, or to a Blossom server.

- `Account`: a pubkey and the `EventSigner` that signs for it.
- `AuthAccounts`: where the logged-in account comes from, implemented by
  `ndk`'s `Accounts`.
- `AuthPolicy`: what one operation may reveal. `never()` stays anonymous,
  `allow(account)` authenticates when asked, `require(account)` authenticates
  upfront and fails if it cannot.
- `AuthHandler`: asked before a pubkey is revealed on a url. Answering false
  keeps it from being revealed there.

Depends only on [`ndk_signer`](https://pub.dev/packages/ndk_signer). A package
that authenticates on behalf of NDK accounts, such as
[`ndk_blossom`](https://pub.dev/packages/ndk_blossom), only needs this
package, not `ndk_core`.

## Install

```yaml
dependencies:
  ndk_auth: ^0.1.0
```

## Usage

```dart
import 'package:ndk_auth/ndk_auth.dart';

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

## Coming from `ndk` or `ndk_core`

`package:ndk_core/domain_layer/entities/account.dart`, `auth_policy.dart`,
`auth_handler.dart` and `package:ndk_core/domain_layer/repositories/auth_accounts.dart`
are now `package:ndk_auth/ndk_auth.dart`. `package:ndk/ndk.dart` and
`package:ndk_core/ndk_core.dart` still export it. `TimeoutPausable` stays in
`ndk_core`, in `package:ndk_core/domain_layer/entities/timeout_pausable.dart`.
