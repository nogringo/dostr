/// Thrown when a blossom operation requires an identity that cannot sign, or
/// that the `AuthHandler` let no server see, so no request can carry an
/// authorization. Nothing is sent: going out bare is exactly what
/// [AuthPolicyRequire] rules out.
class BlossomAuthUnavailableException implements Exception {
  /// identity the operation required
  final String pubkey;

  /// blossom verb the authorization would have carried, such as "upload"
  final String operation;

  /// the required identity cannot sign or may not be revealed, so nothing was
  /// sent
  BlossomAuthUnavailableException(this.pubkey, this.operation);

  @override
  String toString() =>
      'BlossomAuthUnavailableException: $pubkey cannot sign or may not be '
      'revealed, so no blossom $operation request can be authorised';
}

/// Thrown, before anything is sent, when an operation has no server to talk
/// to: [pubkey]'s Blossom server list (kind 10063) is missing or empty, or the
/// call gave no server and nobody whose list could be read.
class BlossomNoServerListException implements Exception {
  /// whose list is missing, null when there was nobody to read one for
  final String? pubkey;

  const BlossomNoServerListException([this.pubkey]);

  @override
  String toString() => pubkey == null
      ? 'BlossomNoServerListException: no serverUrls, and no pubkey to read '
            'a server list for'
      : 'BlossomNoServerListException: $pubkey has no Blossom server list';
}
