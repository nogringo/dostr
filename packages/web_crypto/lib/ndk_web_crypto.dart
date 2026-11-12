/// Fast BIP-340 signing and verification of Nostr events on the web, with
/// @noble/curves through JS interop. On other platforms the classes throw.
library;

export 'src/web_event_signer_stub.dart'
    if (dart.library.js_interop) 'src/web_event_signer_web.dart';
export 'src/web_event_verifier_stub.dart'
    if (dart.library.js_interop) 'src/web_event_verifier_web.dart';
