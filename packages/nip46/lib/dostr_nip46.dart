/// NIP-46 remote signing: connect to a bunker and sign through it.
///
/// ```dart
/// final bunkers = Bunkers(
///   relayReqs: relayReqs,
///   relayPublishes: relayPublishes,
///   eventSignerFactory: Bip340EventSignerFactory(),
/// );
/// final connection = await bunkers.connectWithBunkerUrl('bunker://...');
/// final signer = bunkers.createSigner(connection!);
/// await signer.getPublicKeyAsync();
/// ```
library;

export 'src/bunker_connection.dart';
export 'src/bunker_request.dart';
export 'src/bunkers.dart';
export 'src/nip46_client_metadata.dart';
export 'src/nip46_event_signer.dart';
export 'src/nostr_connect.dart';
