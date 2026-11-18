## 0.1.0

 - Initial release, moved out of the `ndk` package. `LnurlTransportHttpImpl` is now `HttpLnurlTransport`, and takes an `http.Client` instead of an `HttpRequestDS`.
 - `pubKey` is now `pubkey`: the field of `ZapReceipt`, and the parameter of `ZapRequest`, `createZapRequest`, `fetchZappedReceipts` and `subscribeToZapReceipts`. `nostrPubKey` of `ZapReceipt.isValid` is now `nostrPubkey`, as the LNURL field.
 - `createZapRequest` takes its `relays` as `RelayUrl`s, from `dostr_relay_url`.
 - Logs with [`logging`](https://pub.dev/packages/logging), under the name `dostr_zaps`, instead of the logger of `ndk`: nothing is printed until the app listens to `Logger.root.onRecord`.
 - `fetchZappedReceipts` and `subscribeToZapReceipts` take the `nostrPubkey` of the recipient's LNURL server, ask for the receipts it signed only, and give only those that pass `ZapReceipt.isValid`. Anyone could publish a receipt that the old ones passed on.
 - `subscribeToZapReceipts` returns a `ZapReceiptsSubscription`, whose `receipts` are `ZapReceipt`s, instead of a `ZapsSubscription` of events. `fetchZappedReceipts` takes a `Duration` timeout, 10 seconds by default, instead of a nullable one.
 - `ZapReceipt.isValid` compares the amounts to the millisat, refuses a receipt without zap request, without invoice amount or whose zap request names another recipient, and compares the `lnurl` ignoring case. `recipientLnurl` is optional.
 - `ZapReceipt` is immutable and has a `zapRequest` and an `amountMsats`. `amountSats` is the amount of the invoice instead of the one the zap request asked for, and `sender`, `comment` and `lnurl` come from `zapRequest`. `fromEvent` throws an `ArgumentError` instead of an `Exception` for an event of another kind, and reads a `description` that is not a zap request as no `zapRequest` instead of throwing.
 - `Lnurl.getAmountFromBolt11` is now `bolt11AmountMsats`, in millisats. It reads whole bitcoin amounts and every network, and returns null instead of 0 for an invoice it cannot read.
 - `LnurlResponse` and `InvoiceResponse` are immutable. `LnurlResponse.callback` is never null: `fromJson` throws a `FormatException` without it, so `getLnurlResponse` returns null for an error answer. `allowsNostr` is a `bool`, and `doesAllowsNostr` is gone.
