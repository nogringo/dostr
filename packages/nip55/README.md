# dostr_nip55

[NIP-55](https://github.com/nostr-protocol/nips/blob/master/55.md) signing for Nostr on Android: log in with a signer app installed on the device, then sign events and encrypt or decrypt NIP-04 and NIP-44 messages through it.

It implements the `EventSigner` of [`dostr_signer`](https://pub.dev/packages/dostr_signer), so Dostr accounts can use it. It is a Flutter plugin for Android and does not depend on `dostr_flutter`.

## With `dostr_flutter`

`dostr_flutter` depends on this package and exports it. Its `NLogin` widget offers the signer app login, and `NdkFlutter` saves and restores these accounts.

## Standalone

```yaml
dependencies:
  dostr_nip55: ^0.1.0
```

```dart
import 'package:dostr_nip55/dostr_nip55.dart';

const nip55Signer = Nip55Signer();
if (await nip55Signer.isAppInstalled()) {
  final login = await nip55Signer.login();
  if (login != null) {
    final signer = Nip55EventSigner(
      publicKey: login.pubkey,
      nip55Signer: Nip55Signer(package: login.package),
    );
    accounts.loginExternalSigner(signer: signer);
  }
}
```

`accounts` is an `Accounts` from [`dostr_accounts`](https://pub.dev/packages/dostr_accounts).

`login()` asks the signer app for the user's public key and pre-authorizes `Nip55Signer.defaultPermissions`, so later requests can be answered silently, without opening the signer app. Pass your own list of `Nip55Permission` to ask for other ones. Keep `login.package` and pass it to `Nip55Signer(package:)`: requests then go straight to the same signer app.

The signer app may ask the user to approve each request. While it waits, the request is in `pendingRequests` and `pendingRequestsStream`, and `cancelRequest` drops it. A refusal throws a `SignerRequestRejectedException`. At most `maxConcurrentRequests` requests (100 by default) go out at once. The rest wait in a queue.

On other platforms than Android, the plugin is not registered and every call throws a `MissingPluginException`.

## Coming from `ndk_flutter`

The classes keep their names. `package:ndk_flutter/ndk_flutter.dart` is now `package:dostr_flutter/dostr_flutter.dart`, which still exports them. The deep imports `package:ndk_flutter/data_layer/data_sources/nip55_signer.dart` and `package:ndk_flutter/data_layer/repositories/signers/nip55_event_signer.dart` are now `package:dostr_nip55/dostr_nip55.dart`. The method channel is now `dostr_nip55` instead of `ndk`.
