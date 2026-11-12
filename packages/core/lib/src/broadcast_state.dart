import 'dart:async';

import 'package:rxdart/rxdart.dart';

import '../domain_layer/entities/timeout_pausable.dart';
import 'package:dostr_signer/dostr_signer.dart';
import '../domain_layer/entities/broadcast_state.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

/// State of one broadcast. Internal to dostr_core.
class BroadcastState implements TimeoutPausable {
  /// share of the relays, between 0 and 1, that must accept the event for the
  /// broadcast to be done before every relay answered
  final double considerDonePercent;

  final Duration timeout;

  /// the event being broadcast (stored for potential retries on auth-required)
  Nip01Event? event;

  /// which identity this broadcast may be attributed to on the relays (NIP-42)
  final AuthPolicy? auth;

  /// relay urls this broadcast is currently re-sending to after an
  /// auth-required refusal
  final Set<String> retryingAuth = {};

  /// stream controller for state updates
  final BehaviorSubject<BroadcastState> _stateUpdatesController =
      BehaviorSubject<BroadcastState>();

  /// [networkController] used by relay manger to write responses
  StreamController<RelayBroadcastResponse> networkController =
      StreamController<RelayBroadcastResponse>();

  /// stream of state updates \
  /// updates are sent when a relay responds, the whole state is sent \
  /// if you call .listen() the last state is sent immediately
  Stream<BroadcastState> get stateUpdates => _stateUpdatesController.stream;

  //! our broadcast tracking obj
  /// key is relay url, value is [RelayBroadcastResponse]
  Map<String, RelayBroadcastResponse> broadcasts = {};

  /// completes when all relays have responded or timed out
  /// first string is the relay url, second is the response
  bool get publishDone {
    // If no relays were registered and the engine closed the controller, it's done
    if (broadcasts.isEmpty) {
      return networkController.isClosed;
    }

    // Check if all relays have responded (success or failure)
    final allResponded = broadcasts.values.every(
      (element) => element.okReceived || element.failure != null,
    );
    if (allResponded) {
      return true;
    }

    final acceptedCount = broadcasts.values
        .where((element) => element.broadcastSuccessful)
        .length
        .toDouble();
    final totalCount = broadcasts.length.toDouble();
    return acceptedCount / totalCount >= considerDonePercent;
  }

  /// completes when state update controller closes
  Future<BroadcastState> get publishDoneFuture => _publishDoneCompleter.future;

  late final StreamSubscription _networkSubscription;
  Timer? _timeoutTimer;
  bool _isDisposed = false;
  final Completer<BroadcastState> _publishDoneCompleter = Completer();

  bool _timeoutStarted = false;
  DateTime? _timeoutStartedAt;
  Duration? _timeoutLeftAtStart;
  Duration? _remainingTimeout;
  int _timeoutPauses = 0;

  /// creates a new [BroadcastState] instance
  BroadcastState({
    required this.timeout,
    this.considerDonePercent = 1,
    this.auth,
  }) {
    _networkSubscription = networkController.stream.listen(
      (response) {
        // got a response from a relay
        broadcasts[response.relayUrl] = response;
        // send state update
        _stateUpdatesController.add(this);
        // check if all relays responded
        _checkBroadcastDone();
      },
      onDone: () {
        _checkBroadcastDone();
      },
    );
  }

  /// Starts the timeout timer. Call this after signing is complete.
  void startTimeout() {
    if (_timeoutStarted) return;
    _timeoutStarted = true;
    _startTimeout(timeout);
  }

  void _startTimeout(Duration duration) {
    _timeoutStartedAt = DateTime.now();
    _timeoutLeftAtStart = duration;
    _timeoutTimer = Timer(duration, () {
      if (!publishDone) {
        _stateUpdatesController.add(this);
        _dispose();
      }
    });
  }

  /// Pauses the timeout while an [AuthHandler] decides.
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
    if (_timeoutPauses > 0 || remaining == null || _isDisposed) return;
    _remainingTimeout = null;
    _startTimeout(remaining);
  }

  void _checkBroadcastDone() {
    if (publishDone) {
      _stateUpdatesController.add(this);
      _dispose();
    }
  }

  /// dispose of the broadcast state => close all streams
  void _dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _timeoutTimer?.cancel();
    _remainingTimeout = null;
    _networkSubscription.cancel();
    if (!_publishDoneCompleter.isCompleted) {
      _publishDoneCompleter.complete(this);
    }
    _stateUpdatesController.close();
    networkController.close();
  }

  /// Add an error to the broadcast state stream and dispose
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_publishDoneCompleter.isCompleted) {
      _publishDoneCompleter.completeError(error, stackTrace);
    }
    _dispose();
  }

  /// Close the network controller if no relays were registered.
  /// This should be called after broadcast strategies complete
  /// to signal that the broadcast is done when there were no relays to broadcast to.
  void closeIfNoRelays() {
    if (broadcasts.isNotEmpty || networkController.isClosed) return;
    networkController.close();
  }
}
