/// NIP-07 signer: sign and encrypt with the user's browser extension.
///
/// ```dart
/// if (await Nip07Signer.waitForExtension()) {
///   final signer = await Nip07Signer.connect();
/// }
/// ```
library;

export 'src/nip07_signer.dart' show Nip07Signer;
