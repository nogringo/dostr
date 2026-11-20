import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_core/protocol.dart';

import 'logger.dart';
import 'negentropy.dart' as neg;
import 'nip77_state.dart';

part 'nip77_internal.dart';

/// Ids and creation times of the local events matching a filter
typedef Nip77LoadEventIds =
    Future<List<({String id, int createdAt})>> Function(Filter filter);

/// What a reconciliation fails with. Errors thrown by [Nip77LoadEventIds]
/// come through as they are, and so does the [ArgumentError] for an entry it
/// returns whose id is not 64 hex digits or whose creation time is out of
/// range.
sealed class Nip77Exception implements Exception {
  /// relay the reconciliation was meant for
  final RelayUrl relayUrl;

  Nip77Exception(this.relayUrl);
}

/// Exception thrown when a relay answers NEG-OPEN with a NOTICE that says it
/// does not support NIP-77
final class Nip77NotSupportedException extends Nip77Exception {
  final String? message;

  Nip77NotSupportedException(super.relayUrl, [this.message]);

  @override
  String toString() =>
      'Nip77NotSupportedException: Relay $relayUrl does not support NIP-77${message != null ? ': $message' : ''}';
}

/// Exception thrown when a relay ends the negotiation with a NEG-ERR, or with
/// a CLOSED that does not ask for an identity
final class Nip77RefusedException extends Nip77Exception {
  /// reason the relay gave, such as `blocked: this query is too big`
  final String reason;

  /// most records the relay agrees to process, which NIP-77 lets a `blocked`
  /// refusal give
  final int? maxRecords;

  Nip77RefusedException(super.relayUrl, this.reason, {this.maxRecords});

  /// Machine-readable prefix of [reason], lowercased, null when it has none.
  /// NIP-77 suggests `blocked`, for a query too big or too old, and `closed`,
  /// for a negotiation the relay timed out.
  String? get code {
    final colon = reason.indexOf(':');
    final prefix = (colon < 0 ? reason : reason.substring(0, colon)).trim();
    if (prefix.isEmpty || prefix.contains(RegExp(r'\s'))) return null;
    return prefix.toLowerCase();
  }

  @override
  String toString() =>
      'Nip77RefusedException: $relayUrl refused the negotiation: $reason'
      '${maxRecords != null ? ' (at most $maxRecords records)' : ''}';
}

/// Exception thrown when no connection to the relay could be opened, the
/// [AuthHandler] refused to bind one, or the connection dropped or was closed
/// before the reconciliation ended
final class Nip77ConnectionException extends Nip77Exception {
  /// whether the connection was open, and dropped or was closed before the
  /// reconciliation ended
  final bool lost;

  Nip77ConnectionException(super.relayUrl, {this.lost = false});

  @override
  String toString() => lost
      ? 'Nip77ConnectionException: the connection to $relayUrl closed before '
            'the reconciliation ended'
      : 'Nip77ConnectionException: could not open a connection to $relayUrl';
}

/// Exception thrown when a relay sends a NEG-MSG the Negentropy V1 codec
/// cannot read
final class Nip77MalformedMessageException extends Nip77Exception {
  /// what the codec reported
  final Object error;

  Nip77MalformedMessageException(super.relayUrl, this.error);

  @override
  String toString() =>
      'Nip77MalformedMessageException: $relayUrl sent an unreadable NEG-MSG: '
      '$error';
}

/// Exception thrown when no connection can carry the reconciliation, because
/// the identity it requires cannot sign. Falling back to the anonymous
/// connection is exactly what [AuthPolicy.require] ruled out.
final class Nip77AuthUnavailableException extends Nip77Exception {
  /// identity that was required
  final String pubkey;

  /// no connection can carry the reconciliation
  Nip77AuthUnavailableException(super.relayUrl, this.pubkey);

  @override
  String toString() =>
      'Nip77AuthUnavailableException: $pubkey cannot sign, so no connection to '
      '$relayUrl can carry this reconciliation';
}

/// Exception thrown when a relay refuses the negotiation without an identity
/// and the auth policy leaves nobody to authenticate as.
final class Nip77AuthRequiredException extends Nip77Exception {
  /// raw refusal from the relay
  final String message;

  /// the relay asked for an identity this reconciliation may not reveal
  Nip77AuthRequiredException(super.relayUrl, this.message);

  @override
  String toString() =>
      'Nip77AuthRequiredException: $relayUrl requires an identity this '
      'reconciliation may not authenticate as: $message';
}

/// Exception thrown when a relay stops answering a NIP-77 reconciliation
final class Nip77TimeoutException extends Nip77Exception {
  /// how long the relay stayed silent
  final Duration timeout;

  /// whether the relay never answered the NEG-OPEN, rather than going quiet
  /// between two rounds
  final bool openUnanswered;

  Nip77TimeoutException(
    super.relayUrl,
    this.timeout, {
    required this.openUnanswered,
  });

  @override
  String toString() => openUnanswered
      ? 'Nip77TimeoutException: $relayUrl did not answer NEG-OPEN within ${timeout.inSeconds}s'
      : 'Nip77TimeoutException: $relayUrl went silent for ${timeout.inSeconds}s between two rounds';
}

/// Response from a NIP-77 reconciliation request
class Nip77Response {
  final Nip77State _state;

  Nip77Response(this._state);

  /// Event IDs we need to fetch from the relay, as the rounds find them.
  ///
  /// It is a single-subscription stream that keeps every id until it is
  /// listened to. It closes when the reconciliation ends, whatever the
  /// outcome: [future] tells which.
  Stream<String> get needStream => _state.needStream;

  /// Event IDs we have that the relay doesn't, as [needStream] gives the
  /// others.
  Stream<String> get haveStream => _state.haveStream;

  /// Completes with the final result, or fails with a [Nip77Exception].
  /// Listen to it even when only the streams matter: a failure nobody
  /// listens to is reported as an uncaught error.
  Future<Nip77Result> get future => _state.future;

  /// The subscription ID for this session
  String get subscriptionId => _state.subscriptionId;

  /// The relay of this session
  RelayUrl get relayUrl => _state.relayUrl;
}

/// Public API for NIP-77 Negentropy sync
class Nip77 {
  final _Nip77Internal _internal;

  /// Reconciles over the connections of [relayManager], comparing the relay's
  /// events with the local ones that [loadEventIds] returns.
  Nip77({
    required RelayManager relayManager,
    required Nip77LoadEventIds loadEventIds,
  }) : _internal = _Nip77Internal(
         relayManager: relayManager,
         loadEventIds: loadEventIds,
       ) {
    relayManager.addProtocolHandler(_internal);
  }

  /// How long a relay may take to answer NEG-OPEN by default
  static const Duration defaultOpenTimeout = Duration(seconds: 30);

  /// How long a relay may stay silent between two rounds by default
  static const Duration defaultIdleTimeout = Duration(seconds: 15);

  /// Most bytes of one NEG-MSG by default, before hex encoding, so the
  /// message stays under 128 KiB on the wire
  static const int defaultFrameSizeLimit = 60000;

  /// Close a specific NIP-77 negotiation. Its future completes with what it
  /// found so far, and [Nip77Result.isComplete] false.
  void close(String subscriptionId) {
    _internal.close(subscriptionId);
  }

  /// Close all active NIP-77 negotiations, as [close] does
  void closeAll() {
    _internal.closeAll();
  }

  /// Closes all active negotiations, as [closeAll] does, and stops listening
  /// to the relay manager. [reconcile] throws a [StateError] afterwards.
  void dispose() {
    _internal.dispose();
  }

  /// Start a negentropy reconciliation with a relay
  ///
  /// [relayUrl] - The relay to reconcile with
  /// [filter] - Filter to determine which events to sync
  /// [openTimeout] - How long the relay may take to answer NEG-OPEN
  ///                 (default: 30s)
  /// [idleTimeout] - How long the relay may stay silent between two rounds
  ///                 (default: 15s). There is no overall deadline, so a
  ///                 reconciliation that keeps progressing is never cut.
  /// [frameSizeLimit] - Most bytes of one NEG-MSG before hex encoding, 0 for
  ///                 no limit, otherwise at least
  ///                 [NegentropyEncoder.minFrameSizeLimit]. A larger
  ///                 difference takes more rounds instead.
  /// [localIds] - The local events to compare, instead of the ones
  ///              `loadEventIds` returns for [filter].
  /// [auth] - which identity this reconciliation may be attributed to, see
  ///          [AuthPolicy]. Without it, it reveals no identity, as with
  ///          [AuthPolicy.never].
  ///
  /// Returns a [Nip77Response] with streams for real-time updates and
  /// a future that completes with the final result.
  ///
  /// Throws from the call itself, before anything is sent, an [ArgumentError]
  /// for a [frameSizeLimit] it does not take, or a [localIds] entry whose id
  /// is not 64 hex digits or whose creation time is out of range, a
  /// [Nip77AuthUnavailableException] if [auth] requires an identity that
  /// cannot sign, and a [StateError] once [dispose] was called.
  ///
  /// The returned future fails with:
  /// - [Nip77NotSupportedException] if the relay doesn't support NIP-77,
  /// - [Nip77RefusedException] if the relay refuses or ends the negotiation,
  /// - [Nip77TimeoutException] if the relay stops answering,
  /// - [Nip77AuthRequiredException] if the relay asks for an identity [auth]
  ///   rules out,
  /// - [Nip77ConnectionException] if no connection to the relay opens, or it
  ///   drops or is closed before the end,
  /// - [Nip77MalformedMessageException] if the relay sends a message the
  ///   codec cannot read.
  Nip77Response reconcile({
    required RelayUrl relayUrl,
    required Filter filter,
    Duration openTimeout = defaultOpenTimeout,
    Duration idleTimeout = defaultIdleTimeout,
    int frameSizeLimit = defaultFrameSizeLimit,
    List<({String id, int createdAt})>? localIds,
    AuthPolicy? auth,
  }) {
    return _internal.reconcile(
      relayUrl: relayUrl,
      filter: filter,
      openTimeout: openTimeout,
      idleTimeout: idleTimeout,
      frameSizeLimit: frameSizeLimit,
      localIds: localIds,
      auth: auth,
    );
  }
}
