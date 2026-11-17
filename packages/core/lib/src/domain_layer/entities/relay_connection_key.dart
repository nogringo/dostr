import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:dostr_signer/dostr_signer.dart';

final _hexPubkeyRegex = RegExp(r'^[0-9a-fA-F]{64}$');

/// Identifies a single relay connection.
///
/// A connection carries at most one authenticated identity, chosen when the
/// connection is opened and immutable for its whole lifetime. Several
/// connections may therefore exist towards the same relay.
class RelayConnectionKey {
  final RelayUrl url;

  /// lowercase hex pubkey authenticated on this connection, null when anonymous
  final String? pubkey;

  const RelayConnectionKey._(this.url, this.pubkey);

  /// key of a connection that never authenticates
  factory RelayConnectionKey.anonymous(RelayUrl url) =>
      RelayConnectionKey._(url, null);

  /// key of a connection authenticated as [pubkey]
  factory RelayConnectionKey.authenticated(RelayUrl url, String pubkey) {
    if (!_hexPubkeyRegex.hasMatch(pubkey)) {
      throw ArgumentError.value(pubkey, 'pubkey', 'expected 64 hex characters');
    }
    return RelayConnectionKey._(url, pubkey.toLowerCase());
  }

  /// The connection a request under [auth] must use towards [url] (NIP-42).
  ///
  /// Null means no connection can satisfy it and nothing may be sent to that
  /// relay: falling back to the anonymous one is exactly what the caller ruled
  /// out. A null [auth] keeps the historical default.
  static RelayConnectionKey? forAuth(RelayUrl url, AuthPolicy? auth) =>
      switch (auth) {
        AuthPolicyRequire(:final signer) =>
          signer.canSign
              ? RelayConnectionKey.authenticated(url, signer.publicKey)
              : null,
        null ||
        AuthPolicyNever() ||
        AuthPolicyAllow() => RelayConnectionKey.anonymous(url),
      };

  /// whether any identity is bound to this connection
  bool get isAnonymous => pubkey == null;

  @override
  String toString() => '$url|${pubkey ?? 'anon'}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelayConnectionKey &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          pubkey == other.pubkey;

  @override
  int get hashCode => Object.hash(url, pubkey);
}
