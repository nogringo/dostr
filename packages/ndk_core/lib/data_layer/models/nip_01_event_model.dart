import 'dart:convert';

import 'package:ndk_nip01/ndk_nip01.dart';

@Deprecated('Use Nip01Event')
typedef Nip01EventModel = Nip01Event;

extension Nip01EventBase64 on Nip01Event {
  /// The event JSON in base64, as a `Nostr` Authorization header carries it
  /// (NIP-98, Blossom).
  String toBase64() => base64Encode(utf8.encode(toJsonString()));
}
