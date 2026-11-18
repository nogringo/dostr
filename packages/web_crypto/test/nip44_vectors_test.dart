@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:crypto/crypto.dart';
import 'package:dostr_nip01/hex.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';
import 'package:dostr_web_crypto/src/js_interop.dart';
import 'package:test/test.dart';

// The browser cannot read files: the VM side of the test reads the vectors
// that dostr_nip44 checks.
Future<Map<String, dynamic>> _loadVectors() async {
  final channel = spawnHybridCode(r'''
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

void hybridMain(StreamChannel<Object?> channel) {
  channel.sink.add(File('../nip44/test/nip44.vectors.json').readAsStringSync());
}
''');
  final json = await channel.stream.first as String;
  return (jsonDecode(json) as Map<String, dynamic>)['v2']
      as Map<String, dynamic>;
}

List<Map<String, dynamic>> _cases(Map<String, dynamic> group, String name) =>
    (group[name] as List).cast<Map<String, dynamic>>();

JSString _js(Object? value) => (value as String).toJS;

JSUint8Array _bytes(String hex) => hexToBytes(hex).toJS;

String _hex(JSUint8Array bytes) => bytesToHex(bytes.toDart);

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

String _publicKey(String privateKey) =>
    nostrCrypto.getPublicKey(privateKey.toJS).toDart;

void main() {
  late Map<String, dynamic> valid;
  late Map<String, dynamic> invalid;

  setUpAll(() async {
    final vectors = await _loadVectors();
    valid = vectors['valid'] as Map<String, dynamic>;
    invalid = vectors['invalid'] as Map<String, dynamic>;
  });

  test('conversation keys', () {
    for (final (i, v) in _cases(valid, 'get_conversation_key').indexed) {
      expect(
        _hex(nostrCrypto.nip44ConversationKey(_js(v['sec1']), _js(v['pub2']))),
        v['conversation_key'],
        reason: 'vector $i',
      );
    }
  });

  test('rejects invalid conversation keys', () {
    for (final v in _cases(invalid, 'get_conversation_key')) {
      expect(
        () => nostrCrypto.nip44ConversationKey(_js(v['sec1']), _js(v['pub2'])),
        throwsA(anything),
        reason: v['note'],
      );
    }
  });

  test('encrypts and decrypts', () {
    for (final (i, v) in _cases(valid, 'encrypt_decrypt').indexed) {
      final conversationKey = nostrCrypto.nip44ConversationKey(
        _js(v['sec1']),
        _publicKey(v['sec2']).toJS,
      );
      expect(_hex(conversationKey), v['conversation_key'], reason: 'vector $i');
      expect(
        nostrCrypto
            .nip44Encrypt(
              conversationKey,
              _js(v['plaintext']),
              _bytes(v['nonce']),
            )
            .toDart,
        v['payload'],
        reason: 'vector $i',
      );
      expect(
        nostrCrypto.nip44Decrypt(conversationKey, _js(v['payload'])).toDart,
        v['plaintext'],
        reason: 'vector $i',
      );
    }
  });

  test('WebSigner decrypts the payloads of the vectors', () async {
    for (final (i, v) in _cases(valid, 'encrypt_decrypt').indexed) {
      final signer = WebSigner(v['sec2']);
      expect(
        await signer.decryptNip44(
          ciphertext: v['payload'],
          senderPubkey: _publicKey(v['sec1']),
        ),
        v['plaintext'],
        reason: 'vector $i',
      );
    }
  });

  test('encrypts long messages', () {
    for (final (i, v) in _cases(valid, 'encrypt_decrypt_long_msg').indexed) {
      final conversationKey = _bytes(v['conversation_key']);
      final plaintext = (v['pattern'] as String) * (v['repeat'] as int);
      final payload = nostrCrypto
          .nip44Encrypt(conversationKey, plaintext.toJS, _bytes(v['nonce']))
          .toDart;

      expect(_sha256(plaintext), v['plaintext_sha256'], reason: 'vector $i');
      expect(_sha256(payload), v['payload_sha256'], reason: 'vector $i');
      expect(
        nostrCrypto.nip44Decrypt(conversationKey, payload.toJS).toDart,
        plaintext,
        reason: 'vector $i',
      );
    }
  });

  // https://github.com/nostr-protocol/nips/blob/master/44.md#extended-length-prefix-test-vectors
  test('encrypts messages around the extended length prefix', () {
    final conversationKey = _bytes(
      'c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d',
    );
    for (final (length, payloadSha256) in [
      (
        65535,
        '6d8c2810d1e870fbaa1f0a0937126cca837a15f9260e27060c331d70a3c0bc84',
      ),
      (
        65536,
        'b7b4edb36ba92e267d322d56d9aebc22e7fa96ff52e3c12adc07f07a43cbc616',
      ),
      (
        65537,
        'eeb7c7c5373894ea2c1547cfd3ccb15d5a0b2d619da852e5c79df792dcc9e435',
      ),
    ]) {
      final plaintext = 'a' * length;
      final payload = nostrCrypto
          .nip44Encrypt(conversationKey, plaintext.toJS, _bytes('${'0' * 63}1'))
          .toDart;

      expect(_sha256(payload), payloadSha256, reason: '$length bytes');
      expect(
        nostrCrypto.nip44Decrypt(conversationKey, payload.toJS).toDart,
        plaintext,
        reason: '$length bytes',
      );
    }
  });

  test('rejects invalid payloads', () {
    for (final (i, v) in _cases(invalid, 'decrypt').indexed) {
      expect(
        () => nostrCrypto.nip44Decrypt(
          _bytes(v['conversation_key']),
          _js(v['payload']),
        ),
        throwsA(anything),
        reason: '${v['note']} (vector $i)',
      );
    }
  });
}
