import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip01/hex.dart';

import 'bip340.dart';

/// Pure Dart event verifier, on the calling isolate.
class Bip340EventVerifier implements EventVerifier {
  @override
  Future<bool> verify(Nip01Event event) async {
    final sig = event.sig;
    if (sig == null ||
        !isLowercaseHex(sig, length: 128) ||
        !isLowercaseHex(event.pubkey, length: 64) ||
        !event.hasValidId) {
      return false;
    }
    return Bip340.verify(
      message: event.id,
      signature: sig,
      publicKey: event.pubkey,
    );
  }
}
