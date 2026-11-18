# dostr_zaps

[NIP-57](https://github.com/nostr-protocol/nips/blob/master/57.md) zaps for Nostr: create zap requests, fetch the invoice to pay from a lightning address ([LUD-06](https://github.com/lnurl/luds/blob/luds/06.md), [LUD-16](https://github.com/lnurl/luds/blob/luds/16.md)), and read zap receipts.
Paying the invoice is up to your wallet.

## Standalone

```yaml
dependencies:
  dostr_zaps: ^0.1.0
  dostr_bip340: ^0.1.0
  dostr_relay_url: ^0.1.0
  http: ^1.6.0
```

```dart
import 'package:http/http.dart' as http;
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_zaps/dostr_zaps.dart';

final lnurl = Lnurl(transport: HttpLnurlTransport(http.Client()));
final zaps = Zaps(
  query: (filter, {required timeout}) => myRelays.query(filter, timeout),
  subscribe: (filter) {
    final sub = myRelays.subscribe(filter);
    return (events: sub.events, close: sub.close);
  },
  lnurl: lnurl,
);

final lud16Link = Lnurl.getLud16LinkFromLud16('name@domain.com')!;
final zapRequest = await zaps.createZapRequest(
  amountSats: 21,
  signer: Bip340Signer(key.privateKey),
  pubkey: recipient,
  relays: [RelayUrl.parse('wss://relay.example.com')],
);
final invoice = await zaps.fetchInvoice(
  lud16Link: lud16Link,
  amountSats: 21,
  zapRequest: zapRequest,
);

final server = await lnurl.getLnurlResponse(lud16Link);
final receipts = await zaps
    .fetchZappedReceipts(pubkey: recipient, nostrPubkey: server!.nostrPubkey!)
    .toList();
```

`query` streams the events relays hold for a filter, with their signatures verified, and ends once they are done or the timeout runs out.
`subscribe` opens a live subscription to a filter and returns its events, with their signatures verified, and a `close` to end it.
`lnurl` fetches the LNURL-pay metadata and the invoices, `HttpLnurlTransport` does it over HTTPS.

`fetchInvoice` encodes the zap request in the invoice only when the LNURL server allows Nostr and the request is signed.
Without a zap request it returns a plain lightning invoice.
Pass `eventId` or `addressableId` to `createZapRequest` to zap an event, and `comment` for a message.

More in [example/](example/), which runs `query` and `subscribe` on the `RelayReqs` of [`dostr_core`](https://pub.dev/packages/dostr_core).

## Receipts

`fetchZappedReceipts` and `subscribeToZapReceipts` give the valid receipts (kind `9735`) of the zaps to a recipient, and to an event or addressable event when given:

```dart
final receipts = await zaps
    .fetchZappedReceipts(
      pubkey: author,
      nostrPubkey: nostrPubkey,
      eventId: eventId,
    )
    .toList();

final live = zaps.subscribeToZapReceipts(
  pubkey: author,
  nostrPubkey: nostrPubkey,
);
live.receipts.listen((receipt) => print(receipt.amountSats));
await live.close();
```

`nostrPubkey` is the `nostrPubkey` of the recipient's LNURL server, which `getLnurlResponse(link)` of your `Lnurl` returns.
Only the receipts it signed are asked for, and only those that pass `ZapReceipt.isValid`, the checks of NIP-57, come out:

- The receipt names the recipient of the zap request it carries.
- The invoice has the amount of the zap request, to the millisat.
- The `lnurl` of the zap request is the recipient's, when you pass it as `recipientLnurl`.

Per NIP-57 this proves the receipt came from that server, not that the payment happened.
Receipts from a server the recipient used before no longer pass.
`ZapReceipt.isValid` trusts the pubkey of the event, so `query` and `subscribe` must verify the signatures, as `RelayReqs` of `dostr_core` does.

`ZapReceipt.fromEvent(event)` reads a receipt without checking it, and `bolt11AmountMsats(invoice)` reads the amount of an invoice.

## Coming from `ndk`

`Zaps`, `ZapRequest`, `ZapReceipt`, `InvoiceResponse`, `Lnurl` and `LnurlResponse` keep their names, and `LnurlTransportHttpImpl` is now `HttpLnurlTransport`.
The deep imports under `package:ndk/domain_layer/usecases/zaps/`, `package:ndk/domain_layer/usecases/lnurl/`, `package:ndk/domain_layer/repositories/lnurl_transport.dart` and `package:ndk/data_layer/repositories/lnurl_http_impl.dart` are now `package:dostr_zaps/dostr_zaps.dart`.
`Zaps` takes `query` and `subscribe` instead of `requests`.
`fetchZappedReceipts` and `subscribeToZapReceipts` take the `nostrPubkey` of the recipient's LNURL server, and give only the receipts that pass `ZapReceipt.isValid`.
`subscribeToZapReceipts` returns a `ZapReceiptsSubscription` instead of an `NdkResponse`: read the `ZapReceipt`s of `receipts` instead of the events of `stream`, and call `close()` instead of `ndk.requests.closeSubscription(response.requestId)`.
`Lnurl.getAmountFromBolt11(bolt11)` is now `bolt11AmountMsats(bolt11)`, in millisats, and null rather than 0 for an invoice it cannot read.
`ZapReceipt`, `LnurlResponse` and `InvoiceResponse` are immutable.
