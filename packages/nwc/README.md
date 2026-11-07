<img src="https://framerusercontent.com/assets/zipB5Tdnkw0u2uMIStFerslkTa4.png" width="300px" />

Nostr Wallet Connect implementation for dart NDK.
https://nwc.dev

It does not depend on `ndk`: it asks you how to reach the relays.

## Resources
- https://github.com/getAlby/awesome-nwc for more info how to get a wallet supporting NWC
- https://github.com/nostr-protocol/nips/blob/master/47.md for protocol spec 

## Install

```yaml
dependencies:
  ndk: ^0.11.0-dev.2
  ndk_nwc: ^0.1.0
```

## Usage

```dart
import 'dart:io';
import 'package:ndk/ndk.dart';
import 'package:ndk_nwc/ndk_nwc.dart';

final ndk = Ndk.emptyBootstrapRelaysConfig();
final nwc = Nwc(
  query: (filter, {required relays, required timeout, onTimeout}) => ndk
      .requests
      .query(
        filter: filter,
        explicitRelays: relays,
        timeout: timeout,
        timeoutCallback: onTimeout,
        cacheRead: false,
        cacheWrite: false,
      )
      .future,
  subscribe: (filter, {required relays}) {
    final response = ndk.requests.subscription(
      filter: filter,
      explicitRelays: relays,
    );
    return (
      events: response.stream,
      sent: (timeout) =>
          ndk.relays.waitForRequestSent(response.requestId, timeout),
      close: () => ndk.requests.closeSubscription(response.requestId),
    );
  },
  publish: (event, {required relays, required signer}) => ndk.broadcast
      .broadcast(
        nostrEvent: event,
        specificRelays: relays,
        customSigner: signer,
        retryDelivery: false,
        saveToCache: false,
      )
      .broadcastDoneFuture,
  eventSignerFactory: ndk.config.eventSignerFactory,
  zaps: ndk.zaps,
);
ndk.addLifecycleHooks(
  onBackgrounded: nwc.setBackgrounded,
  onDestroy: nwc.disconnectAll,
);

final connection = await nwc.connect(Platform.environment['NWC_URI']!);

final balanceResponse = await nwc.getBalance(connection);
print("Balance: ${balanceResponse.balanceSats} sats");

final makeInvoice = await nwc.makeInvoice(connection, amountSats: 100);
print("paying ${makeInvoice.amountSat} sats invoice: ${makeInvoice.invoice}");

final payInvoice = await nwc.payInvoice(connection, invoice: makeInvoice.invoice);
print("preimage: ${payInvoice.preimage}");

// also closes every NWC connection, through the lifecycle hooks
await ndk.destroy();
```

`query` loads the wallet's info event, `subscribe` listens to its responses and notifications, and `publish` signs a request with the connection's key and sends it. None of them touch the cache, and a request is never retried later: it expires with its caller. `sent` waits until a subscription's REQ went out, so a request is only published once its response can be received. `setBackgrounded` pauses idle notifications and `disconnectAll` closes every connection.

`nwc.zap(...)` pays a zap through a connection and needs `zaps`. `NwcWalletProvider(nwc)` plugs NWC into `Wallets` from [ndk_wallets](../wallets/).

More in [example/](example/), where [nwc_for_ndk.dart](example/nwc_for_ndk.dart) builds `Nwc` from an NDK instance.
