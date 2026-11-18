import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:rxdart/rxdart.dart';

import 'bunker_connection.dart';
import 'bunker_request.dart';
import 'nip46_client_metadata.dart';
import 'nip46_message.dart';
import 'nip46_signer.dart';
import 'nostr_connect.dart';

/// Connects to NIP-46 remote signers, and builds a [Nip46Signer] for each
/// connection.
class Bunkers {
  final RelayReqs _relayReqs;
  final RelayPublishes _relayPublishes;
  final LocalSignerFactory _signerFactory;

  Bunkers({
    required RelayReqs relayReqs,
    required RelayPublishes relayPublishes,
    required LocalSignerFactory signerFactory,
  }) : _relayReqs = relayReqs,
       _relayPublishes = relayPublishes,
       _signerFactory = signerFactory;

  /// Connects to the remote signer of a `bunker://` url.
  ///
  /// [authCallback] gets the url of an auth challenge, where the user
  /// approves the connection, and only an https one. Throws an
  /// [ArgumentError] for a url without a hex pubkey or a relay, a
  /// [SignerRequestRejectedException] when the remote signer refuses, and a
  /// [SignerRequestFailedException] when no relay takes the request or the
  /// remote signer accepts nothing within [timeout].
  Future<BunkerConnection> connectWithBunkerUrl(
    String bunkerUrl, {
    void Function(String url)? authCallback,
    Nip46ClientMetadata? clientMetadata,
    Duration timeout = Nip46Signer.defaultConnectTimeout,
  }) async {
    final uri = Uri.parse(bunkerUrl);
    if (uri.scheme != 'bunker') {
      throw ArgumentError('Invalid bunker URL scheme');
    }

    final remotePubkey = uri.host;
    if (!isHexPubkey(remotePubkey)) {
      throw ArgumentError('The bunker URL has no hex remote signer pubkey');
    }
    final relays = (uri.queryParametersAll['relay'] ?? [])
        .map(RelayUrl.tryParse)
        .nonNulls
        .toList();
    final secret = uri.queryParameters['secret'];

    if (relays.isEmpty) {
      throw ArgumentError('At least one relay is required in bunker URL');
    }

    final privateKey = _signerFactory.generateKeyPair().privateKey;
    final localSigner = _signerFactory.create(privateKey);

    final metadata = clientMetadata?.displayInfo ?? const {};
    final params = [
      remotePubkey,
      secret ?? '',
      clientMetadata?.perms?.join(',') ?? '',
      if (metadata.isNotEmpty) jsonEncode(metadata),
    ];
    // an empty optional param holds the place of the ones after it (NIP-46)
    while (params.length > 1 && params.last.isEmpty) {
      params.removeLast();
    }
    final request = BunkerRequest(method: 'connect', params: params);

    final subscription = _subscribe(
      relays,
      Filter(
        authors: [remotePubkey],
        kinds: [BunkerRequest.kKind],
        pTags: [localSigner.publicKey],
        since: _fiveMinutesAgo(),
      ),
    );

    Future<BunkerConnection> accepted() async {
      if (!await isServed(subscription)) {
        throw SignerRequestFailedException(
          'No relay took the subscription for the answer',
          requestId: request.id,
          cause: subscription.outcomes,
        );
      }
      final outcomes = await _relayPublishes
          .publish(
            await signedRequestEvent(
              localSigner,
              request,
              remotePubkey: remotePubkey,
            ),
            relays: relays,
          )
          .done;
      if (noRelayTook(outcomes)) {
        throw SignerRequestFailedException(
          'No relay took the connect request',
          requestId: request.id,
          cause: outcomes,
        );
      }

      await for (final (_, message) in _messages(subscription, localSigner)) {
        if (message['id'] != request.id) continue;

        final result = message['result'];
        final error = message['error'];
        if (result == 'auth_url') {
          final url = httpsAuthUrl(error);
          if (url != null) authCallback?.call(url);
          continue;
        }
        if (error != null) {
          throw SignerRequestRejectedException(
            requestId: request.id,
            originalMessage: '$error',
          );
        }
        if (result == 'ack' || (secret != null && result == secret)) {
          return BunkerConnection(
            privateKey: privateKey,
            remotePubkey: remotePubkey,
            relays: relays,
          );
        }
        throw SignerRequestFailedException(
          'The remote signer answered connect with neither ack nor the secret',
          requestId: request.id,
          cause: result,
        );
      }
      throw _closedBeforeAnswer(request.id);
    }

    return _withTimeout(
      accepted(),
      subscription,
      timeout,
      requestId: request.id,
    );
  }

  /// Creates a nostr connect invitation (nostrconnect://) with a fresh key pair
  NostrConnect createNostrConnect({
    required List<RelayUrl> relays,
    Nip46ClientMetadata? clientMetadata,
  }) {
    final (:privateKey, :publicKey) = _signerFactory.generateKeyPair();
    return NostrConnect(
      relays: relays,
      privateKey: privateKey,
      publicKey: publicKey,
      clientMetadata: clientMetadata,
    );
  }

  /// Waits for a remote signer to accept [nostrConnect], once the user gave
  /// it the [NostrConnect.nostrConnectURL].
  ///
  /// Throws a [SignerRequestFailedException] when none accepts within
  /// [timeout].
  Future<BunkerConnection> connectWithNostrConnect(
    NostrConnect nostrConnect, {
    Duration timeout = Nip46Signer.defaultConnectTimeout,
  }) async {
    final localSigner = _signerFactory.create(nostrConnect.privateKey);
    final subscription = _subscribe(
      nostrConnect.relays,
      Filter(
        kinds: [BunkerRequest.kKind],
        pTags: [localSigner.publicKey],
        since: _fiveMinutesAgo(),
      ),
    );

    Future<BunkerConnection> accepted() async {
      await for (final (event, message) in _messages(
        subscription,
        localSigner,
      )) {
        if (message['result'] == nostrConnect.secret) {
          return BunkerConnection(
            privateKey: nostrConnect.privateKey,
            remotePubkey: event.pubkey,
            relays: nostrConnect.relays,
          );
        }
      }
      throw _closedBeforeAnswer();
    }

    return _withTimeout(accepted(), subscription, timeout);
  }

  RelayReq _subscribe(List<RelayUrl> relays, Filter filter) => _relayReqs.req(
    relays: {
      for (final relay in relays) relay: [filter],
    },
    closeOnEose: false,
  );

  /// The messages [subscription] receives for [localSigner], each once
  /// although every relay delivers it, without those it cannot read.
  Stream<(Nip01Event, Map<String, dynamic>)> _messages(
    RelayReq subscription,
    NostrSigner localSigner,
  ) async* {
    final events = subscription.events
        .map((received) => received.event)
        .distinctUnique();
    await for (final event in events) {
      final message = await readMessage(localSigner, event);
      if (message != null) yield (event, message);
    }
  }

  static SignerRequestFailedException _closedBeforeAnswer([
    String? requestId,
  ]) => SignerRequestFailedException(
    'The subscription closed before the remote signer answered',
    requestId: requestId,
  );

  /// [answer], unless [timeout] passes first. Closes [subscription] either
  /// way.
  Future<T> _withTimeout<T>(
    Future<T> answer,
    RelayReq subscription,
    Duration timeout, {
    String? requestId,
  }) async {
    try {
      return await answer.timeout(
        timeout,
        onTimeout: () => throw SignerRequestFailedException(
          'No remote signer answered within $timeout',
          requestId: requestId,
        ),
      );
    } finally {
      await subscription.close();
    }
  }

  static int _fiveMinutesAgo() =>
      DateTime.now()
          .subtract(const Duration(minutes: 5))
          .millisecondsSinceEpoch ~/
      1000;

  /// A signer for [connection], once the remote signer sent the user's
  /// pubkey, see [Nip46Signer.connect].
  Future<Nip46Signer> createSigner(
    BunkerConnection connection, {
    void Function(String url)? authCallback,
    EventVerifier? verifier,
    Duration timeout = Nip46Signer.defaultConnectTimeout,
  }) => Nip46Signer.connect(
    connection: connection,
    relayReqs: _relayReqs,
    relayPublishes: _relayPublishes,
    authCallback: authCallback,
    verifier: verifier,
    signerFactory: _signerFactory,
    timeout: timeout,
  );
}
