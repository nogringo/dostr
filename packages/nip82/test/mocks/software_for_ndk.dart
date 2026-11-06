import 'package:ndk/ndk.dart';
import 'package:ndk_nip82/ndk_nip82.dart';

Software softwareFor(Ndk ndk) => Software(
  query: (filter, {relays, timeout}) async {
    final response = ndk.requests.query(
      filter: filter,
      explicitRelays: relays,
      timeout: timeout,
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
    );
    return (
      events: response.stream,
      close: () => ndk.requests.closeSubscription(response.requestId),
    );
  },
);
