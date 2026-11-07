import 'dart:convert';

import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip44/ndk_nip44.dart';
import 'package:ndk_nip46/ndk_nip46.dart';

import 'package:ndk_mock_relay/ndk_mock_relay.dart';

/// A NIP-46 remote signer that answers the requests its relays receive, on
/// the relay each request came through.
class MockRemoteSigner {
  static const String privateKey =
      'e7158a4379e743889f8ea8cfcdf4bd904cdfde4ff8a1c545aad4590d8a3acccc';
  static const String publicKey =
      '52f58988d7aaea17936581db7ff19074633557fad37f354323cea579b1025cef';

  /// shifts the created_at of the events it signs
  int signEventCreatedAtOffsetSeconds = 0;

  /// replaces the content of the events it signs
  String? signEventContentOverride;

  /// the relays switch_relays answers, null keeps the current ones
  List<String>? switchRelaysResult;

  /// the params of the last connect request
  List<dynamic>? lastConnectParams;

  MockRemoteSigner(Iterable<MockRelay> relays) {
    for (final relay in relays) {
      relay.onEvent = (event) => _onEvent(relay, event);
    }
  }

  Future<void> _onEvent(MockRelay relay, Nip01Event event) async {
    if (event.kind != BunkerRequest.kKind) return;
    if (event.getFirstTag('p') != publicKey) return;

    final request = jsonDecode(
      await Nip44.decryptMessage(event.content, privateKey, event.pubKey),
    );
    final response = await _answer(
      relay,
      request['method'] as String,
      request['params'] as List<dynamic>,
    );
    response['id'] = request['id'];
    await _respond(relay, event.pubKey, response);
  }

  /// Answers a nostrconnect:// invitation on [relay], as a signer app does
  /// once the user scans it.
  Future<void> acceptNostrConnect(MockRelay relay, String nostrConnectUrl) {
    final uri = Uri.parse(nostrConnectUrl);
    return _respond(relay, uri.host, {
      'id': 'nostrconnect',
      'result': uri.queryParameters['secret'],
    });
  }

  Future<void> _respond(
    MockRelay relay,
    String recipient,
    Map<String, dynamic> response,
  ) async {
    relay.publish(
      Bip340.signEvent(
        event: Nip01Event(
          pubKey: publicKey,
          kind: BunkerRequest.kKind,
          tags: [
            ['p', recipient],
          ],
          content: await Nip44.encryptMessage(
            jsonEncode(response),
            privateKey,
            recipient,
          ),
        ),
        privateKey: privateKey,
      ),
    );
  }

  Future<Map<String, dynamic>> _answer(
    MockRelay relay,
    String method,
    List<dynamic> params,
  ) async {
    switch (method) {
      case 'connect':
        lastConnectParams = params;
        return {'result': 'ack'};
      case 'ping':
        return {'result': 'pong'};
      case 'switch_relays':
        final relays = switchRelaysResult;
        return {'result': relays == null ? null : jsonEncode(relays)};
      case 'get_relays':
        return {
          'result': {
            relay.url: {'read': true, 'write': true},
          },
        };
      case 'get_public_key':
        return {'result': publicKey};
      case 'sign_event':
        final unsigned = jsonDecode(params[0] as String);
        final signed = Bip340.signEvent(
          event: Nip01Event(
            pubKey: publicKey,
            kind: unsigned['kind'] as int,
            tags: [
              for (final tag in unsigned['tags'] as List)
                List<String>.from(tag),
            ],
            content: signEventContentOverride ?? unsigned['content'] as String,
            createdAt:
                (unsigned['created_at'] as int) +
                signEventCreatedAtOffsetSeconds,
          ),
          privateKey: privateKey,
        );
        return {'result': signed.toJsonString()};
      case 'nip04_encrypt':
        return {'result': Nip04.encrypt(privateKey, params[0], params[1])};
      case 'nip04_decrypt':
        return {'result': Nip04.decrypt(privateKey, params[0], params[1])};
      case 'nip44_encrypt':
        return {
          'result': await Nip44.encryptMessage(
            params[1],
            privateKey,
            params[0],
          ),
        };
      case 'nip44_decrypt':
        return {
          'result': await Nip44.decryptMessage(
            params[1],
            privateKey,
            params[0],
          ),
        };
      default:
        return {'error': 'Unknown method: $method'};
    }
  }
}
