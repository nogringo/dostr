import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  Future<Map<int, String>> describe(
    WidgetTester tester,
    List<int> kinds, {
    Locale? locale,
  }) async {
    late BuildContext context;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
        locale: locale,
      ),
    );
    return {
      for (final kind in kinds) kind: NostrKinds.getDescription(context, kind),
    };
  }

  testWidgets('names the well known kinds', (tester) async {
    expect(await describe(tester, [0, 1, 3, 1059, 9735, 10002, 30023]), {
      0: 'User Metadata',
      1: 'Short Text Note',
      3: 'Follows',
      1059: 'Gift Wrap',
      9735: 'Zap',
      10002: 'Relay List Metadata',
      30023: 'Long-form Content',
    });
  });

  testWidgets('names the kinds of the DVM and group ranges', (tester) async {
    expect(
      await describe(tester, [5000, 5999, 6000, 6999, 7000, 9000, 9030, 9041]),
      {
        5000: 'Job Request',
        5999: 'Job Request',
        6000: 'Job Result',
        6999: 'Job Result',
        7000: 'Job Feedback',
        9000: 'Group Control Event',
        9030: 'Group Control Event',
        9041: 'Zap Goal',
      },
    );
  });

  testWidgets('numbers a kind it does not know', (tester) async {
    expect(await describe(tester, [9031, 12345, -1]), {
      9031: 'Event Kind 9031',
      12345: 'Event Kind 12345',
      -1: 'Event Kind -1',
    });
  });

  testWidgets('speaks the language of the app', (tester) async {
    expect(await describe(tester, [1, 12345], locale: const Locale('fr')), {
      1: 'Note courte',
      12345: "Type d'événement 12345",
    });
  });
}
