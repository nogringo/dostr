import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip85/dostr_nip85.dart';

TrustedAssertions trustedAssertionsFor(
  RelayReqs reqs, {
  List<Nip85TrustedProvider> defaultProviders = DEFAULT_NIP85_PROVIDERS,
}) => TrustedAssertions(
  query: (filter, {required relay}) => reqs
      .req(
        relays: {
          relay: [filter],
        },
      )
      .events
      .map((received) => received.event)
      .toList(),
  subscribe: (filter, {required relay}) {
    final req = reqs.req(
      relays: {
        relay: [filter],
      },
      closeOnEose: false,
    );
    return (
      events: req.events.map((received) => received.event),
      close: req.close,
    );
  },
  defaultProviders: defaultProviders,
);
