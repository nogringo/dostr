import 'package:ndk_nip01/ndk_nip01.dart';

/// The deprecated members of [Nip01Event], kept out of `ndk_nip01`.
extension Nip01EventDeprecated on Nip01Event {
  @Deprecated('Use getFirstTag("e")')
  String? getEId() => getFirstTag('e');

  @Deprecated('Use dTag')
  String? getDtag() => dTag;

  @Deprecated('Use getTags("t")')
  List<String> get tTags => getTags('t');

  @Deprecated('A NIP-10 marker: read it from tags')
  List<String> get replyETags => [
    for (final tag in tags)
      if (tag.length >= 4 && tag[0] == 'e' && tag[3] == 'reply') tag[1],
  ];
}

class Nip01Utils {
  @Deprecated('Use event.hasValidId')
  static bool isIdValid(Nip01Event event) => event.hasValidId;

  @Deprecated('Use event.payloadId')
  static String calculateId(Nip01Event event) => event.payloadId;
}
