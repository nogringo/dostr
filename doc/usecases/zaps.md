---
icon: zap
---

[!badge variant="primary" text="high level"]

[!badge text="CLI"](/guides/cli/zaps.md) — `ndk zaps invoice|zap|receipts`

## Example

Paying a zap goes through a wallet: with NWC, `Nwc.zap(...)` from the `ndk_nwc` package fetches the invoice, pays it and waits for the receipt. Without a wallet, `ndk.zaps.fetchInvoice(...)` returns the invoice to pay.

:::code source="../../packages/nwc/example/zap.dart" language="dart" range="13-53" title="zap, receipt" :::

:::code source="../../packages/ndk/example/zaps/receipts_for_profile.dart" language="dart" range="8-31" title="receipts for profile" :::

:::code source="../../packages/ndk/example/zaps/receipts_for_event.dart" language="dart" range="8-31" title="receipts for event" :::

## How to use

You need a `nostr+walletconnect://...` uri from your NWC wallet service provider.

see https://github.com/getAlby/awesome-nwc for more info how to get a wallet supporting NWC
