import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'nostr_crypto_js.dart';

@JS('DostrNoble')
external NostrCrypto? get _loadedNostrCrypto;

@JS('document')
external JSObject? get _document;

NostrCrypto? _nostrCrypto;
var _injected = false;

/// The bundle of `js/nostr_crypto.src.js`, injected into the page on first
/// use unless the page or the Web Worker already loaded it.
///
/// Throws a [StateError] when the bundle did not run, when a Web Worker did
/// not load it, or when the page loaded one of another version.
NostrCrypto get nostrCrypto => _nostrCrypto ??= _loadNostrCrypto();

NostrCrypto _loadNostrCrypto() {
  if (_loadedNostrCrypto == null && _document == null) {
    throw StateError(
      'The DostrNoble bundle is not loaded, and there is no page to inject it '
      'into: in a Web Worker, run importScripts on the js/nostr_crypto.js of '
      'the version you depend on, see the dostr_noble README',
    );
  }
  if (_loadedNostrCrypto == null && !_injected) {
    // once: under a Content-Security-Policy, each try adds a script and a report
    _injected = true;
    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..text = nostrCryptoJs;
    web.document.head!.append(script);
  }
  final loaded =
      _loadedNostrCrypto ??
      (throw StateError(
        'The DostrNoble bundle did not run: a Content-Security-Policy may '
        'block inline scripts, see the dostr_noble README',
      ));
  final version = loaded.version?.toDart;
  if (version != nostrCryptoVersion) {
    throw StateError(
      'The page loaded the DostrNoble bundle $version, but this '
      'dostr_noble needs $nostrCryptoVersion: serve the js/nostr_crypto.js '
      'of the version you depend on, see the dostr_noble README',
    );
  }
  return loaded;
}

extension type NostrCrypto._(JSObject _) implements JSObject {
  external JSString? get version;
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
