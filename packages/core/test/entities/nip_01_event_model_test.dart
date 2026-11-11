import 'dart:convert';

import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  final event = signedEvent(
    content: 'hello',
    createdAt: 42,
    tags: [
      ['p', bob],
    ],
  );

  test('toBase64 encodes the event JSON', () {
    final decoded = jsonDecode(utf8.decode(base64Decode(event.toBase64())));

    expect(decoded, event.toJson());
  });

  test('Nip01EventModel is still a Nip01Event', () {
    final Nip01EventModel model = Nip01EventModel.fromJson(event.toJson());

    expect(model.toJson(), event.toJson());
  });
}
