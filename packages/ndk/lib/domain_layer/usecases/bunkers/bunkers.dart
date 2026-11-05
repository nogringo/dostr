import 'dart:async';
import 'dart:convert';

import 'package:rxdart/rxdart.dart';

import 'package:ndk/domain_layer/usecases/bunkers/models/nostr_connect.dart';

import '../../../data_layer/repositories/signers/nip46_event_signer.dart';
import 'package:ndk_core/domain_layer/repositories/event_signer.dart';
import 'package:ndk_core/shared/helpers/relay_helper.dart';
import 'models/bunker_request.dart';
import 'models/bunker_connection.dart';
import '../../entities/nip46_client_metadata.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_core/domain_layer/usecases/relay_manager.dart';

/// Bunkers usecase that handles NIP-46 remote signing protocol operations
class Bunkers {
  final RelayReqs _relayReqs;
  final RelayPublishes _relayPublishes;
  final LocalEventSignerFactory _eventSignerFactory;

  static const int kMaxWaitingTimeForConnectionSeconds = 600;

  Bunkers({
    required RelayReqs relayReqs,
    required RelayPublishes relayPublishes,
    required LocalEventSignerFactory eventSignerFactory,
  }) : _relayReqs = relayReqs,
       _relayPublishes = relayPublishes,
       _eventSignerFactory = eventSignerFactory;

  /// Connects to a bunker using a bunker URL (bunker://)
  /// authCallback is called with the auth URL if the bunker requires authentication
  Future<BunkerConnection?> connectWithBunkerUrl(
    String bunkerUrl, {
    Function(String)? authCallback,
    Nip46ClientMetadata? clientMetadata,
  }) async {
    final uri = Uri.parse(bunkerUrl);
    if (uri.scheme != 'bunker') {
      throw ArgumentError('Invalid bunker URL scheme');
    }

    final remotePubkey = uri.host;
    final relays = uri.queryParametersAll['relay'] ?? [];
    final secret = uri.queryParameters['secret'];

    if (relays.isEmpty) {
      throw ArgumentError('At least one relay is required in bunker URL');
    }

    if (secret == null) {
      throw ArgumentError('Secret parameter is required in bunker URL');
    }

    final keyPair = _eventSignerFactory.generateKeyPair();

    final localEventSigner = _eventSignerFactory.create(
      privateKey: keyPair.$1,
      publicKey: keyPair.$2,
    );

    final requestedPerms = clientMetadata?.perms?.join(',') ?? '';
    final metadata = clientMetadata?.displayInfo ?? {};

    final request = BunkerRequest(
      method: SignerMethod.connect,
      params: [
        remotePubkey,
        secret,
        // an empty perms string keeps the metadata in fourth position (NIP-46)
        if (requestedPerms.isNotEmpty || metadata.isNotEmpty) requestedPerms,
        if (metadata.isNotEmpty) jsonEncode(metadata),
      ],
    );

    final encryptedRequest = await localEventSigner.encryptNip44(
      plaintext: jsonEncode(request),
      recipientPubKey: remotePubkey,
    );

    final requestEvent = Nip01Event(
      pubKey: localEventSigner.getPublicKey(),
      kind: BunkerRequest.kKind,
      tags: [
        ["p", remotePubkey],
      ],
      content: encryptedRequest!,
    );

    final signedEvent = await localEventSigner.sign(requestEvent);

    // Subscribe BEFORE broadcasting to avoid missing the response,
    // since NIP-46 uses ephemeral events (kind 24133)
    final subscription = _subscribe(
      relays,
      Filter(
        authors: [remotePubkey],
        kinds: [BunkerRequest.kKind],
        pTags: [localEventSigner.getPublicKey()],
        since: someTimeAgo(),
      ),
    );

    await _relayPublishes.publish(signedEvent, relays: relays).done;

    try {
      await for (final event in _responses(subscription)) {
        final decryptedContent = await localEventSigner.decryptNip44(
          ciphertext: event.content,
          senderPubKey: remotePubkey,
        );

        final response = jsonDecode(decryptedContent!);

        if (response["id"] != request.id) continue;

        if (response["result"] == "auth_url") {
          if (authCallback != null) {
            authCallback(response["error"]);
          }
          continue;
        }

        if (response["result"] == "ack") {
          return BunkerConnection(
            privateKey: keyPair.$1,
            remotePubkey: remotePubkey,
            relays: relays,
          );
        }
      }
      return null;
    } finally {
      await subscription.close();
    }
  }

  /// Connects to a bunker using a nostr connect URL (nostrconnect://)
  /// authCallback is called with the auth URL if the bunker requires authentication
  Future<BunkerConnection?> connectWithNostrConnect(
    NostrConnect nostrConnect, {
    Function(String)? authCallback,
  }) async {
    final relays = nostrConnect.relays;
    final secret = nostrConnect.secret;

    if (relays.isEmpty) {
      throw ArgumentError('At least one relay is required in bunker URL');
    }

    final keyPair = nostrConnect.keyPair;
    final localEventSigner = _eventSignerFactory.create(
      privateKey: keyPair.privateKey!,
      publicKey: keyPair.publicKey,
    );

    final subscription = _subscribe(
      relays,
      Filter(
        kinds: [BunkerRequest.kKind],
        pTags: [localEventSigner.getPublicKey()],
        since: someTimeAgo(),
      ),
    );

    try {
      await for (final event in _responses(subscription)) {
        final decryptedContent = await localEventSigner.decryptNip44(
          ciphertext: event.content,
          senderPubKey: event.pubKey,
        );

        final response = jsonDecode(decryptedContent!);

        if (response["result"] == secret) {
          return BunkerConnection(
            privateKey: nostrConnect.keyPair.privateKey!,
            remotePubkey: event.pubKey,
            relays: relays,
          );
        }
      }
      return null;
    } finally {
      await subscription.close();
    }
  }

  RelayReq _subscribe(List<String> relays, Filter filter) => _relayReqs.req(
    relays: {
      for (final relay in cleanRelayUrls(relays)) relay: [filter],
    },
    closeOnEose: false,
  );

  /// Each response once, although every relay of the bunker delivers it.
  Stream<Nip01Event> _responses(RelayReq subscription) => subscription.events
      .map((received) => received.event)
      .distinctUnique()
      .timeout(Duration(seconds: kMaxWaitingTimeForConnectionSeconds));

  int someTimeAgo({Duration duration = const Duration(minutes: 5)}) {
    return (DateTime.now().millisecondsSinceEpoch ~/ 1000) - duration.inSeconds;
  }

  /// Creates a simple signer that delegates to this bunker instance
  Nip46EventSigner createSigner(
    BunkerConnection connection, {
    Function(String)? authCallback,
  }) {
    return Nip46EventSigner(
      connection: connection,
      relayReqs: _relayReqs,
      relayPublishes: _relayPublishes,
      authCallback: authCallback,
      eventSignerFactory: _eventSignerFactory,
    );
  }
}
