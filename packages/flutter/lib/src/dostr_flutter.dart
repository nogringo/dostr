import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';
import 'package:dostr_nip05/dostr_nip05.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'accounts_storage.dart';
import 'models/metadata.dart';

class DostrFlutter {
  final Accounts accounts;
  final RelayReqs relayReqs;
  final RelayPublishes relayPublishes;

  /// reads the profiles the widgets show
  final MetadataFetcher metadataFetcher;

  /// resolves the NIP-05 addresses `NLogin` logs in with
  final Nip05Resolver nip05Resolver;

  /// NIP-46 connections, signed with the factory of [accounts]
  final Bunkers bunkers;

  final String npubSeparator;
  final int npubPrefixLength;
  final int npubSuffixLength;
  final AccountsStorage _accountsStorage;

  /// [metadataFetcher] defaults to one that asks the write relays of each
  /// pubkey, found by its own [Nip65Fetcher], and [nip05Resolver] to one that
  /// keeps what it resolved in memory.
  DostrFlutter({
    required this.accounts,
    required this.relayReqs,
    required this.relayPublishes,
    MetadataFetcher? metadataFetcher,
    Nip05Resolver? nip05Resolver,
    this.npubSeparator = '…',
    this.npubPrefixLength = 10,
    this.npubSuffixLength = 4,
    FlutterSecureStorage? storage,
  }) : metadataFetcher =
           metadataFetcher ??
           MetadataFetcher(
             reqs: relayReqs,
             nip65Fetcher: Nip65Fetcher(reqs: relayReqs),
           ),
       nip05Resolver =
           nip05Resolver ??
           Nip05Resolver(
             nip05Repository: HttpNip05Repository(client: http.Client()),
           ),
       bunkers = Bunkers(
         relayReqs: relayReqs,
         relayPublishes: relayPublishes,
         signerFactory: accounts.signerFactory,
       ),
       _accountsStorage = AccountsStorage(
         storage: storage ?? const FlutterSecureStorage(),
         accounts: accounts,
         relayReqs: relayReqs,
         relayPublishes: relayPublishes,
       );

  /// the newest profile of [pubkey], or null if no relay has one
  Future<Metadata?> loadMetadata(String pubkey) async {
    final event = await metadataFetcher.fetch(pubkey);
    return event == null ? null : Metadata.fromEvent(event);
  }

  /// logs in through a `bunker://` url
  Future<BunkerConnection?> loginWithBunkerUrl(
    String bunkerUrl, {
    void Function(String url)? authCallback,
    Nip46ClientMetadata? clientMetadata,
  }) async {
    final connection = await bunkers.connectWithBunkerUrl(
      bunkerUrl,
      authCallback: authCallback,
      clientMetadata: clientMetadata,
    );
    if (connection != null) {
      await _loginWithBunker(connection, authCallback: authCallback);
    }
    return connection;
  }

  /// logs in once a signer answers [nostrConnect]
  Future<BunkerConnection?> loginWithNostrConnect(
    NostrConnect nostrConnect, {
    void Function(String url)? authCallback,
  }) async {
    final connection = await bunkers.connectWithNostrConnect(
      nostrConnect,
      authCallback: authCallback,
    );
    if (connection != null) {
      await _loginWithBunker(connection, authCallback: authCallback);
    }
    return connection;
  }

  Future<void> _loginWithBunker(
    BunkerConnection connection, {
    void Function(String url)? authCallback,
  }) async {
    final signer = await bunkers.createSigner(
      connection,
      authCallback: authCallback,
    );
    accounts.loginExternalSigner(signer: signer);
  }

  String formatNpub(String pubkey) {
    final npub = Npub(pubkey).encode();
    final prefix = npub.substring(0, npubPrefixLength);
    final suffix = npub.substring(npub.length - npubSuffixLength);
    return '$prefix$npubSeparator$suffix';
  }

  Future<void> saveAccountsState() => _accountsStorage.save();

  Future<void> restoreAccountsState() => _accountsStorage.restore();
}
