import 'dart:async';

import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';
import 'package:dostr_nip05/dostr_nip05.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'accounts_storage.dart';
import 'models/metadata.dart';

class DostrFlutter {
  final Accounts accounts;
  final RelayReqs relayReqs;
  final RelayPublishes relayPublishes;

  /// reads the profiles the widgets show
  final MetadataFetcher metadataFetcher;

  /// finds the write relays [metadataFetcher] asks: give it to the other
  /// fetchers of the app so they share its lookups
  Nip65Fetcher? get nip65Fetcher => metadataFetcher.nip65Fetcher;

  /// resolves the NIP-05 addresses `NLogin` logs in with
  final Nip05Resolver nip05Resolver;

  /// NIP-46 connections, signed with the factory of [accounts]
  final Bunkers bunkers;

  final String npubSeparator;
  final int npubPrefixLength;
  final int npubSuffixLength;
  late final AccountsStorage _accountsStorage;
  final _bunkerAuthUrls = StreamController<String>.broadcast();

  /// [metadataFetcher] defaults to one that asks the write relays of each
  /// pubkey, found by [nip65Fetcher], a new [Nip65Fetcher] unless given. A
  /// [metadataFetcher] given with a [nip65Fetcher] must find its write relays
  /// with it. [nip05Resolver] defaults to one that keeps what it resolved in
  /// memory.
  DostrFlutter({
    required this.accounts,
    required this.relayReqs,
    required this.relayPublishes,
    Nip65Fetcher? nip65Fetcher,
    MetadataFetcher? metadataFetcher,
    Nip05Resolver? nip05Resolver,
    this.npubSeparator = '…',
    this.npubPrefixLength = 10,
    this.npubSuffixLength = 4,
    FlutterSecureStorage? storage,
  }) : metadataFetcher = _metadataFetcher(
         relayReqs,
         nip65Fetcher,
         metadataFetcher,
       ),
       nip05Resolver = nip05Resolver ?? Nip05Resolver(),
       bunkers = Bunkers(
         relayReqs: relayReqs,
         relayPublishes: relayPublishes,
         signerFactory: accounts.signerFactory,
       ) {
    _accountsStorage = AccountsStorage(
      storage: storage ?? const FlutterSecureStorage(),
      accounts: accounts,
      relayReqs: relayReqs,
      relayPublishes: relayPublishes,
      bunkerAuthCallback: addBunkerAuthUrl,
    );
  }

  static MetadataFetcher _metadataFetcher(
    RelayReqs relayReqs,
    Nip65Fetcher? nip65Fetcher,
    MetadataFetcher? metadataFetcher,
  ) {
    if (metadataFetcher == null) {
      return MetadataFetcher(
        reqs: relayReqs,
        nip65Fetcher: nip65Fetcher ?? Nip65Fetcher(reqs: relayReqs),
      );
    }
    if (nip65Fetcher != null &&
        !identical(metadataFetcher.nip65Fetcher, nip65Fetcher)) {
      throw ArgumentError.value(
        metadataFetcher,
        'metadataFetcher',
        'does not find write relays with nip65Fetcher',
      );
    }
    return metadataFetcher;
  }

  /// The auth challenges of the bunker accounts: https urls where the user
  /// approves a request. `NPendingRequests` shows the latest one while
  /// requests wait.
  Stream<String> get bunkerAuthUrls => _bunkerAuthUrls.stream;

  /// Adds [url] to [bunkerAuthUrls]. It is the `authCallback` of the bunker
  /// accounts this logs in or restores: give it to a `Nip46Signer` you log in
  /// yourself.
  void addBunkerAuthUrl(String url) => _bunkerAuthUrls.add(url);

  /// the newest profile of [pubkey], or null if no relay has one
  Future<Metadata?> loadMetadata(String pubkey) async {
    final event = await metadataFetcher.fetch(pubkey);
    return event == null ? null : Metadata.fromEvent(event);
  }

  /// Logs in through a `bunker://` url. [authCallback] gets the auth
  /// challenges of the login, and [bunkerAuthUrls] the later ones.
  Future<BunkerConnection> loginWithBunkerUrl(
    String bunkerUrl, {
    void Function(String url)? authCallback,
    Nip46ClientMetadata? clientMetadata,
  }) async {
    final connection = await bunkers.connectWithBunkerUrl(
      bunkerUrl,
      authCallback: authCallback,
      clientMetadata: clientMetadata,
    );
    await _loginWithBunker(connection, authCallback: authCallback);
    return connection;
  }

  /// Logs in once a signer answers [nostrConnect]. [authCallback] gets the
  /// auth challenges of the login, and [bunkerAuthUrls] the later ones.
  Future<BunkerConnection> loginWithNostrConnect(
    NostrConnect nostrConnect, {
    void Function(String url)? authCallback,
  }) async {
    final connection = await bunkers.connectWithNostrConnect(nostrConnect);
    await _loginWithBunker(connection, authCallback: authCallback);
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
    // the login screen behind authCallback may be gone by the next challenge
    signer.authCallback = addBunkerAuthUrl;
    accounts.loginExternalSigner(signer: signer);
  }

  /// Removes the logged account, as [Accounts.logout] does, and ends its
  /// session on its bunker, see [removeAccount].
  Future<void> logout() async {
    final pubkey = accounts.loggedPubkey;
    if (pubkey != null) await removeAccount(pubkey: pubkey);
  }

  /// Removes the account of [pubkey], as [Accounts.removeAccount] does. A
  /// bunker account also ends its session on its bunker.
  Future<void> removeAccount({required String pubkey}) {
    final signer = accounts.getAccount(pubkey);
    if (signer is Nip46Signer) unawaited(signer.logout());
    return accounts.removeAccount(pubkey: pubkey);
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
