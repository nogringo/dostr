import 'package:bip340/bip340.dart' as bip340;
import 'package:ndk_nip01/hex.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_isolates/ndk_isolates.dart';

/// Pure dart event verifier using https://pub.dev/packages/bip340
/// can be slow on mobile devices
class Bip340EventVerifier implements EventVerifier {
  bool useIsolate = true;

  Bip340EventVerifier({this.useIsolate = true});

  @override
  Future<bool> verify(Nip01Event event) async {
    final sig = event.sig;
    if (sig == null ||
        !isLowercaseHex(sig, length: 128) ||
        !isLowercaseHex(event.pubKey, length: 64) ||
        !event.hasValidId) {
      return false;
    }
    return useIsolate
        ? await IsolateManager.instance.runInComputeIsolate<Nip01Event, bool>(
            _verifySig,
            event,
          )
        : _verifySig(event);
  }
}

// The bip340 package throws on some malformed input instead of returning false.
bool _verifySig(Nip01Event event) {
  try {
    return bip340.verify(event.pubKey, event.id, event.sig!);
  } catch (_) {
    return false;
  }
}
