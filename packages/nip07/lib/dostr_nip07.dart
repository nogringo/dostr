/// NIP-07 signer: sign and encrypt with the user's browser extension.
///
/// ```dart
/// if (Nip07Signer.isAvailable) {
///   final signer = await Nip07Signer.connect();
/// }
/// ```
library;

export 'src/nip07_signer_stub.dart'
    if (dart.library.js_interop) 'src/nip07_signer_web.dart';
