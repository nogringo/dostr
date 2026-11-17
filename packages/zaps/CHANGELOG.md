## 0.1.0

 - Initial release, moved out of the `ndk` package. `LnurlTransportHttpImpl` is now `HttpLnurlTransport`, and takes an `http.Client` instead of an `HttpRequestDS`.
 - `pubKey` is now `pubkey`: the field of `ZapReceipt`, and the parameter of `ZapRequest`, `createZapRequest`, `fetchZappedReceipts` and `subscribeToZapReceipts`. `nostrPubKey` of `ZapReceipt.isValid` is now `nostrPubkey`, as the LNURL field.
 - `createZapRequest` takes its `relays` as `RelayUrl`s, from `dostr_relay_url`.
 - Logs with [`logging`](https://pub.dev/packages/logging), under the name `dostr_zaps`, instead of the logger of `ndk`: nothing is printed until the app listens to `Logger.root.onRecord`.
