import 'package:dostr_string_color/dostr_string_color.dart';

void main() {
  print(StringColor.fromText('alice'));
  print(
    StringColor.fromHex(
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
    ).forTextOnDark(),
  );
}
