import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Metadata.fromEvent', () {
    Metadata parse(String content) => Metadata.fromEvent(
      Nip01Event(pubKey: alicePubkey, kind: 0, tags: [], content: content),
    );

    test('reads the profile fields and keeps the others', () {
      final metadata = parse(
        jsonEncode({
          'name': 'alice',
          'display_name': 'Alice',
          'picture': 'https://example.com/a.png',
          'banner': 'https://example.com/b.png',
          'website': 'https://example.com',
          'about': 'hi',
          'nip05': 'alice@example.com',
          'lud16': 'alice@wallet.example.com',
          'lud06': 'lnurl1',
          'bot': true,
        }),
      );

      expect(metadata.pubKey, alicePubkey);
      expect(metadata.name, 'alice');
      expect(metadata.displayName, 'Alice');
      expect(metadata.picture, 'https://example.com/a.png');
      expect(metadata.banner, 'https://example.com/b.png');
      expect(metadata.website, 'https://example.com');
      expect(metadata.about, 'hi');
      expect(metadata.nip05, 'alice@example.com');
      expect(metadata.lud16, 'alice@wallet.example.com');
      expect(metadata.lud06, 'lnurl1');
      expect(metadata.content['bot'], isTrue);
    });

    test('reads a field that is not a string as null', () {
      final metadata = parse(jsonEncode({'name': 42, 'nip05': null}));

      expect(metadata.name, isNull);
      expect(metadata.nip05, isNull);
      expect(metadata.content['name'], 42);
    });

    test('reads a content that is not a JSON object as no field', () {
      for (final content in ['', 'not json', '[1, 2]', 'null', '"alice"']) {
        final metadata = parse(content);

        expect(metadata.name, isNull, reason: content);
        expect(metadata.content, isEmpty, reason: content);
      }
    });
  });

  group('Metadata', () {
    test(
      'getName prefers the display name, then the name, then the pubkey',
      () {
        expect(
          const Metadata(
            pubKey: alicePubkey,
            name: 'alice',
            displayName: ' Alice ',
          ).getName(),
          'Alice',
        );
        expect(
          const Metadata(
            pubKey: alicePubkey,
            name: ' alice ',
            displayName: '  ',
          ).getName(),
          'alice',
        );
        expect(
          const Metadata(pubKey: alicePubkey, name: '').getName(),
          alicePubkey,
        );
      },
    );

    test('cleanNip05 lowercases, trims and drops the root underscore', () {
      expect(
        const Metadata(
          pubKey: alicePubkey,
          nip05: ' Alice@Example.COM ',
        ).cleanNip05,
        'alice@example.com',
      );
      expect(
        const Metadata(pubKey: alicePubkey, nip05: '_@example.com').cleanNip05,
        '@example.com',
      );
      expect(
        const Metadata(pubKey: alicePubkey, nip05: 'a_@example.com').cleanNip05,
        'a_@example.com',
      );
      expect(const Metadata(pubKey: alicePubkey).cleanNip05, isNull);
    });
  });

  group('DostrFlutter', () {
    late TestDostrFlutter dostr;

    setUp(() => dostr = TestDostrFlutter());
    tearDown(() => dostr.dispose());

    test('formatNpub keeps the start and the end of the npub', () {
      final npub = Nip19.encodePubKey(alicePubkey);

      expect(
        dostr.dostrFlutter.formatNpub(alicePubkey),
        '${npub.substring(0, 10)}...${npub.substring(npub.length - 4)}',
      );
    });

    test('loadMetadata reads the profile the fetcher finds', () async {
      dostr.addProfile(alicePubkey, {'name': 'alice'});

      expect(
        (await dostr.dostrFlutter.loadMetadata(alicePubkey))!.name,
        'alice',
      );
      expect(await dostr.dostrFlutter.loadMetadata(bobPubkey), isNull);
      expect(dostr.metadata.fetched, [alicePubkey, bobPubkey]);
    });

    test('getColorFromPubkey is stable and evenly lit', () {
      final alice = DostrFlutter.getColorFromPubkey(alicePubkey);
      final bob = DostrFlutter.getColorFromPubkey(bobPubkey);

      expect(DostrFlutter.getColorFromPubkey(alicePubkey), alice);
      expect(alice, isNot(bob));
      for (final color in [alice, bob]) {
        final hsl = HSLColor.fromColor(color);
        expect(hsl.saturation, closeTo(0.6, 0.01));
        expect(hsl.lightness, closeTo(0.45, 0.01));
      }
    });
  });

  group('DostrFlutter.fetchNip05', () {
    late List<Uri> requested;

    // Nip05Result is not exported, so the return type is inferred.
    fetch(
      String nip05,
      Future<http.Response> Function(http.Request request) answer,
    ) {
      return http.runWithClient(
        () => DostrFlutter.fetchNip05(nip05),
        () => MockClient((request) {
          requested.add(request.url);
          return answer(request);
        }),
      );
    }

    setUp(() => requested = []);

    test('finds the pubkey and relays of a name', () async {
      final result = await fetch(
        'bob@example.com',
        (_) async => http.Response(
          jsonEncode({
            'names': {'bob': bobPubkey},
            'relays': {
              bobPubkey: ['wss://relay.example.com'],
            },
          }),
          200,
        ),
      );

      expect(result.error, isNull);
      expect(result.pubkey, bobPubkey);
      expect(result.relays, ['wss://relay.example.com']);
      expect(
        requested.single,
        Uri.parse('https://example.com/.well-known/nostr.json?name=bob'),
      );
    });

    test('has no relays when the document lists none', () async {
      final result = await fetch(
        'bob@example.com',
        (_) async => http.Response(
          jsonEncode({
            'names': {'bob': bobPubkey},
          }),
          200,
        ),
      );

      expect(result.pubkey, bobPubkey);
      expect(result.relays, isNull);
    });

    test('fails on a name the document does not list', () async {
      final result = await fetch(
        'carol@example.com',
        (_) async => http.Response(
          jsonEncode({
            'names': {'bob': bobPubkey},
          }),
          200,
        ),
      );

      expect(result.pubkey, isNull);
      expect(result.error, isNotNull);
    });

    test('fails on an HTTP error', () async {
      final result = await fetch(
        'bob@example.com',
        (_) async => http.Response('', 404),
      );

      expect(result.pubkey, isNull);
      expect(result.error, contains('404'));
    });

    test('fails on a document that is not JSON', () async {
      final result = await fetch(
        'bob@example.com',
        (_) async => http.Response('<html></html>', 200),
      );

      expect(result.pubkey, isNull);
      expect(result.error, isNotNull);
    });

    test('fails without a request on an address without one @', () async {
      for (final nip05 in ['example.com', 'a@b@example.com']) {
        final result = await fetch(
          nip05,
          (_) async => http.Response('{}', 200),
        );

        expect(result.pubkey, isNull);
        expect(result.error, isNotNull);
      }
      expect(requested, isEmpty);
    });
  });

  group('accounts state', () {
    late TestDostrFlutter saved;

    setUp(() => saved = TestDostrFlutter());
    tearDown(() => saved.dispose());

    test('saves every account and the logged one', () async {
      final accounts = saved.accounts;
      accounts.loginPublicKey(pubkey: bobPubkey);
      accounts.addAccount(
        pubkey: carolPubkey,
        type: AccountType.externalSigner,
        signer: Nip55EventSigner(
          publicKey: carolPubkey,
          nip55Signer: const Nip55Signer(package: 'com.example.signer'),
        ),
      );
      accounts.loginPrivateKey(pubkey: alicePubkey, privkey: alicePrivateKey);

      await saved.dostrFlutter.saveAccountsState();

      expect(saved.savedState, {
        'loggedAccount': alicePubkey,
        'accounts': [
          {'kind': 'pubkey', 'pubkey': bobPubkey, 'signerSeed': null},
          {
            'kind': 'nip55',
            'pubkey': carolPubkey,
            'signerSeed': 'com.example.signer',
          },
          {
            'kind': 'privkey',
            'pubkey': alicePubkey,
            'signerSeed': alicePrivateKey,
          },
        ],
      });
    });

    test('restores what it saved', () async {
      saved.accounts.addAccount(
        pubkey: carolPubkey,
        type: AccountType.externalSigner,
        signer: Nip07EventSigner(cachedPublicKey: carolPubkey),
      );
      saved.accounts.addAccount(
        pubkey: bobPubkey,
        type: AccountType.externalSigner,
        signer: Nip55EventSigner(
          publicKey: bobPubkey,
          nip55Signer: const Nip55Signer(package: 'com.example.signer'),
        ),
      );
      saved.accounts.loginPrivateKey(
        pubkey: alicePubkey,
        privkey: alicePrivateKey,
      );
      saved.accounts.switchAccount(pubkey: bobPubkey);
      await saved.dostrFlutter.saveAccountsState();

      final restored = TestDostrFlutter(storage: saved.storage);
      addTearDown(restored.dispose);
      await restored.dostrFlutter.restoreAccountsState();
      final accounts = restored.accounts.accounts;

      expect(accounts.keys, [carolPubkey, bobPubkey, alicePubkey]);
      expect(accounts[carolPubkey]!.signer, isA<Nip07EventSigner>());
      expect(
        (accounts[bobPubkey]!.signer as Nip55EventSigner).nip55Signer.package,
        'com.example.signer',
      );
      expect(accounts[alicePubkey]!.type, AccountType.privateKey);
      expect(accounts[alicePubkey]!.signer.canSign(), isTrue);
      expect(restored.accounts.getPublicKey(), bobPubkey);
    });

    test('restores a legacy amber account as a NIP-55 one', () async {
      final restored = TestDostrFlutter(
        storage: {
          accountsKey: jsonEncode({
            'loggedAccount': bobPubkey,
            'accounts': [
              {
                'kind': 'amber',
                'pubkey': bobPubkey,
                'signerSeed': 'com.example.signer',
              },
            ],
          }),
        },
      );
      addTearDown(restored.dispose);

      await restored.dostrFlutter.restoreAccountsState();

      final account = restored.accounts.getLoggedAccount()!;
      expect(account.pubkey, bobPubkey);
      expect(account.type, AccountType.externalSigner);
      expect(
        (account.signer as Nip55EventSigner).nip55Signer.package,
        'com.example.signer',
      );
    });

    test('derives the pubkey of a private key account from the key', () async {
      final restored = TestDostrFlutter(
        storage: {
          accountsKey: jsonEncode({
            'loggedAccount': alicePubkey,
            'accounts': [
              {
                'kind': 'privkey',
                'pubkey': bobPubkey,
                'signerSeed': alicePrivateKey,
              },
            ],
          }),
        },
      );
      addTearDown(restored.dispose);

      await restored.dostrFlutter.restoreAccountsState();

      expect(restored.accounts.accounts.keys, [alicePubkey]);
      expect(restored.accounts.getPublicKey(), alicePubkey);
    });

    test('stays logged out when the logged account is not saved', () async {
      final restored = TestDostrFlutter(
        storage: {
          accountsKey: jsonEncode({
            'loggedAccount': alicePubkey,
            'accounts': [
              {'kind': 'pubkey', 'pubkey': bobPubkey, 'signerSeed': null},
            ],
          }),
        },
      );
      addTearDown(restored.dispose);

      await restored.dostrFlutter.restoreAccountsState();

      expect(restored.accounts.hasAccount(bobPubkey), isTrue);
      expect(restored.accounts.isNotLoggedIn, isTrue);
    });

    test('does nothing without a saved state', () async {
      await saved.dostrFlutter.restoreAccountsState();

      expect(saved.accounts.accounts, isEmpty);
    });
  });
}
