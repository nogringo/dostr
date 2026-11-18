/// NIP-55 Android signer: log in, sign and encrypt with a signer app.
///
/// ```dart
/// const signerApp = Nip55SignerApp();
/// final login = await signerApp.login();
/// final signer = Nip55Signer(
///   publicKey: login.pubkey,
///   signerApp: Nip55SignerApp(package: login.package),
/// );
/// ```
library;

export 'src/nip55_signer.dart';
export 'src/nip55_signer_app.dart';
