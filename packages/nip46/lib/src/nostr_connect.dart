import 'package:dostr_core/shared/nips/nip01/helpers.dart';

import 'nip46_client_metadata.dart';

/// A `nostrconnect://` invitation, from `Bunkers.createNostrConnect`.
class NostrConnect {
  List<String> relays;
  Nip46ClientMetadata? clientMetadata;

  final String privateKey;
  final String publicKey;

  final secret = Helpers.getSecureRandomHex(16);

  String get nostrConnectURL {
    final params = <String>[];

    for (final relay in relays) {
      params.add('relay=${Uri.encodeComponent(relay)}');
    }

    params.add('secret=$secret');

    final perms = clientMetadata?.perms;
    if (perms != null && perms.isNotEmpty) {
      params.add('perms=${perms.join(',')}');
    }

    clientMetadata?.displayInfo.forEach((key, value) {
      params.add('$key=${Uri.encodeComponent(value)}');
    });

    return 'nostrconnect://$publicKey?${params.join('&')}';
  }

  NostrConnect({
    required this.relays,
    required this.privateKey,
    required this.publicKey,
    this.clientMetadata,
  }) {
    if (relays.isEmpty) {
      throw ArgumentError("At least one relay is required");
    }
  }
}
