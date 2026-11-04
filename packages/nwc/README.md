<img src="https://framerusercontent.com/assets/zipB5Tdnkw0u2uMIStFerslkTa4.png" width="300px" />

Nostr Wallet Connect implementation for dart NDK.
https://nwc.dev

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
final nwc = Nwc(ndk);

final connection = await nwc.connect(Platform.environment['NWC_URI']!);

final balanceResponse = await nwc.getBalance(connection);
print("Balance: ${balanceResponse.balanceSats} sats");

final makeInvoice = await nwc.makeInvoice(connection, amountSats: 100);
print("paying ${makeInvoice.amountSat} sats invoice: ${makeInvoice.invoice}");

final payInvoice = await nwc.payInvoice(connection, invoice: makeInvoice.invoice);
print("preimage: ${payInvoice.preimage}");

// also closes every NWC connection
await ndk.destroy();
```

`nwc.zap(...)` pays a zap through a connection, and `NwcWalletProvider(nwc)` plugs NWC into `Wallets` from [ndk_wallets](../wallets/).

More in [example/](example/).
