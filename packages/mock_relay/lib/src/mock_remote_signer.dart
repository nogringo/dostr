import 'dart:convert';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_nip44/dostr_nip44.dart';

import 'mock_relay.dart';

/// NIP-46
const _kNip46Kind = 24133;

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

  /// the method of every request, in the order they came
  final List<String> receivedMethods = [];

  /// answers that replace the usual one, by method, such as
  /// `{'error': 'denied'}`
  final Map<String, Map<String, dynamic>> answers = {};

  /// sent as an auth challenge before each answer
  String? authUrl;

  /// event contents sent to the client before each answer, as they are
  List<String> contentsBeforeAnswer = [];

  MockRemoteSigner(Iterable<MockRelay> relays) {
    for (final relay in relays) {
      relay.onEvent = (event) => _onEvent(relay, event);
    }
  }

  Future<void> _onEvent(MockRelay relay, Nip01Event event) async {
    if (event.kind != _kNip46Kind) return;
    if (event.getFirstTag('p') != publicKey) return;

    final request = jsonDecode(
      Nip44.decryptMessage(
        event.content,
        recipientPrivateKey: privateKey,
        senderPublicKey: event.pubkey,
      ),
    );
    for (final content in contentsBeforeAnswer) {
      relay.publish(_signed(event.pubkey, content));
    }
    final authUrl = this.authUrl;
    if (authUrl != null) {
      await _respond(relay, event.pubkey, {
        'id': request['id'],
        'result': 'auth_url',
        'error': authUrl,
      });
    }
    Map<String, dynamic> response;
    try {
      response = await _answer(
        relay,
        request['method'] as String,
        request['params'] as List<dynamic>,
      );
    } catch (error) {
      response = {'error': '$error'};
    }
    response['id'] = request['id'];
    await _respond(relay, event.pubkey, response);
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
      _signed(
        recipient,
        Nip44.encryptMessage(
          jsonEncode(response),
          senderPrivateKey: privateKey,
          recipientPublicKey: recipient,
        ),
      ),
    );
  }

  Nip01Event _signed(String recipient, String content) => Bip340.signEvent(
    event: Nip01Event(
      pubkey: publicKey,
      kind: _kNip46Kind,
      tags: [
        ['p', recipient],
      ],
      content: content,
    ),
    privateKey: privateKey,
  );

  Future<Map<String, dynamic>> _answer(
    MockRelay relay,
    String method,
    List<dynamic> params,
  ) async {
    receivedMethods.add(method);
    if (method == 'connect') lastConnectParams = params;
    final answer = answers[method];
    if (answer != null) return {...answer};

    switch (method) {
      case 'connect':
        return {'result': 'ack'};
      case 'ping':
        return {'result': 'pong'};
      case 'logout':
        return {'result': 'ack'};
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
            pubkey: publicKey,
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
        return {
          'result': Nip04.encrypt(
            params[1],
            senderPrivateKey: privateKey,
            recipientPublicKey: params[0],
          ),
        };
      case 'nip04_decrypt':
        return {
          'result': Nip04.decrypt(
            params[1],
            recipientPrivateKey: privateKey,
            senderPublicKey: params[0],
          ),
        };
      case 'nip44_encrypt':
        return {
          'result': Nip44.encryptMessage(
            params[1],
            senderPrivateKey: privateKey,
            recipientPublicKey: params[0],
          ),
        };
      case 'nip44_decrypt':
        return {
          'result': Nip44.decryptMessage(
            params[1],
            recipientPrivateKey: privateKey,
            senderPublicKey: params[0],
          ),
        };
      default:
        return {'error': 'Unknown method: $method'};
    }
  }
}
