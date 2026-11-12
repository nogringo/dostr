import 'package:bip340/bip340.dart' as bip340;
import 'package:dostr_nip01/hex.dart';
import 'package:dostr_nip01/dostr_nip01.dart';

/// Pure dart event verifier using https://pub.dev/packages/bip340
/// can be slow on mobile devices
class Bip340EventVerifier implements EventVerifier {
  @override
  Future<bool> verify(Nip01Event event) async {
    final sig = event.sig;
    if (sig == null ||
        !isLowercaseHex(sig, length: 128) ||
        !isLowercaseHex(event.pubKey, length: 64) ||
        !event.hasValidId) {
      return false;
    }
    // the bip340 package throws on some malformed input instead of returning false
    try {
      return bip340.verify(event.pubKey, event.id, sig);
    } catch (_) {
      return false;
    }
  }
}
