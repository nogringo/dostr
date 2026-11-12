# dostr_zaps

The zaps of [NDK](https://pub.dev/packages/ndk) ([NIP-57](https://github.com/nostr-protocol/nips/blob/master/57.md)): create zap requests, fetch the invoice to pay from a lightning address ([LUD-06](https://github.com/lnurl/luds/blob/luds/06.md), [LUD-16](https://github.com/lnurl/luds/blob/luds/16.md)), and read zap receipts. It does not depend on `ndk`.

## With NDK

`ndk` depends on this package, re-exports it and exposes it as `ndk.zaps` and `ndk.lnurl`:

```dart
import 'package:ndk/ndk.dart';

final invoice = await ndk.zaps.fetchInvoice(
  lud16Link: Lnurl.getLud16LinkFromLud16('name@domain.com')!,
  amountSats: 21,
);
final receipts = await ndk.zaps.fetchZappedReceipts(pubKey: pubkey).toList();
```

Paying goes through a wallet: `Nwc.zap(...)` from [`ndk_nwc`](https://pub.dev/packages/ndk_nwc) fetches the invoice, pays it and waits for the receipt.

## Standalone

```yaml
dependencies:
  dostr_zaps: ^0.1.0
  dostr_bip340: ^0.1.0
  http: ^1.6.0
```

```dart
import 'package:http/http.dart' as http;
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_zaps/dostr_zaps.dart';

final zaps = Zaps(
  query: (filter, {required timeout}) => myRelays.query(filter, timeout),
  subscribe: (filter) {
    final sub = myRelays.subscribe(filter);
    return (events: sub.events, close: sub.close);
  },
  lnurl: Lnurl(transport: LnurlTransportHttpImpl(http.Client())),
);

final zapRequest = await zaps.createZapRequest(
  amountSats: 21,
  signer: Bip340EventSigner(privateKey: key.privateKey, publicKey: key.publicKey),
  pubKey: recipient,
  relays: ['wss://relay.example.com'],
);
final invoice = await zaps.fetchInvoice(
  lud16Link: Lnurl.getLud16LinkFromLud16('name@domain.com')!,
  amountSats: 21,
  zapRequest: zapRequest,
);

final receipts = await zaps.fetchZappedReceipts(pubKey: recipient).toList();
```

`query` streams the events relays hold for a filter and ends once they are done or the timeout runs out. `subscribe` opens a live subscription to a filter and returns its events and a `close` to end it. `lnurl` fetches the LNURL-pay metadata and the invoices, `LnurlTransportHttpImpl` does it over HTTPS.

`fetchInvoice` encodes the zap request in the invoice only when the LNURL server allows Nostr and the request is signed. Without a zap request it returns a plain lightning invoice. `fetchZappedReceipts` and `subscribeToZapReceipts` match the receipts (kind 9735) by recipient, and by event or addressable event when given.

More in [example/](example/) and the [zaps docs](https://dart-nostr.com/usecases/zaps/).

## Coming from `ndk`

`Zaps`, `ZapRequest`, `ZapReceipt`, `InvoiceResponse`, `Lnurl` and `LnurlResponse` keep their names, and `package:ndk/ndk.dart` still exports them. The deep imports under `package:ndk/domain_layer/usecases/zaps/`, `package:ndk/domain_layer/usecases/lnurl/`, `package:ndk/domain_layer/repositories/lnurl_transport.dart` and `package:ndk/data_layer/repositories/lnurl_http_impl.dart` are now `package:dostr_zaps/dostr_zaps.dart`. `Zaps` takes `query` and `subscribe` instead of `requests`. `subscribeToZapReceipts` returns a `ZapsSubscription` instead of an `NdkResponse`: read `events` instead of `stream`, and call `close()` instead of `ndk.requests.closeSubscription(response.requestId)`.
