import 'package:dostr_relay_url/dostr_relay_url.dart';

/// Connection attempts of a `RelayConnectivity`, kept by its `RelayManager`.
abstract interface class Relay {
  RelayUrl get url;

  /// is it connecting
  bool get connecting;

  /// when the last attempt to connect started
  DateTime? get lastConnectTry;

  /// when the last attempt to connect succeeded
  DateTime? get lastSuccessfulConnect;
}
