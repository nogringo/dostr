import 'package:flutter/widgets.dart';
import 'package:dostr_demo/l10n/generated/demo_localizations.dart';

extension DemoLocalizationsContext on BuildContext {
  DemoLocalizations get l10n => DemoLocalizations.of(this)!;
}
