@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_web_crypto/dostr_web_crypto.dart';
import 'package:dostr_web_crypto/src/nostr_crypto_js.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void _runJs(String code) => globalContext.callMethod('eval'.toJS, code.toJS);

int get _scriptCount => web.document.head!.querySelectorAll('script').length;

void main() {
  final privateKey = Bip340.generateKeyPair().privateKey;

  // The tests share the page and the loader state, so they run in this order.
  test('a bundle of another version on the page throws a StateError', () {
    final scripts = _scriptCount;
    _runJs('globalThis.DostrWebCrypto = { version: "stale" };');

    expect(() => WebSigner(privateKey), throwsStateError);
    expect(_scriptCount, scripts);
  });

  test('a bundle that does not run is injected once', () {
    _runJs('''
      delete globalThis.DostrWebCrypto;
      Object.defineProperty(globalThis, 'DostrWebCrypto', {
        get: () => undefined,
        set: () => {},
        configurable: true,
      });
    ''');
    final scripts = _scriptCount;

    expect(() => WebSigner(privateKey), throwsStateError);
    expect(() => WebSigner(privateKey), throwsStateError);
    expect(_scriptCount, scripts + 1);
  });

  test('a bundle the page loads later is used', () {
    _runJs('delete globalThis.DostrWebCrypto;');
    _runJs(nostrCryptoJs);

    expect(WebSigner(privateKey).publicKey, Bip340.getPublicKey(privateKey));
  });
}
