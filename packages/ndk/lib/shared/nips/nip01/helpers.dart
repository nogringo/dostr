import 'dart:math';

import 'package:ndk_core/shared/nips/nip01/helpers.dart' as core;

class Helpers {
  static const _chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';

  // coverage:ignore-line
  static final Random _rnd = Random();

  /// return a random string of given length
  static String getRandomString(int length) {
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => _chars.codeUnitAt(_rnd.nextInt(_chars.length)),
      ),
    );
  }

  /// returns [bytes] secure random bytes as a hex string (2 chars per byte)
  static String getSecureRandomHex(int bytes) =>
      core.Helpers.getSecureRandomHex(bytes);

  /// reads tags from a nostr event and returns a list of pubkeys
  static List<String> getPubkeysFromTags(List tag) {
    var pubkeys = <String>[];
    for (var i = 0; i < tag.length; i++) {
      if (tag[i][0] == "p") {
        pubkeys.add(tag[i][1]);
      }
    }
    return pubkeys;
  }

  /// reads tags from a nostr event and returns a list of events
  static List<String> getEventsFromTags(List tag) {
    var events = <String>[];
    for (var i = 0; i < tag.length; i++) {
      if (tag[i][0] == "e") {
        events.add(tag[i][1]);
      }
    }
    return events;
  }

  /// return if given string is not blank
  static bool isNotBlank(String? str) {
    if (str != null && str.trim() != "") {
      return true;
    }
    return false;
  }

  /// return if given string is blank
  static bool isBlank(String? str) {
    return !isNotBlank(str);
  }

  /// now
  static int get now => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
