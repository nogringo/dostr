import 'package:ndk/ndk.dart';
import 'package:ndk_nip82/ndk_nip82.dart';

/// [Software] answered by [ndk]'s requests.
Software softwareForNdk(Ndk ndk) => Software(
  query: (filter, {relays, timeout}) async {
    final response = ndk.requests.query(
      filter: filter,
      explicitRelays: relays,
      timeout: timeout,
      name: 'software',
    );
    final events = await response.future;
    return (
      events: events,
      anyRelayCompleted: response.relayOutcomes.values.any(
        (outcome) => outcome.status == RelayRequestStatus.eose,
      ),
    );
  },
  subscribe: (filter, {relays}) {
    final response = ndk.requests.subscription(
      filter: filter,
      explicitRelays: relays,
      cacheRead: true,
      cacheWrite: true,
      name: 'software-watch',
    );
    return (
      events: response.stream,
      close: () => ndk.requests.closeSubscription(
        response.requestId,
        debugLabel: 'software release watcher cancelled',
      ),
    );
  },
);
