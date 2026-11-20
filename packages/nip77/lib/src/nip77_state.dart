import 'dart:async';
import 'dart:typed_data';

import 'package:dostr_core/dostr_core.dart';

import 'negentropy.dart';

/// State of a NIP-77 negentropy reconciliation session
class Nip77State implements TimeoutPausable {
  /// Unique subscription ID for this session
  final String subscriptionId;

  /// Connection this session runs on. It moves to a bound connection when a
  /// relay refuses the negotiation without an identity.
  RelayConnectionKey connectionKey;

  /// Filter the negotiation was opened with, replayed on an auth retry
  final Filter filter;

  /// Which identity this session may be attributed to (NIP-42)
  final AuthPolicy? auth;

  /// how long the relay may take to answer a NEG-OPEN
  final Duration openTimeout;

  /// how long the relay may stay silent between two rounds
  final Duration idleTimeout;

  /// most bytes of one message sent to the relay, 0 for no limit
  final int frameSizeLimit;

  /// whether the negotiation already moved from the anonymous connection to a
  /// bound one
  bool movedToBoundConnection = false;

  /// whether AUTH was already sent for the bound connection after a refusal
  bool authenticatedAfterRefusal = false;

  /// whether the connection behind [connectionKey] is open for this session,
  /// false while it opens or while the session moves to a bound one
  bool connected = false;

  /// whether a NEG-OPEN went out
  bool negOpenSent = false;

  /// whether the relay answered a NEG-OPEN, even with a refusal, which shows
  /// it supports NIP-77
  bool answered = false;

  /// Relay this session is connected to
  RelayUrl get relayUrl => connectionKey.url;

  /// Local items for reconciliation, sorted once by [prepareNegentropyItems]
  List<NegentropyItem> localItems = const [];

  final _needController = StreamController<String>();

  final _haveController = StreamController<String>();

  /// All need IDs accumulated
  final List<String> needIds = [];

  /// All have IDs accumulated
  final List<String> haveIds = [];

  final Completer<Nip77Result> _completer = Completer<Nip77Result>();

  bool _isCompleted = false;

  Nip77State({
    required this.subscriptionId,
    required this.connectionKey,
    required this.filter,
    required this.openTimeout,
    required this.idleTimeout,
    required this.frameSizeLimit,
    this.auth,
  });

  /// Stream of IDs we need from the relay
  Stream<String> get needStream => _needController.stream;

  /// Stream of IDs we have that relay doesn't
  Stream<String> get haveStream => _haveController.stream;

  /// Future that completes when reconciliation is done
  Future<Nip77Result> get future => _completer.future;

  /// Whether the session is completed
  bool get isCompleted => _isCompleted;

  Timer? _timeoutTimer;
  DateTime? _timeoutStartedAt;
  Duration? _timeoutLeftAtStart;
  Duration? _remainingTimeout;
  int _timeoutPauses = 0;
  void Function()? _onTimeout;

  /// Gives the relay [duration] to answer what was just sent, replacing the
  /// previous deadline. There is no overall one, so a session that keeps
  /// getting answers never times out.
  void startTimeout(Duration duration, void Function() onTimeout) {
    cancelTimeout();
    _onTimeout = onTimeout;
    _startTimeout(duration);
  }

  void _startTimeout(Duration duration) {
    _timeoutStartedAt = DateTime.now();
    _timeoutLeftAtStart = duration;
    _timeoutTimer = Timer(duration, () => _onTimeout?.call());
  }

  /// Pauses the timeout while an [AuthHandler] decides on the connection.
  @override
  void pauseTimeout() {
    _timeoutPauses++;
    final timer = _timeoutTimer;
    if (_timeoutPauses > 1 || timer == null || !timer.isActive) return;

    final elapsed = DateTime.now().difference(_timeoutStartedAt!);
    final remaining = _timeoutLeftAtStart! - elapsed;
    _remainingTimeout = remaining.isNegative ? Duration.zero : remaining;
    timer.cancel();
    _timeoutTimer = null;
  }

  /// Resumes a paused timeout with the time it had left.
  @override
  void resumeTimeout() {
    if (_timeoutPauses == 0) return;
    _timeoutPauses--;
    final remaining = _remainingTimeout;
    if (_timeoutPauses > 0 || remaining == null) return;
    _remainingTimeout = null;
    _startTimeout(remaining);
  }

  /// Stops the clock for a wait that is not the relay's to answer, such as an
  /// authentication before the NEG-OPEN is sent again.
  void cancelTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _remainingTimeout = null;
  }

  /// Process an incoming NEG-MSG from relay
  /// Returns the response message bytes to send back, or null if done
  Uint8List? processMessage(Uint8List messageBytes) {
    final (response, newNeedIds, newHaveIds) = NegentropyEncoder.reconcile(
      messageBytes,
      localItems,
      frameSizeLimit: frameSizeLimit,
    );

    for (final id in newNeedIds) {
      needIds.add(id);
      _needController.add(id);
    }
    for (final id in newHaveIds) {
      haveIds.add(id);
      _haveController.add(id);
    }

    // Check if we're done (response only has version byte)
    if (response.length <= 1) {
      return null;
    }

    return response;
  }

  /// Complete the session successfully
  void complete() => _end(isComplete: true);

  /// Complete the session with an error
  void completeWithError(Object error) {
    if (_isCompleted) return;
    _isCompleted = true;
    cancelTimeout();
    _needController.close();
    _haveController.close();
    _completer.completeError(error);
  }

  /// Ends the session before it converged, with what it found so far
  void close() => _end(isComplete: false);

  void _end({required bool isComplete}) {
    if (_isCompleted) return;
    _isCompleted = true;
    cancelTimeout();
    _needController.close();
    _haveController.close();
    _completer.complete(
      Nip77Result(
        needIds: List.unmodifiable(needIds),
        haveIds: List.unmodifiable(haveIds),
        isComplete: isComplete,
      ),
    );
  }
}

/// Result of a NIP-77 negentropy reconciliation
class Nip77Result {
  /// IDs that we need to fetch from the relay
  final List<String> needIds;

  /// IDs that we have that the relay doesn't
  final List<String> haveIds;

  /// Whether the reconciliation ran until both sides agreed. It is false when
  /// `Nip77.close` or `Nip77.closeAll` ended it first: [needIds] and
  /// [haveIds] then hold only what the rounds so far found.
  final bool isComplete;

  Nip77Result({
    required this.needIds,
    required this.haveIds,
    required this.isComplete,
  });

  @override
  String toString() =>
      'Nip77Result(need: ${needIds.length}, have: ${haveIds.length}'
      '${isComplete ? '' : ', closed early'})';
}
