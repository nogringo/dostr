import 'dart:async';

/// What the relay reads on one socket of a connection, asked by `RelayLimits`
/// each time a socket opens: a socket that replaces it gets its own. Internal
/// to dostr_core.
class SocketLimits {
  final Completer<void> _settled = Completer();
  int? _subscriptions;
  int? _messageLength;

  /// UTF-8 length of the longest message written on the socket
  int longestMessage = 0;

  SocketLimits();

  /// The limits of a connection that has not opened a socket yet: nothing
  /// waits for them.
  SocketLimits.none() {
    _settled.complete();
  }

  /// how many REQs the relay keeps open on the socket, null until settled
  int? get subscriptions => _subscriptions;

  /// how many UTF-8 bytes the relay reads in one message, as it publishes it,
  /// null when unknown
  int? get messageLength => _messageLength;

  /// completes once the limits are settled, or the socket replaced
  Future<void> get settled => _settled.future;

  void settle({required int subscriptions, int? messageLength}) {
    if (_settled.isCompleted) return;
    _subscriptions = subscriptions;
    _messageLength = messageLength;
    _settled.complete();
  }

  /// Lets go whatever waits for these limits, once another socket replaced the
  /// one they were asked for.
  void abandon() {
    if (!_settled.isCompleted) _settled.complete();
  }
}
