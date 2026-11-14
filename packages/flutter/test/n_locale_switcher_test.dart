import 'package:dostr_flutter/dostr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('NLocaleSwitcher', () {
    late List<Locale> changes;

    setUp(() => changes = []);

    Widget switcher({
      Locale currentLocale = const Locale('en'),
      Map<String, String>? localeDisplayNames,
      String? tooltip,
      IconData? icon,
    }) {
      return localizedApp(
        NLocaleSwitcher(
          currentLocale: currentLocale,
          onLocaleChanged: changes.add,
          localeDisplayNames: localeDisplayNames,
          tooltip: tooltip,
          icon: icon,
        ),
      );
    }

    testWidgets('lists the languages and checks the current one', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(switcher(currentLocale: const Locale('fr')));
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      final titles = [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          (tile.title! as Text).data,
      ];
      expect(titles, hasLength(9));
      expect(titles.take(3), ['English', 'Español', 'Français']);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Français')),
        isA<ListTile>()
            .having((tile) => tile.selected, 'selected', isTrue)
            .having((tile) => tile.trailing, 'trailing', isNotNull),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('reports the language picked and closes', (tester) async {
      await tester.pumpWidget(switcher());
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();

      expect(changes, [const Locale('de')]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('reports nothing for the current language or a cancel', (
      tester,
    ) async {
      await tester.pumpWidget(switcher());

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('offers only the languages it is given', (tester) async {
      await tester.pumpWidget(
        switcher(localeDisplayNames: {'sk': 'Slovak', 'xx': 'Unknown'}),
      );
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(2));
      await tester.tap(find.text('Unknown'));
      await tester.pumpAndSettle();

      expect(changes, [const Locale('xx')]);
    });

    testWidgets('uses the icon and tooltip it is given', (tester) async {
      await tester.pumpWidget(
        switcher(icon: Icons.translate, tooltip: 'Language'),
      );

      expect(find.byIcon(Icons.language), findsNothing);
      expect(find.byTooltip('Language'), findsOneWidget);
    });
  });

  group('NLocaleSwitcherDropdown', () {
    testWidgets('reports the language picked', (tester) async {
      final changes = <Locale>[];
      await tester.pumpWidget(
        localizedApp(
          NLocaleSwitcherDropdown(
            currentLocale: const Locale('en'),
            onLocaleChanged: changes.add,
          ),
        ),
      );

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Italiano').last);
      await tester.pumpAndSettle();

      expect(changes, [const Locale('it')]);
    });
  });
}
