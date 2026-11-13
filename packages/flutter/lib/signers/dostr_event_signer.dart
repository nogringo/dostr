/// Auto-platform Nostr event signer that uses the best implementation
/// for the current platform.
///
/// On web: uses [WebEventSigner] from `dostr_web_crypto` (fast JS crypto via @noble/curves)
/// On native (mobile/desktop): uses [Bip340EventSigner] (pure Dart)
///
/// Give [DostrEventSignerFactory] to `Accounts` so the accounts it logs in sign
/// with it.
///
/// The conditional export below works like this:
/// - Web compiler sees `dart.library.js_interop` → loads `dostr_event_signer_web.dart`
/// - Native compiler does not → falls back to `dostr_event_signer_native.dart`
library;

export 'src/dostr_event_signer_native.dart'
    if (dart.library.js_interop) 'src/dostr_event_signer_web.dart';
