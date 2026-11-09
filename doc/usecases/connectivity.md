---
icon: rss
---

[!badge variant="primary" text="high level"]

## Example

```dart
/// Stream<Map<String, RelayConnectivity>>
/// key: relay url/identifier
/// value: relay connectivity
ndkInstance.connectivity.relayConnectivityChanges;

/// NIP-11 info of a relay, fetched on first call and then cached,
/// across restarts in NdkConfig.cache
/// past an hour, a call gets the cached document while it is fetched again in the background
/// null when the relay serves no document, could not be reached and never answered, or the url is not a relay url
/// a relay that could not be reached is asked again after a minute, and keeps its last document meanwhile
await ndkInstance.connectivity.getRelayInfo(relayConnectivity.url);

/// forces all relays to reconnect \
/// use this for faster reconnects based on your application/os connectivity \
tryReconnect();

```

```dart example in a flutter app
  // listen to lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
 
    switch (state) {
      case AppLifecycleState.resumed:
        // reconnect instantly when resuming
        ndkInstance.connectivity.tryReconnect();
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }
```

## When to use

Ndk uses exponential backoff to reconnect to relays.\
The reconnect interval might be too long when the app is in the background and then resumed. \
You can instantly reconnect using the `tryReconnect()` method, as shown in the example above.

`relayConnectivityChanges` can be used to display connectivity status in the UI. 

### REQs per relay

NDK keeps at most the `limitation.max_subscriptions` of a relay open as REQs on one socket, and queues the others. It reads the limit from the NIP-11 document when the socket opens, through the same cache as `getRelayInfo`, which keeps the documents in `NdkConfig.cache`: after a restart, a persistent backend serves them without waiting for a request. A document fetched more than an hour ago is fetched again in the background, and the socket uses the old one meanwhile. A relay that publishes no limit, or does not answer within 2 seconds, gets 20. `NdkConfig.subscriptionLimit` comes first: a number it gives for a relay replaces NIP-11, and null falls back on it.

```dart
final ndk = Ndk(
  NdkConfig(
    eventVerifier: Bip340EventVerifier(),
    cache: MemCacheManager(),
    subscriptionLimit: (url) => url == 'wss://relay.example.com' ? 50 : null,
  ),
);
```

### Message length

A relay closes the socket, with a 1009, on a message longer than it reads, and every REQ open on that socket goes down with it. NDK does not send a message longer than the `limitation.max_message_length` of the relay, read from the same NIP-11 document: a REQ ends there as `notSent`, an EVENT fails, both with `RelayFailureKind.messageTooLong`. A relay that publishes no limit and closes a socket with a 1009 shows that it reads less than the longest message written there: nothing that long is sent to it again, and the other REQs go out again on the new socket. NDK keeps that limit in `NdkConfig.cache`, so it applies after a restart without a new 1009, and never forgets it: `removeLearnedMessageLength` of the cache lets a relay that raised its limit get longer messages again. REQs and EVENTs wait for these limits once a socket opens. `NdkConfig.messageLengthLimit` comes before NIP-11, like `subscriptionLimit`, and a learned limit applies either way.

A socket that drops within 10 seconds of coming back is not reconnected right away: it waits the next step of the backoff, so a relay that drops every socket it gets is not reconnected in a loop.

### Migrating from `RelayConnectivity.relayInfo`

`RelayConnectivity.relayInfo` and `ndk.relays.doesRelaySupportNip` are removed, so `relayConnectivityChanges` no longer carries NIP-11 info. Ask for it where you need it. NDK fetches it when it connects, for the limit above, so the call is often served from the cache:

```dart
// before
final info = relayConnectivity.relayInfo;
final supportsSearch = ndk.relays.doesRelaySupportNip(url, '50');

// after
final info = await ndk.connectivity.getRelayInfo(relayConnectivity.url);
final supportsSearch = info?.supportsNip('50') ?? false;
```

## Without NDK

`RelayInfo` and `HttpRelayInfoRepo` live in the `ndk_nip11` package, which `ndk` depends on and re-exports. It depends on neither `ndk` nor `ndk_core`: `HttpRelayInfoRepo` fetches the document without caching, and `CachedRelayInfoRepo` caches it, in a `RelayInfoCache` such as a `CacheManager` to keep it across restarts, see its [README](https://pub.dev/packages/ndk_nip11).
