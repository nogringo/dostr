import 'dart:convert';

import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_fetchers/dostr_fetchers.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_flutter/l10n/app_localizations.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const alicePrivateKey =
    'e4bd52924bce6a9c58d2decc7fe91b376d6a6513fc615aabc9e071f2b436b127';
const alicePubkey =
    '953f12b4f6966a289fde9adfc511e00a66cfa4cb9d69551dee51f3f387e8e277';
const bobPubkey =
    'e247d5da03bab4206b4d6ef5d9db0e175e0dbf51585fa16345dd53abdd2d9259';
const carolPubkey =
    '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';

/// Answers from [events] instead of asking relays.
class FakeMetadataFetcher extends MetadataFetcher {
  FakeMetadataFetcher(RelayReqs reqs) : super(reqs: reqs);

  final events = <String, Nip01Event>{};
  final fetched = <String>[];
  Object? error;

  @override
  Future<Nip01Event?> fetch(String pubKey) async {
    fetched.add(pubKey);
    final error = this.error;
    if (error != null) throw error;
    return events[pubKey];
  }
}

/// A [DostrFlutter] that never reaches a relay, with its secure storage in
/// [storage].
class TestDostrFlutter {
  TestDostrFlutter({Map<String, String>? storage})
    : storage = storage ?? <String, String>{} {
    FlutterSecureStorage.setMockInitialValues(this.storage);
    final relayReqs = RelayReqs(
      relayManager: _relayManager,
      eventVerifier: Bip340EventVerifier(),
    );
    metadata = FakeMetadataFetcher(relayReqs);
    dostrFlutter = DostrFlutter(
      accounts: Accounts(const Bip340EventSignerFactory()),
      relayReqs: relayReqs,
      relayPublishes: RelayPublishes(relayManager: _relayManager),
      metadataFetcher: metadata,
      npubSeparator: '...',
    );
  }

  final Map<String, String> storage;
  final _relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(
      pingInterval: null,
    ),
  );
  late final FakeMetadataFetcher metadata;
  late final DostrFlutter dostrFlutter;

  Accounts get accounts => dostrFlutter.accounts;

  void addProfile(String pubkey, Map<String, Object?> content) {
    metadata.events[pubkey] = Nip01Event(
      pubKey: pubkey,
      kind: 0,
      tags: [],
      content: jsonEncode(content),
    );
  }

  /// The accounts [DostrFlutter.saveAccountsState] wrote, or null.
  Map<String, dynamic>? get savedState => switch (storage[accountsKey]) {
    final String json => jsonDecode(json) as Map<String, dynamic>,
    null => null,
  };

  Future<void> dispose() async {
    await accounts.dispose();
    await _relayManager.closeAllTransports();
  }
}

String shortNpub(String pubkey) {
  final npub = Npub(pubkey).encode();
  return '${npub.substring(0, 10)}...${npub.substring(npub.length - 4)}';
}

Widget localizedApp(Widget child, {Locale? locale, ThemeData? theme}) {
  return MaterialApp(
    locale: locale,
    theme: theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}
