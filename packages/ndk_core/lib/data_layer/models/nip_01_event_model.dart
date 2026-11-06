import 'dart:convert';

import 'package:ndk_nip01/ndk_nip01.dart';

/// Data model for NIP-01 Event
/// Extends [Nip01Event] entity with a base64 form
class Nip01EventModel extends Nip01Event {
  /// creates a new [Nip01EventModel] instance
  Nip01EventModel({
    required super.id,
    required super.pubKey,
    required super.createdAt,
    required super.kind,
    required super.tags,
    required super.content,
    required super.sig,
  });

  /// [Nip01Event.copyWith], as a [Nip01EventModel]
  @override
  Nip01EventModel copyWith({
    String? id,
    String? pubKey,
    int? createdAt,
    int? kind,
    List<List<String>>? tags,
    String? content,
    String? sig,
  }) => Nip01EventModel.fromEntity(
    super.copyWith(
      id: id,
      pubKey: pubKey,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      sig: sig,
    ),
  );

  /// [Nip01Event.withoutSig], as a [Nip01EventModel]
  @override
  Nip01EventModel withoutSig() =>
      Nip01EventModel.fromEntity(super.withoutSig());

  /**
   * encoding/decoding methods
   */

  /// creates a new [Nip01EventModel] instance from a [Nip01Event] entity
  factory Nip01EventModel.fromEntity(Nip01Event event) {
    return Nip01EventModel(
      id: event.id,
      pubKey: event.pubKey,
      createdAt: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      sig: event.sig,
    );
  }

  /// [Nip01Event.fromJson], as a [Nip01EventModel]
  Nip01EventModel.fromJson(super.data) : super.fromJson();

  /// Returns the Event object as a base64-encoded JSON string
  String toBase64() {
    return base64Encode(utf8.encode(toJsonString()));
  }
}
