import 'package:ndk/ndk.dart';

TrustedAssertions trustedAssertionsFor(
  Ndk ndk, {
  List<Nip85TrustedProvider> defaultProviders = DEFAULT_NIP85_PROVIDERS,
}) => TrustedAssertions(
  query: (filter, {required relay}) =>
      ndk.requests.query(filter: filter, explicitRelays: [relay]).future,
  subscribe: (filter, {required relay}) {
    final response = ndk.requests.subscription(
      filter: filter,
      explicitRelays: [relay],
    );
    return (
      events: response.stream,
      close: () => ndk.requests.closeSubscription(response.requestId),
    );
  },
  defaultProviders: defaultProviders,
);
