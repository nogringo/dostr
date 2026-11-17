import 'dart:async';

import 'package:dostr_relay_url/dostr_relay_url.dart';

/// One socket to a relay. It never reconnects: `RelayManager` opens a new
/// transport once this one ends.
abstract interface class NostrTransport {
  /// Completes once the socket is open, and fails when it cannot connect or is
  /// closed before that.
  Future<void> get ready;

  bool get isOpen;

  Future<void> close();

  void send(dynamic data);

  /// [onDone] is called once the socket ended, whichever side closed it.
  StreamSubscription listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  });

  int? get closeCode;

  String? get closeReason;
}

/// Opens a [NostrTransport] to [url], as `webSocketTransportFactory` does.
typedef NostrTransportFactory = NostrTransport Function(RelayUrl url);
