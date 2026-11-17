import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../../../config/publish_defaults.dart';
import '../../entities/relay_publish_outcome.dart';
import '../relay_manager/publish_state.dart';
import '../relay_manager/publishes_in_flight.dart';
import '../relay_manager/relay_manager.dart';
import '../relay_manager/relay_manager_parts.dart';

/// Publishes signed events to relays the caller picks (NIP-01 EVENT).
///
/// No signing, no cache, no outbox routing and no retry.
final class RelayPublishes {
  final PublishesInFlight _publishes;

  RelayPublishes({required RelayManager relayManager})
    : _publishes = relayManagerParts(relayManager).publishes;

  /// Sends [event], which must be signed, to each of [relays] and collects
  /// their OK, on the connections [auth] allows. Throws a [StateError] once
  /// the [RelayManager] was disposed.
  ///
  /// It is done once every relay answered or failed, or after [timeout], not
  /// counting NIP-42 authentication: a relay that has not answered by then is
  /// [RelayPublishStatus.timedOut].
  RelayPublish publish(
    Nip01Event event, {
    required Iterable<RelayUrl> relays,
    AuthPolicy? auth,
    Duration timeout = defaultPublishTimeout,
  }) {
    if (event.sig == null) {
      throw ArgumentError.value(event.id, 'event', 'must be signed');
    }
    if (_publishes.disposed) {
      throw StateError('the RelayManager was disposed');
    }
    final state = PublishState(
      event,
      relays: relays,
      timeout: timeout,
      auth: auth,
    );
    _publishes.start(state);
    return RelayPublish._(state);
  }
}

/// One EVENT on the relays its caller picked, opened by
/// [RelayPublishes.publish].
final class RelayPublish {
  final PublishState _state;

  RelayPublish._(this._state);

  /// The outcome on each relay so far, keyed by relay url.
  Map<RelayUrl, RelayPublishOutcome> get outcomes => _state.outcomes;

  /// [outcomes] each time a relay answers, closed once the publish is done.
  Stream<Map<RelayUrl, RelayPublishOutcome>> get outcomesStream =>
      _state.outcomesStream;

  /// [outcomes] once the publish is done, see [RelayPublishes.publish].
  Future<Map<RelayUrl, RelayPublishOutcome>> get done => _state.done;

  /// the event being published
  Nip01Event get event => _state.event;
}
