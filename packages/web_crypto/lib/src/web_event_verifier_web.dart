import 'dart:js_interop';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip01/hex.dart';

import 'js_interop.dart';

/// Verifies BIP-340 event signatures with @noble/curves through JS interop.
class WebEventVerifier implements EventVerifier {
  const WebEventVerifier();

  @override
  Future<bool> verify(Nip01Event event) async {
    final sig = event.sig;
    if (sig == null ||
        !isLowercaseHex(sig, length: 128) ||
        !isLowercaseHex(event.pubkey, length: 64) ||
        !event.hasValidId) {
      return false;
    }
    return nostrCrypto
        .verifySignature(sig.toJS, event.id.toJS, event.pubkey.toJS)
        .toDart;
  }
}
