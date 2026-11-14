import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late TestDostrFlutter dostr;
  late List<String> events;

  setUp(() {
    dostr = TestDostrFlutter();
    events = [];
    dostr.addProfile(alicePubkey, {'name': 'alice'});
    dostr.addProfile(bobPubkey, {'name': 'bob'});
    dostr.addProfile(carolPubkey, {'name': 'carol'});
    dostr.accounts.loginPublicKey(pubkey: bobPubkey);
    dostr.accounts.addAccount(
      pubkey: carolPubkey,
      type: AccountType.externalSigner,
      signer: Nip07EventSigner(cachedPublicKey: carolPubkey),
    );
    dostr.accounts.loginPrivateKey(
      pubkey: alicePubkey,
      privkey: alicePrivateKey,
    );
  });

  tearDown(() => dostr.dispose());

  Widget switchAccount({VoidCallback? onAddAccount}) => localizedApp(
    NSwitchAccount(
      dostrFlutter: dostr.dostrFlutter,
      beforeAccountSwitch: (pubkey) => events.add('before switch $pubkey'),
      onAccountSwitch: (pubkey) => events.add('switch $pubkey'),
      beforeAccountRemove: (pubkey) => events.add('before remove $pubkey'),
      onAccountRemove: (pubkey) => events.add('remove $pubkey'),
      onAddAccount: onAddAccount,
    ),
  );

  Finder tileOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ListTile));

  testWidgets('lists every account with its kind', (tester) async {
    await tester.pumpWidget(switchAccount());
    await tester.pump();

    expect(find.byType(ListTile), findsNWidgets(3));
    expect(
      find.descendant(of: tileOf('bob'), matching: find.text('Read-only')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tileOf('alice'), matching: find.text('Nsec')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tileOf('carol'), matching: find.text('Extension')),
      findsOneWidget,
    );
  });

  testWidgets('marks the logged account and offers no action on it', (
    tester,
  ) async {
    await tester.pumpWidget(switchAccount());
    await tester.pump();

    double markOpacity(String name) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.descendant(
                  of: tileOf(name),
                  matching: find.byIcon(Icons.radio_button_checked),
                ),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    expect(markOpacity('alice'), 1);
    expect(markOpacity('bob'), 0);
    expect(tester.widget<ListTile>(tileOf('alice')).onTap, isNull);
    expect(
      find.descendant(of: tileOf('alice'), matching: find.text('Logout')),
      findsNothing,
    );
    expect(find.text('Logout'), findsNWidgets(2));
  });

  testWidgets('switches to an account on tap', (tester) async {
    await tester.pumpWidget(switchAccount());
    await tester.pump();

    await tester.tap(find.text('bob'));
    await tester.pump();

    expect(dostr.accounts.getPublicKey(), bobPubkey);
    expect(events, ['before switch $bobPubkey', 'switch $bobPubkey']);
    expect(dostr.savedState!['loggedAccount'], bobPubkey);
    expect(tester.widget<ListTile>(tileOf('bob')).onTap, isNull);
    expect(tester.widget<ListTile>(tileOf('alice')).onTap, isNotNull);
  });

  testWidgets('removes an account that is not logged', (tester) async {
    await tester.pumpWidget(switchAccount());
    await tester.pump();

    await tester.tap(
      find.descendant(of: tileOf('carol'), matching: find.text('Logout')),
    );
    await tester.pump();

    expect(dostr.accounts.hasAccount(carolPubkey), isFalse);
    expect(dostr.accounts.getPublicKey(), alicePubkey);
    expect(events, ['before remove $carolPubkey', 'remove $carolPubkey']);
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(
      [
        for (final account in dostr.savedState!['accounts'] as List)
          (account as Map)['pubkey'],
      ],
      [bobPubkey, alicePubkey],
    );
  });

  testWidgets('offers to add an account only when asked to', (tester) async {
    await tester.pumpWidget(switchAccount());
    expect(find.text('Add account'), findsNothing);

    var added = false;
    await tester.pumpWidget(switchAccount(onAddAccount: () => added = true));
    await tester.tap(find.text('Add account'));

    expect(added, isTrue);
  });
}
