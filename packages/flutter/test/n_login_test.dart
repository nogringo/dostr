import 'dart:convert';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

void main() {
  late TestDostrFlutter dostr;
  late int loggedIn;

  setUp(() {
    dostr = TestDostrFlutter();
    loggedIn = 0;
  });

  tearDown(() => dostr.dispose());

  Widget login({
    bool enableAccountCreation = true,
    bool enableNip05Login = true,
    bool enableNpubLogin = true,
    bool enableNsecLogin = true,
    bool enableNip07Login = true,
    bool enableBunkerLogin = true,
    bool enableSignerAppLogin = true,
    bool enablePubkeyLogin = true,
    NostrConnect? nostrConnect,
    String? nsecLabelText,
  }) {
    return localizedApp(
      SingleChildScrollView(
        child: NLogin(
          dostrFlutter: dostr.dostrFlutter,
          onLoggedIn: () => loggedIn++,
          enableAccountCreation: enableAccountCreation,
          enableNip05Login: enableNip05Login,
          enableNpubLogin: enableNpubLogin,
          enableNsecLogin: enableNsecLogin,
          enableNip07Login: enableNip07Login,
          enableBunkerLogin: enableBunkerLogin,
          enableSignerAppLogin: enableSignerAppLogin,
          enablePubkeyLogin: enablePubkeyLogin,
          nostrConnect: nostrConnect,
          nsecLabelText: nsecLabelText,
        ),
      ),
    );
  }

  /// The text field showing [hint], found by position so it is still found
  /// once the hint is gone.
  Finder field(String hint) {
    final fields = find.byType(TextField);
    final index = fields.evaluate().toList().indexOf(
      find.widgetWithText(TextField, hint).evaluate().single,
    );
    return fields.at(index);
  }

  group('sections', () {
    testWidgets(
      'shows every login it is not told to hide',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        await tester.pumpWidget(login());

        expect(find.text('Nostr Address'), findsOneWidget);
        expect(find.text('Public Key'), findsOneWidget);
        expect(find.text('Private Key (insecure)'), findsOneWidget);
        expect(find.text('Bunker'), findsOneWidget);
        expect(find.text('Get Started'), findsOneWidget);
        expect(find.text('Install'), kIsWeb ? findsOneWidget : findsNothing);
        expect(find.text('Login with signer app'), findsNothing);
        expect(find.text('Show nostr connect qrcode'), findsNothing);
      },
    );

    testWidgets(
      'offers the signer app login on Android apps',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        await tester.pumpWidget(login());
        expect(
          find.text('Login with signer app'),
          kIsWeb ? findsNothing : findsOneWidget,
        );

        await tester.pumpWidget(login(enableSignerAppLogin: false));
        expect(find.text('Login with signer app'), findsNothing);
      },
    );

    testWidgets('hides the logins it is told to hide', (tester) async {
      await tester.pumpWidget(
        login(
          enablePubkeyLogin: false,
          enableNsecLogin: false,
          enableNip07Login: false,
          enableBunkerLogin: false,
          enableSignerAppLogin: false,
          enableAccountCreation: false,
        ),
      );

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('can hide the NIP-05 login alone', (tester) async {
      await tester.pumpWidget(login(enableNip05Login: false));

      expect(find.text('Nostr Address'), findsNothing);
      expect(find.text('Public Key'), findsOneWidget);
    });

    testWidgets('uses the private key label it is given', (tester) async {
      await tester.pumpWidget(login(nsecLabelText: 'Secret key'));

      expect(find.text('Secret key'), findsOneWidget);
      expect(find.text('Private Key (insecure)'), findsNothing);
    });

    testWidgets('offers the nostr connect QR code with an invitation', (
      tester,
    ) async {
      await tester.pumpWidget(
        login(
          enableBunkerLogin: false,
          nostrConnect: NostrConnect(
            relays: ['wss://relay.example.com'],
            privateKey: alicePrivateKey,
            publicKey: alicePubkey,
          ),
        ),
      );

      expect(find.text('Bunker'), findsOneWidget);
      expect(find.text('Show nostr connect qrcode'), findsOneWidget);
      expect(find.text('Login with bunker'), findsNothing);
    });
  });

  group('keys', () {
    testWidgets('logs in read-only with an npub', (tester) async {
      await tester.pumpWidget(login());

      await tester.enterText(field('npub1...'), Npub(bobPubkey).encode());
      await tester.pump();

      final account = dostr.accounts.getLoggedAccount()!;
      expect(account.pubkey, bobPubkey);
      expect(account.type, AccountType.publicKey);
      expect(loggedIn, 1);
      expect(dostr.savedState!['loggedAccount'], bobPubkey);
    });

    testWidgets('ignores a public key that is not an npub', (tester) async {
      await tester.pumpWidget(login());

      await tester.enterText(field('npub1...'), bobPubkey);
      await tester.pump();

      expect(dostr.accounts.isNotLoggedIn, isTrue);
      expect(loggedIn, 0);
    });

    testWidgets('waits for a complete npub', (tester) async {
      await tester.pumpWidget(login());

      await tester.enterText(
        field('npub1...'),
        Npub(bobPubkey).encode().substring(0, 20),
      );
      await tester.pump();

      expect(dostr.accounts.isNotLoggedIn, isTrue);
      expect(loggedIn, 0);
    });

    testWidgets('waits for a complete nsec', (tester) async {
      await tester.pumpWidget(login());

      await tester.enterText(
        field('nsec1...'),
        Nsec(alicePrivateKey).encode().substring(0, 20),
      );
      await tester.pump();

      expect(dostr.accounts.isNotLoggedIn, isTrue);
      expect(loggedIn, 0);
    });

    testWidgets('logs in with an nsec under the pubkey of the key', (
      tester,
    ) async {
      await tester.pumpWidget(login());

      await tester.enterText(field('nsec1...'), Nsec(alicePrivateKey).encode());
      await tester.pump();

      final account = dostr.accounts.getLoggedAccount()!;
      expect(account.pubkey, alicePubkey);
      expect(account.type, AccountType.privateKey);
      expect(account.signer.canSign(), isTrue);
      expect(loggedIn, 1);
    });

    testWidgets('switches to an account it already has', (tester) async {
      dostr.accounts.loginPrivateKey(
        pubkey: alicePubkey,
        privkey: alicePrivateKey,
      );
      dostr.accounts.loginPublicKey(pubkey: bobPubkey);
      await tester.pumpWidget(login());

      await tester.enterText(field('nsec1...'), Nsec(alicePrivateKey).encode());
      await tester.pump();

      expect(dostr.accounts.getPublicKey(), alicePubkey);
      expect(dostr.accounts.accounts, hasLength(2));
      expect(loggedIn, 1);

      await tester.enterText(field('npub1...'), Npub(bobPubkey).encode());
      await tester.pump();

      expect(dostr.accounts.getPublicKey(), bobPubkey);
      expect(loggedIn, 2);
    });
  });

  group('NIP-05', () {
    Future<void> submit(
      WidgetTester tester,
      String nip05,
      http.Response response,
    ) async {
      await tester.enterText(field('name@example.com'), nip05);
      await http.runWithClient(
        () => tester.tap(find.byIcon(Icons.arrow_forward)),
        () => MockClient((_) async => response),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('flags an address that is not a NIP-05 one', (tester) async {
      await tester.pumpWidget(login());

      await tester.enterText(field('name@example.com'), 'bob');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Invalid Address'), findsOneWidget);

      await tester.enterText(field('name@example.com'), 'bob@');
      await tester.pump();
      expect(find.text('Invalid Address'), findsNothing);
      expect(dostr.accounts.isNotLoggedIn, isTrue);
    });

    testWidgets('logs in read-only with the pubkey of the address', (
      tester,
    ) async {
      await tester.pumpWidget(login());

      await submit(
        tester,
        'bob@example.com',
        http.Response(
          jsonEncode({
            'names': {'bob': bobPubkey},
          }),
          200,
        ),
      );

      final account = dostr.accounts.getLoggedAccount()!;
      expect(account.pubkey, bobPubkey);
      expect(account.type, AccountType.publicKey);
      expect(loggedIn, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('says so when the address does not resolve', (tester) async {
      await tester.pumpWidget(login());

      await submit(tester, 'bob@example.com', http.Response('', 404));

      expect(find.text('Unable to connect'), findsOneWidget);
      expect(dostr.accounts.isNotLoggedIn, isTrue);
      expect(loggedIn, 0);
    });
  });

  group('bunker', () {
    final remote = 'b' * 64;

    testWidgets('enables the bunker login only for a bunker url', (
      tester,
    ) async {
      await tester.pumpWidget(login());
      final bunkerField = field('bunker://');

      bool enabled() => tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Login with bunker'),
          )
          .enabled;

      expect(enabled(), isFalse);

      final urls = {
        'bunker://$remote?relay=wss://relay.example.com&secret=s': true,
        ' bunker://$remote?relay=wss://relay.example.com ': true,
        'bunker://$remote': false,
        'bunker://${'b' * 63}?relay=wss://relay.example.com': false,
        'bunker://${'g' * 64}?relay=wss://relay.example.com': false,
        'nostrconnect://$remote?relay=wss://relay.example.com': false,
        'not a url': false,
      };
      for (final MapEntry(key: url, value: valid) in urls.entries) {
        await tester.enterText(bunkerField, url);
        await tester.pump();
        expect(enabled(), valid, reason: url);
      }
      expect(dostr.accounts.isNotLoggedIn, isTrue);
    });
  });
}
