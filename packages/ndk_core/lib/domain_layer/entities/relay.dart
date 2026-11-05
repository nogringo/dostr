/// Connection attempts of a `RelayConnectivity`, kept by its `RelayManager`.
abstract interface class Relay {
  /// relay url
  String get url;

  /// is it connecting
  bool get connecting;

  /// last connection try timestamp
  int? get lastConnectTry;

  /// last successful connection
  int? get lastSuccessfulConnect;

  /// was last connection try longer than given seconds
  bool wasLastConnectTryLongerThanSeconds(int seconds);
}
