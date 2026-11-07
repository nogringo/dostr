---
icon: plug
---
[!badge variant="primary" text="high level"]

## Setup

NDK exposes NWC as `ndk.nwc`. `ndk.destroy()` closes every connection and `ndk.setBackgrounded(true)` pauses idle notifications.

`Nwc` lives in the `ndk_nwc` package, which `ndk` depends on and re-exports. It does not depend on `ndk`: without it, build `Nwc` with callbacks to query, subscribe and publish on the relays, see its [README](https://pub.dev/packages/ndk_nwc).

## Example

:::code source="../../packages/nwc/example/get_balance.dart" language="dart" range="10-19" title="connect, get balance" :::

:::code source="../../packages/nwc/example/pay_invoice.dart" language="dart" range="20-20" title="pay invoice" :::


:::code source="../../packages/nwc/example/notifications.dart" language="dart" range="15-21" title="notifications" :::

## How to use

You need a `nostr+walletconnect://...` uri from your NWC wallet service provider.

`NwcConnection.supportedExtensions` lists recognized extension identifiers from
the wallet's info event. It includes `NwcExtension.lookupPayment` (`09`) and
`NwcExtension.bolt12` (`12`) when the wallet advertises them. Unknown identifiers
are ignored.

see https://github.com/getAlby/awesome-nwc for more info how to get a wallet supporting NWC
