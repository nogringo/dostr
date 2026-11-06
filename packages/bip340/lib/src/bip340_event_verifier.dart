import 'package:bip340/bip340.dart' as bip340;
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_core/shared/isolates/isolate_manager.dart';

/// Pure dart event verifier using https://pub.dev/packages/bip340
/// can be slow on mobile devices
class Bip340EventVerifier implements EventVerifier {
  bool useIsolate = true;

  Bip340EventVerifier({this.useIsolate = true});

  @override
  Future<bool> verify(Nip01Event event) async {
    if (event.sig == null) {
      return false;
    }
    if (!event.hasValidId) return false;
    return useIsolate
        ? await IsolateManager.instance.runInComputeIsolate<Nip01Event, bool>((
            event,
          ) {
            return bip340.verify(event.pubKey, event.id, event.sig!);
          }, event)
        : bip340.verify(event.pubKey, event.id, event.sig!);
  }
}
