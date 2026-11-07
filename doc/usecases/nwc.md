---
icon: plug
---
[!badge variant="primary" text="high level"]

## Setup

NWC lives in the `ndk_nwc` package.

```yaml
dependencies:
  ndk_nwc: ^0.1.0
```

It does not depend on `ndk`: `Nwc` takes callbacks to query, subscribe and publish on the relays, here wired to an NDK instance. Its lifecycle hooks make `ndk.destroy()` close every connection and `ndk.setBackgrounded(true)` pause idle notifications.

:::code source="../../packages/nwc/example/nwc_for_ndk.dart" language="dart" title="build Nwc from an NDK instance" :::

## Example

:::code source="../../packages/nwc/example/get_balance.dart" language="dart" range="13-22" title="connect, get balance" :::

:::code source="../../packages/nwc/example/pay_invoice.dart" language="dart" range="22-22" title="pay invoice" :::


:::code source="../../packages/nwc/example/notifications.dart" language="dart" range="17-23" title="notifications" :::

## How to use

You need a `nostr+walletconnect://...` uri from your NWC wallet service provider.

`NwcConnection.supportedExtensions` lists recognized extension identifiers from
the wallet's info event. It includes `NwcExtension.lookupPayment` (`09`) and
`NwcExtension.bolt12` (`12`) when the wallet advertises them. Unknown identifiers
are ignored.

see https://github.com/getAlby/awesome-nwc for more info how to get a wallet supporting NWC
