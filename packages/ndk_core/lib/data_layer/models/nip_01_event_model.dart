import 'dart:convert';

import '../../domain_layer/entities/nip_01_event.dart';
import '../../shared/helpers/list_casting.dart';

/// Data model for NIP-01 Event
/// Extends [Nip01Event] entity with serialization methods to/from JSON and other formats
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
    super.validSig,
  });

  /// creates a copy of this event with the given fields replaced by the new values \
  /// needed so other packages depending on the extened nip01_event.dart can use copyWith
  @override
  Nip01EventModel copyWith({
    String? id,
    String? pubKey,
    int? createdAt,
    int? kind,
    List<List<String>>? tags,
    String? content,
    String? sig,
    bool? validSig,
  }) {
    return Nip01EventModel(
      id: id ?? this.id,
      pubKey: pubKey ?? this.pubKey,
      createdAt: createdAt ?? this.createdAt,
      kind: kind ?? this.kind,
      tags: tags ?? this.tags,
      content: content ?? this.content,
      sig: sig ?? this.sig,
      validSig: validSig ?? this.validSig,
    );
  }

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
      validSig: event.validSig,
    );
  }

  /// creates a new [Nip01EventModel] instance from a JSON object
  factory Nip01EventModel.fromJson(Map<dynamic, dynamic> data) {
    final id = data['id'] as String? ?? '';
    final pubKey = data['pubkey'] as String? ?? '';
    final createdAt = data['created_at'] as int;
    final kind = data['kind'] as int;
    final tags = castToListOfListOfString(data['tags']);
    final content = data['content'] as String? ?? '';

    /// '' to support rumor events
    final sig = (data['sig'] as String?);

    return Nip01EventModel(
      id: id,
      pubKey: pubKey,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      sig: sig,
    );
  }

  /// Returns the Event object as a JSON object
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pubkey': pubKey,
      'created_at': createdAt,
      'kind': kind,
      'tags': tags,
      'content': content,
      'sig': sig,
    };
  }

  /// Returns the Event object as a JSON string
  String toJsonString() {
    final jsonMap = toJson();
    return json.encode(jsonMap);
  }

  /// Returns the Event object as a base64-encoded JSON string
  String toBase64() {
    return base64Encode(utf8.encode(json.encode(toJson())));
  }
}
