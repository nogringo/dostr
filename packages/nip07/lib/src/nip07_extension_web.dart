import 'dart:js_interop';

import 'nip07_extension.dart';

const supportsNip07 = true;

Nip07Extension? windowNostr() => switch (_windowNostr) {
  final nostr? => _WindowNostr(nostr),
  null => null,
};

@JS('nostr')
external _Nostr? get _windowNostr;

extension type _Nostr._(JSObject _) implements JSObject {
  external _Cipher? get nip04;
  external _Cipher? get nip44;
  external JSPromise<JSAny?> getPublicKey();
  external JSPromise<JSAny?> signEvent(JSAny? event);
}

extension type _Cipher._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> encrypt(String pubkey, String text);
  external JSPromise<JSAny?> decrypt(String pubkey, String text);
}

class _WindowNostr implements Nip07Extension {
  _WindowNostr(this._nostr);

  final _Nostr _nostr;

  @override
  Future<Object?> getPublicKey() => _answer(_nostr.getPublicKey());

  @override
  Future<Object?> signEvent(Map<String, Object?> event) =>
      _answer(_nostr.signEvent(event.jsify()));

  @override
  Nip07Cipher? get nip04 => _WindowCipher.of(_nostr.nip04);

  @override
  Nip07Cipher? get nip44 => _WindowCipher.of(_nostr.nip44);
}

class _WindowCipher implements Nip07Cipher {
  _WindowCipher(this._cipher);

  static _WindowCipher? of(_Cipher? cipher) =>
      cipher == null ? null : _WindowCipher(cipher);

  final _Cipher _cipher;

  @override
  Future<Object?> encrypt(String recipientPubkey, String plaintext) =>
      _answer(_cipher.encrypt(recipientPubkey, plaintext));

  @override
  Future<Object?> decrypt(String senderPubkey, String ciphertext) =>
      _answer(_cipher.decrypt(senderPubkey, ciphertext));
}

Future<Object?> _answer(JSPromise<JSAny?> promise) async =>
    (await promise.toDart).dartify();
