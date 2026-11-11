import 'dart:async';

/// One socket to a relay. It never reconnects: `RelayManager` opens a new
/// transport once this one ends.
abstract class NostrTransport {
  /// Completes once the socket is open, and fails when it cannot connect or is
  /// closed before that.
  Future<void> get ready;
  bool isOpen();
  bool isConnecting();
  Future<void> close();
  void send(dynamic data);

  /// [onDone] is called once the socket ended, whichever side closed it.
  StreamSubscription listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  });

  int? closeCode();
  String? closeReason();
}

abstract class NostrTransportFactory {
  NostrTransport call(String url);
}
