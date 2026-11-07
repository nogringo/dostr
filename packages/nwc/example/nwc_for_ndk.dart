import 'package:ndk/ndk.dart';
import 'package:ndk_nwc/ndk_nwc.dart';

/// An [Nwc] that talks to the relays through [ndk]. `ndk.destroy()`
/// disconnects it and `ndk.setBackgrounded(true)` pauses idle notifications.
Nwc nwcFor(Ndk ndk) {
  final nwc = Nwc(
    query: (filter, {required relays, required timeout, onTimeout}) => ndk
        .requests
        .query(
          name: 'nwc',
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
        name: 'nwc',
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
  return nwc;
}
