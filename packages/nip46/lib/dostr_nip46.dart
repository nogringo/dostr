/// NIP-46 remote signing: connect to a bunker and sign through it.
///
/// ```dart
/// final bunkers = Bunkers(
///   relayReqs: relayReqs,
///   relayPublishes: relayPublishes,
///   signerFactory: Bip340SignerFactory(),
/// );
/// final connection = await bunkers.connectWithBunkerUrl('bunker://...');
/// final signer = await bunkers.createSigner(connection);
/// ```
library;

export 'src/bunker_connection.dart';
export 'src/bunker_request.dart';
export 'src/bunkers.dart';
export 'src/nip46_client_metadata.dart';
export 'src/nip46_signer.dart';
export 'src/nostr_connect.dart';
