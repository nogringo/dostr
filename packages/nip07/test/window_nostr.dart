import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dostr_nip07/src/nip07_extension.dart';

/// Puts [extension] in `window.nostr`, as a browser extension does.
void installWindowNostr(Nip07Extension extension) {
  final nostr = JSObject()
    ..['getPublicKey'] = (() => _promise(extension.getPublicKey())).toJS
    ..['signEvent'] = ((JSAny? event) => _promise(
      extension.signEvent(
        jsonDecode(_stringify(event)) as Map<String, Object?>,
      ),
    )).toJS;
  if (extension.nip04 case final nip04?) nostr['nip04'] = _jsCipher(nip04);
  if (extension.nip44 case final nip44?) nostr['nip44'] = _jsCipher(nip44);
  globalContext['nostr'] = nostr;
}

void removeWindowNostr() => globalContext.delete('nostr'.toJS);

JSObject _jsCipher(Nip07Cipher cipher) => JSObject()
  ..['encrypt'] = ((JSString pubkey, JSString plaintext) => _promise(
    cipher.encrypt(pubkey.toDart, plaintext.toDart),
  )).toJS
  ..['decrypt'] = ((JSString pubkey, JSString ciphertext) => _promise(
    cipher.decrypt(pubkey.toDart, ciphertext.toDart),
  )).toJS;

JSPromise<JSAny?> _promise(Future<Object?> answer) =>
    answer.then((value) => value.jsify()).toJS;

// JSON keeps ints as ints, where dartify gives doubles on dart2wasm
@JS('JSON.stringify')
external String _stringify(JSAny? value);
