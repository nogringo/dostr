/// NIP-55 Android signer: log in, sign and encrypt with a signer app.
///
/// ```dart
/// const nip55Signer = Nip55Signer();
/// final login = await nip55Signer.login();
/// final signer = Nip55EventSigner(
///   publicKey: login!.pubkey,
///   nip55Signer: Nip55Signer(package: login.package),
/// );
/// ```
library;

export 'src/nip55_event_signer.dart';
export 'src/nip55_signer.dart';
