import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import '../../entities/relay_set.dart';

/// Hands [filters] to [relayUrl] in a single REQ.
typedef RelaySend = void Function(String relayUrl, List<Filter> filters);

/// Hands the event being broadcast to [relayUrl]. [connectTimeout] bounds the
/// connecting, and [veto] can still call the send off once the relay is
/// connected.
typedef RelayPublishSend =
    void Function(
      String relayUrl, {
      Duration connectTimeout,
      Future<String?> Function()? veto,
    });

abstract class NetworkEngine {
  /// Picks the relays [filters] go to and hands each of them to [send], at
  /// most once per relay: a second REQ with the same id would replace the first
  /// on the relay (NIP-01).
  ///
  /// The request may end once the returned future completes and the relays
  /// handed over so far answered. A relay handed over later, one the engine was
  /// still connecting to, only gets the request if it is still running.
  Future<void> route(
    List<Filter> filters,
    RelaySend send, {
    RelaySet? relaySet,
    required int desiredCoverage,
  });

  /// Picks the relays [event], already signed, is broadcast to: the author's
  /// outbox relays and the inboxes it mentions. Hands each of them to [send].
  ///
  /// The broadcast may end once the returned future completes and the relays
  /// handed over answered.
  Future<void> routeBroadcast(Nip01Event event, RelayPublishSend send);
}
