import 'package:dostr_core/dostr_core.dart';

/// A connection to a remote signer, stored with [toJson] and restored with
/// [BunkerConnection.fromJson].
///
/// Store it as a secret: whoever holds [privateKey] can send the remote
/// signer requests under the permissions the user granted.
class BunkerConnection {
  final String privateKey;
  final String remotePubkey;
  final List<RelayUrl> relays;

  BunkerConnection({
    required this.privateKey,
    required this.remotePubkey,
    required this.relays,
  });

  Map<String, dynamic> toJson() => {
    'privateKey': privateKey,
    'remotePubkey': remotePubkey,
    'relays': relays,
  };

  factory BunkerConnection.fromJson(Map<String, dynamic> json) {
    return BunkerConnection(
      privateKey: json['privateKey'] as String,
      remotePubkey: json['remotePubkey'] as String,
      relays: (json['relays'] as List)
          .cast<String>()
          .map(RelayUrl.tryParse)
          .nonNulls
          .toList(),
    );
  }
}
