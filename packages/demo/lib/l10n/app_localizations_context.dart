import 'package:flutter/widgets.dart';
import 'generated/demo_localizations.dart';

extension DemoLocalizationsContext on BuildContext {
  DemoLocalizations get l10n => DemoLocalizations.of(this)!;
}
