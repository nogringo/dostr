import 'dart:async';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip07/src/nip07_extension.dart';

const extensionPrivateKey =
    '0a47414ecfcdda1fe8374ec28629883cdd95287e353b3fd1a536c03d953f6cc2';

final extensionPubkey = Bip340.getPublicKey(extensionPrivateKey);

/// A NIP-07 extension that signs and encrypts as [account].
class FakeExtension implements Nip07Extension {
  /// The extension account, which the user can switch.
  Bip340Signer account = Bip340Signer(extensionPrivateKey);

  /// Holds every answer until [release].
  bool hang = false;

  /// Drops the `client` tags before signing, as some extensions do.
  bool stripClientTag = false;

  bool hasNip44 = true;

  /// Turns every answer into another, or throws to refuse the request.
  Object? Function(Object? answer) tamper = _same;

  /// The requests the extension received, in order.
  final requests = <String>[];

  final _held = <Completer<void>>[];

  static Object? _same(Object? answer) => answer;

  void release() {
    for (final held in _held) {
      held.complete();
    }
    _held.clear();
  }

  Future<Object?> _answer(
    String request,
    Future<Object?> Function() answer,
  ) async {
    requests.add(request);
    if (hang) {
      final held = Completer<void>();
      _held.add(held);
      await held.future;
    }
    return tamper(await answer());
  }

  @override
  Future<Object?> getPublicKey() =>
      _answer('getPublicKey', () async => account.publicKey);

  @override
  Future<Object?> signEvent(Map<String, Object?> event) =>
      _answer('signEvent', () async {
        final unsigned = Nip01Event.fromJson(event);
        final signed = await account.sign(
          unsigned.copyWith(
            pubkey: account.publicKey,
            tags: stripClientTag
                ? [
                    for (final tag in unsigned.tags)
                      if (tag.first != 'client') tag,
                  ]
                : null,
          ),
        );
        return signed.toJson();
      });

  @override
  Nip07Cipher? get nip04 => _FakeCipher(this, 'nip04');

  @override
  Nip07Cipher? get nip44 => hasNip44 ? _FakeCipher(this, 'nip44') : null;
}

class _FakeCipher implements Nip07Cipher {
  _FakeCipher(this._extension, this._scheme);

  final FakeExtension _extension;
  final String _scheme;

  Bip340Signer get _account => _extension.account;

  @override
  Future<Object?> encrypt(String recipientPubkey, String plaintext) =>
      _extension._answer(
        '$_scheme.encrypt',
        () => _scheme == 'nip04'
            ? _account.encryptNip04(
                plaintext: plaintext,
                recipientPubkey: recipientPubkey,
              )
            : _account.encryptNip44(
                plaintext: plaintext,
                recipientPubkey: recipientPubkey,
              ),
      );

  @override
  Future<Object?> decrypt(String senderPubkey, String ciphertext) =>
      _extension._answer(
        '$_scheme.decrypt',
        () => _scheme == 'nip04'
            ? _account.decryptNip04(
                ciphertext: ciphertext,
                senderPubkey: senderPubkey,
              )
            : _account.decryptNip44(
                ciphertext: ciphertext,
                senderPubkey: senderPubkey,
              ),
      );
}
