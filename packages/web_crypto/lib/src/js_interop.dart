import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'nostr_crypto_js.dart';

@JS('NostrCrypto')
external NostrCrypto? get _loadedNostrCrypto;

/// The bundle of `js/nostr_crypto.src.js`, injected into the page on first
/// use unless the page already loaded it.
final NostrCrypto nostrCrypto = _loadNostrCrypto();

NostrCrypto _loadNostrCrypto() {
  if (_loadedNostrCrypto case final loaded?) return loaded;
  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..text = nostrCryptoJs;
  web.document.head!.append(script);
  return _loadedNostrCrypto ??
      (throw StateError(
        'The NostrCrypto bundle did not run: a Content-Security-Policy may '
        'block inline scripts, see the dostr_web_crypto README',
      ));
}

extension type NostrCrypto._(JSObject _) implements JSObject {
  external JSBoolean verifySignature(
    JSString signatureHex,
    JSString hashHex,
    JSString publicKeyHex,
  );
  external JSString signEvent(JSString privateKeyHex, JSString hashHex);
  external JSString getPublicKey(JSString privateKeyHex);
  external JSString nip04Encrypt(
    JSString privateKeyHex,
    JSString publicKeyHex,
    JSString plaintext,
  );
  external JSString nip04Decrypt(
    JSString privateKeyHex,
    JSString publicKeyHex,
    JSString ciphertext,
  );
  external JSUint8Array nip44ConversationKey(
    JSString privateKeyHex,
    JSString publicKeyHex,
  );
  external JSString nip44Encrypt(
    JSUint8Array conversationKey,
    JSString plaintext, [
    JSUint8Array nonce,
  ]);
  external JSString nip44Decrypt(
    JSUint8Array conversationKey,
    JSString payloadB64,
  );
}
