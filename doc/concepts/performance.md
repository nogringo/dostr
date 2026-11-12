## Performance

There are two main constraints that we aim for: battery/compute and network bandwidth.

**network**\
The outbox model is our main pillar to avoid unnecessary requests: [Fetchers](/usecases/fetchers.md) ask each account's write relays rather than every relay. They batch the pubkeys looked up together into one REQ per relay, share lookups between fetchers, and with a cache and a `UrlListCheckStore` skip the relays entirely for a list checked recently. `EventFetcher` asks each relay as soon as a list names it, so one slow relay does not hold back the others.

**compute**\
The most compute intensive operation is verifying signatures. `RelayReqs` remembers the signatures it already checked, so an event several relays send is verified once. `Bip340EventVerifier` from `ndk_bip340` runs in an isolate, in pure Dart. On native platforms, `RustEventVerifier` from [`ndk_rust_verifier`](https://pub.dev/packages/ndk_rust_verifier) is much faster. On the web, `WebEventVerifier` from [`ndk_web_crypto`](https://pub.dev/packages/ndk_web_crypto) is too.
