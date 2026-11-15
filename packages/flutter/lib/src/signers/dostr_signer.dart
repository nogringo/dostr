/// Auto-platform Nostr signer that uses the best implementation
/// for the current platform.
///
/// On web: uses [WebSigner] from `dostr_web_crypto` (fast JS crypto via @noble/curves)
/// On native (mobile/desktop): uses [Bip340Signer] (pure Dart)
///
/// Give [DostrSignerFactory] to `Accounts` so the accounts it logs in sign
/// with it.
///
/// The conditional export below works like this:
/// - Web compiler sees `dart.library.js_interop` → loads `dostr_signer_web.dart`
/// - Native compiler does not → falls back to `dostr_signer_native.dart`
library;

export 'dostr_signer_native.dart'
    if (dart.library.js_interop) 'dostr_signer_web.dart';
