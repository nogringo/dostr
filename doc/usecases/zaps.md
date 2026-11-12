---
icon: zap
---

# Zaps

[`dostr_zaps`](https://pub.dev/packages/dostr_zaps) handles [NIP-57](https://github.com/nostr-protocol/nips/blob/master/57.md) zaps: it creates zap requests, fetches the invoice to pay from a lightning address ([LUD-06](https://github.com/lnurl/luds/blob/luds/06.md), [LUD-16](https://github.com/lnurl/luds/blob/luds/16.md)) and reads zap receipts. Paying the invoice is up to your wallet.

```yaml
dependencies:
  dostr_zaps: ^0.1.0
  dostr_core: ^0.11.0-dev.2
  dostr_bip340: ^0.1.0
  http: ^1.6.0
```

## Setup

`Zaps` takes how to query and subscribe to relays, and an `Lnurl` to talk to the lightning address server. Here both run on [RelayReqs](/usecases/relay-reqs.md):

:::code source="../../packages/zaps/example/dostr_zaps_example.dart" language="dart" range="13-44" title="" :::

`query` streams the events relays hold for a filter and ends once they are done or the timeout runs out. `subscribe` opens a live subscription and returns its events and a `close` to end it.

## Invoice

:::code source="../../packages/zaps/example/dostr_zaps_example.dart" language="dart" range="53-68" title="zap request and invoice" :::

`fetchInvoice` encodes the zap request in the invoice only when the LNURL server allows Nostr and the request is signed. Without a zap request it returns a plain lightning invoice. Pass `eventId` or `addressableId` to `createZapRequest` to zap an event, and `comment` for a message.

## Receipts

:::code source="../../packages/zaps/example/dostr_zaps_example.dart" language="dart" range="46-50" title="receipts for a profile" :::

`fetchZappedReceipts` and `subscribeToZapReceipts` match the receipts (kind `9735`) by recipient, and by event or addressable event when given:

```dart receipts for an event
final receipts =
    await zaps.fetchZappedReceipts(pubKey: author, eventId: eventId).toList();

final live = zaps.subscribeToZapReceipts(pubKey: author, eventId: eventId);
live.events.listen((event) => print(ZapReceipt.fromEvent(event).amountSats));
await live.close();
```

The receipts are parsed, not verified. `receipt.isValid(nostrPubKey: ..., recipientLnurl: ...)` checks one against the `nostrPubkey` of the recipient's LNURL server, which `getLnurlResponse(link)` of your `Lnurl` returns. Per NIP-57 this proves the receipt came from that server, not that the payment happened.
