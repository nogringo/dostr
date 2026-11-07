import 'package:ndk_accounts/ndk_accounts.dart';
import 'package:ndk_nip46/ndk_nip46.dart';

/// Lives in the facade so that neither ndk_accounts nor ndk_nip46 depends on the other.
extension AccountsBunkerLogin on Accounts {
  Future<BunkerConnection?> loginWithBunkerUrl({
    required String bunkerUrl,
    required Bunkers bunkers,
    Function(String)? authCallback,
    Nip46ClientMetadata? clientMetadata,
  }) async {
    BunkerConnection? connection = await bunkers.connectWithBunkerUrl(
      bunkerUrl,
      authCallback: authCallback,
      clientMetadata: clientMetadata,
    );
    if (connection != null) {
      await loginWithBunkerConnection(
        connection: connection,
        bunkers: bunkers,
        authCallback: authCallback,
      );
    }
    return connection;
  }

  Future<BunkerConnection?> loginWithNostrConnect({
    required NostrConnect nostrConnect,
    required Bunkers bunkers,
    Function(String)? authCallback,
  }) async {
    BunkerConnection? connection = await bunkers.connectWithNostrConnect(
      nostrConnect,
      authCallback: authCallback,
    );
    if (connection != null) {
      await loginWithBunkerConnection(
        connection: connection,
        bunkers: bunkers,
        authCallback: authCallback,
      );
    }
    return connection;
  }

  Future<void> loginWithBunkerConnection({
    required BunkerConnection connection,
    required Bunkers bunkers,
    Function(String)? authCallback,
  }) async {
    final signer = bunkers.createSigner(connection, authCallback: authCallback);
    await signer.getPublicKeyAsync();
    loginExternalSigner(signer: signer);
  }
}
