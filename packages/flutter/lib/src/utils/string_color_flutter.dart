import 'package:dostr_string_color/dostr_string_color.dart';
import 'package:material_ui/material_ui.dart';

/// Flutter's [Color] of a [StringColor].
extension StringColorFlutter on StringColor {
  /// This color as a Flutter [Color].
  Color toColor() => Color(argb);
}
