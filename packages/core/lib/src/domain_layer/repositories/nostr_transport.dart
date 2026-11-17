import 'dart:async';

import 'package:dostr_relay_url/dostr_relay_url.dart';

/// One socket to a relay. It never reconnects: `RelayManager` opens a new
/// transport once this one ends.
abstract class NostrTransport {
  /// Completes once the socket is open, and fails when it cannot connect or is
  /// closed before that.
  Future<void> get ready;
  bool isOpen();
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
  NostrTransport call(RelayUrl url);
}
