import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data_layer/models/nip_01_event_model.dart';
import 'nip_01_event.dart';

class Nip01Utils {
  /// checks if event id matches the event data (NIP-01)
  static bool isIdValid(Nip01Event event) {
    return event.id ==
        calculateEventIdSync(
          pubKey: event.pubKey,
          createdAt: event.createdAt,
          kind: event.kind,
          tags: event.tags,
          content: event.content,
        );
  }

  /// Calculate event id synchronously
  static String calculateEventIdSync({
    required String pubKey,
    required int createdAt,
    required int kind,
    required List<dynamic> tags,
    required String content,
  }) {
    return calculateId(
      Nip01Event(
        id: '',
        pubKey: pubKey,
        createdAt: createdAt,
        kind: kind,
        tags: List<List<String>>.from(
          tags.map((tag) => List<String>.from(tag)),
        ),
        content: content,
        sig: null,
        validSig: null,
      ),
    );
  }

  static String calculateId(Nip01Event event) {
    final model = Nip01EventModel.fromEntity(event);
    final jsonData = json.encode([
      0,
      model.pubKey,
      model.createdAt,
      model.kind,
      model.tags,
      model.content,
    ]);
    final bytes = utf8.encode(jsonData);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
