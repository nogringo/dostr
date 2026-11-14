import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';
import 'package:dostr_flutter/main/config.dart';
import 'package:dostr_flutter/models/accounts.dart';
import 'package:dostr_flutter/models/metadata.dart';
import 'package:dostr_flutter/models/nip_05_result.dart';
import 'package:dostr_nip07/dostr_nip07.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:dostr_nip55/dostr_nip55.dart';

class DostrFlutter {
  final Accounts accounts;
  final RelayReqs relayReqs;
  final RelayPublishes relayPublishes;

  /// reads the profiles the widgets show
  final MetadataFetcher metadataFetcher;

  /// NIP-46 connections, signed with the factory of [accounts]
  final Bunkers bunkers;

  final String npubSeparator;
  final int npubPrefixLength;
  final int npubSuffixLength;
  final FlutterSecureStorage _storage;

  /// [metadataFetcher] defaults to one that asks the write relays of each
  /// pubkey, found by its own [Nip65Fetcher].
  DostrFlutter({
    required this.accounts,
    required this.relayReqs,
    required this.relayPublishes,
    MetadataFetcher? metadataFetcher,
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
       bunkers = Bunkers(
         relayReqs: relayReqs,
         relayPublishes: relayPublishes,
         eventSignerFactory: accounts.eventSignerFactory,
       ),
       _storage = storage ?? const FlutterSecureStorage();

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
    final signer = bunkers.createSigner(connection, authCallback: authCallback);
    await signer.getPublicKeyAsync();
    accounts.loginExternalSigner(signer: signer);
  }

  String formatNpub(String pubkey) {
    final npub = Npub(pubkey).encode();
    final prefix = npub.substring(0, npubPrefixLength);
    final suffix = npub.substring(npub.length - npubSuffixLength);
    return '$prefix$npubSeparator$suffix';
  }

  static Color getColorFromPubkey(String pubkey) {
    // Hash the pubkey using SHA-256 for better distribution
    final bytes = utf8.encode(pubkey);
    final digest = sha256.convert(bytes);

    // Use first 3 bytes of hash for RGB values
    final hashBytes = digest.bytes;
    final r = hashBytes[0];
    final g = hashBytes[1];
    final b = hashBytes[2];

    // Create color from RGB values
    final color = Color.fromARGB(255, r, g, b);

    // Convert to HSL to ensure good visibility
    final hslColor = HSLColor.fromColor(color);

    // Adjust saturation and lightness for better visibility
    // Keep hue from hash but ensure readable colors
    final adjustedHslColor = hslColor.withSaturation(0.6).withLightness(0.45);

    return adjustedHslColor.toColor();
  }

  static Future<Nip05Result> fetchNip05(String nip05) async {
    try {
      final parts = nip05.split('@');
      if (parts.length != 2) {
        return Nip05Result(
          error: 'Invalid NIP-05 format. Expected format: name@domain.com',
        );
      }

      final name = parts[0];
      final domain = parts[1];

      final uri = Uri.https(domain, '/.well-known/nostr.json', {"name": name});
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        return Nip05Result(
          error: 'Failed to fetch NIP-05 data: ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final names = json['names'] as Map<String, dynamic>?;
      final relays = json['relays'] as Map<String, dynamic>?;

      if (names == null || !names.containsKey(name)) {
        return Nip05Result(error: 'Name not found in NIP-05 data');
      }

      final pubkey = names[name] as String;
      final userRelays = relays?[pubkey] as List<dynamic>?;

      return Nip05Result(pubkey: pubkey, relays: userRelays?.cast<String>());
    } catch (e) {
      return Nip05Result(error: 'Error fetching NIP-05: $e');
    }
  }

  Future<void> saveAccountsState() async {
    final stored = NostrWidgetsAccounts(accounts: []);

    for (var account in accounts.accounts.values) {
      if (account.signer is Nip07EventSigner) {
        stored.accounts.add(
          NostrAccount(kind: AccountKinds.nip07, pubkey: account.pubkey),
        );
        continue;
      }

      if (account.signer is Nip55EventSigner) {
        // `signerSeed` holds the signer app package so
        // silent signing keeps working after restart.
        final signer = account.signer as Nip55EventSigner;
        stored.accounts.add(
          NostrAccount(
            kind: AccountKinds.nip55,
            pubkey: account.pubkey,
            signerSeed: signer.nip55Signer.package,
          ),
        );
        continue;
      }

      if (account.signer is Nip46EventSigner) {
        final signer = account.signer as Nip46EventSigner;
        stored.accounts.add(
          NostrAccount(
            kind: AccountKinds.bunker,
            pubkey: account.pubkey,
            signerSeed: jsonEncode(signer.connection),
          ),
        );
        continue;
      }

      if (account.type == AccountType.privateKey) {
        final privateKey = (account.signer as dynamic).privateKey as String?;
        if (privateKey == null) continue;
        stored.accounts.add(
          NostrAccount(
            kind: AccountKinds.privkey,
            pubkey: account.pubkey,
            signerSeed: privateKey,
          ),
        );
        continue;
      }

      if (account.type == AccountType.publicKey) {
        stored.accounts.add(
          NostrAccount(kind: AccountKinds.pubkey, pubkey: account.pubkey),
        );
        continue;
      }
    }

    stored.loggedAccount = accounts.getPublicKey();

    await _storage.write(key: accountsKey, value: jsonEncode(stored));
  }

  Future<void> restoreAccountsState() async {
    final storedAccounts = await _storage.read(key: accountsKey);

    if (storedAccounts == null) return;

    final stored = NostrWidgetsAccounts.fromJson(jsonDecode(storedAccounts));

    for (var account in stored.accounts) {
      if (account.kind == AccountKinds.nip07) {
        final signer = Nip07EventSigner(cachedPublicKey: account.pubkey);
        accounts.addAccount(
          pubkey: account.pubkey,
          type: AccountType.externalSigner,
          signer: signer,
        );
        continue;
      }

      if (account.kind == AccountKinds.nip55) {
        accounts.addAccount(
          pubkey: account.pubkey,
          type: AccountType.externalSigner,
          signer: Nip55EventSigner(
            publicKey: account.pubkey,
            // restore the signer app package captured at login (null for
            // legacy accounts -> Android routes through a compatible signer).
            nip55Signer: Nip55Signer(package: account.signerSeed),
          ),
        );
        continue;
      }

      if (account.kind == AccountKinds.bunker) {
        final signer = Nip46EventSigner(
          connection: BunkerConnection.fromJson(
            jsonDecode(account.signerSeed!),
          ),
          relayReqs: relayReqs,
          relayPublishes: relayPublishes,
          eventSignerFactory: accounts.eventSignerFactory,
          cachedPublicKey: account.pubkey,
        );
        accounts.addAccount(
          pubkey: account.pubkey,
          type: AccountType.externalSigner,
          signer: signer,
        );
        continue;
      }

      if (account.kind == AccountKinds.pubkey) {
        accounts.addAccount(
          pubkey: account.pubkey,
          type: AccountType.publicKey,
          signer: accounts.eventSignerFactory.create(
            privateKey: null,
            publicKey: account.pubkey,
          ),
        );
        continue;
      }

      if (account.kind == AccountKinds.privkey) {
        final pubkey = accounts.eventSignerFactory.derivePublicKey(
          account.signerSeed!,
        );
        accounts.addAccount(
          pubkey: pubkey,
          type: AccountType.privateKey,
          signer: accounts.eventSignerFactory.create(
            privateKey: account.signerSeed!,
            publicKey: pubkey,
          ),
        );
        continue;
      }
    }

    if (stored.loggedAccount == null) return;
    if (!accounts.hasAccount(stored.loggedAccount!)) return;
    try {
      accounts.switchAccount(pubkey: stored.loggedAccount!);
    } catch (_) {
      // stored logged account could not be restored (e.g. stale/corrupted
      // state); ignore rather than crash app startup.
    }
  }
}
