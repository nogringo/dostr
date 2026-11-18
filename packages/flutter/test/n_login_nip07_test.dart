@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  late TestDostrFlutter dostr;

  setUp(() => dostr = TestDostrFlutter());
  tearDown(() {
    globalContext.delete('nostr'.toJS);
    return dostr.dispose();
  });

  Widget login() => localizedApp(
    SingleChildScrollView(
      child: NLogin(dostrFlutter: dostr.dostrFlutter, onLoggedIn: () {}),
    ),
  );

  testWidgets('offers to connect an extension that shows up late', (
    tester,
  ) async {
    await tester.pumpWidget(login());
    expect(find.text('Install'), findsOneWidget);

    globalContext['nostr'] = JSObject();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Install'), findsNothing);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('offers to install an extension that never shows up', (
    tester,
  ) async {
    await tester.pumpWidget(login());
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Install'), findsOneWidget);
  });
}
