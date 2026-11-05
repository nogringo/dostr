import 'home_relays.dart';
import 'outbox_fetcher.dart';

/// Fetches the `home-relays` lists users publish, `kind:36205`, from their
/// write relays, which [nip65Fetcher] finds, and from [relays].
/// [HomeRelayList.fromEvent] reads one.
class HomeRelayListFetcher extends OutboxFetcher {
  HomeRelayListFetcher({
    required super.reqs,
    super.nip65Fetcher,
    super.relays,
    super.timeout,
    super.cache,
    super.checks,
    super.maxAge,
  }) : super(
         kind: HomeRelayList.kind,
         dTag: HomeRelayList.dTag,
         name: 'home-relays',
       );
}
