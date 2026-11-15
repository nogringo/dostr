/// NIP-07 signer: sign and encrypt with the user's browser extension.
///
/// ```dart
/// final signer = Nip07Signer();
/// if (signer.canSign()) {
///   final pubkey = await signer.getPublicKeyAsync();
/// }
/// ```
library;

export 'src/nip07_signer_stub.dart'
    if (dart.library.js_interop) 'src/nip07_signer_web.dart';
