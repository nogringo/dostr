import 'dart:convert';

import 'event_id.dart';

/// basic nostr nip01 event data structure
class Nip01Event {
  static const int kTextNoteKind = 1;

  /// The event ID is a 32-byte SHA256 hash of the serialised event data.
  final String id;

  /// The event author's public key.
  final String pubKey;

  /// Event creation timestamp in Unix time.
  final int createdAt;

  /// Event kind identifier (e.g. text_note, set_metadata, etc).
  final int kind;

  /// A JSON array of event tags, copied at construction and unmodifiable.
  final List<List<String>> tags;

  /// Event content.
  final String content;

  /// 64-byte Schnorr signature of [Nip01Event.id].
  final String? sig;

  /// Creates a new Nostr event.
  ///
  /// [pubKey] is the author's public key.
  /// [kind] is the event kind.
  /// [tags] are the event tags; the event keeps its own copy of them.
  /// [content] is an arbitrary string.
  ///
  /// Nostr event `id` and `created_at` fields are calculated automatically.
  ///
  Nip01Event({
    String? id,
    required String pubKey,
    required int kind,
    required List<List<String>> tags,
    required String content,
    String? sig,
    int? createdAt,
  }) : this._(
         id: id,
         pubKey: pubKey,
         createdAt: createdAt ?? secondsSinceEpoch(),
         kind: kind,
         tags: _frozen(tags),
         content: content,
         sig: sig,
       );

  Nip01Event._({
    required String? id,
    required this.pubKey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  }) : id =
           id ??
           computeEventId(
             pubKey: pubKey,
             createdAt: createdAt,
             kind: kind,
             tags: tags,
             content: content,
           );

  /// Reads a NIP-01 event JSON object, as `jsonDecode` returns it.
  ///
  /// A missing `id` is computed from the payload, a missing `pubkey` or
  /// `content` reads as `''` and a missing `sig` as null. Tag values that are
  /// not strings are turned into strings.
  Nip01Event.fromJson(Map<dynamic, dynamic> data)
    : this._(
        id: data['id'] as String?,
        pubKey: data['pubkey'] as String? ?? '',
        createdAt: data['created_at'] as int,
        kind: data['kind'] as int,
        tags: _tagsFromJson(data['tags']),
        content: data['content'] as String? ?? '',
        sig: data['sig'] as String?,
      );

  static List<List<String>> _frozen(List<List<String>> tags) =>
      List.unmodifiable([
        for (final tag in tags) List<String>.unmodifiable(tag),
      ]);

  static List<List<String>> _tagsFromJson(Object? tags) => _frozen([
    for (final tag in (tags as List? ?? const []).whereType<List>())
      [for (final value in tag) value?.toString() ?? ''],
  ]);

  /// A copy with the given fields replaced.
  ///
  /// Changing [pubKey], [createdAt], [kind], [tags] or [content] gives the copy
  /// the id of its new payload, and drops [sig] once that id differs. Pass [id]
  /// to keep another one, such as a remote signer's.
  Nip01Event copyWith({
    String? id,
    String? pubKey,
    int? createdAt,
    int? kind,
    List<List<String>>? tags,
    String? content,
    String? sig,
  }) {
    final payloadChanged =
        pubKey != null ||
        createdAt != null ||
        kind != null ||
        tags != null ||
        content != null;
    final nextPubKey = pubKey ?? this.pubKey;
    final nextCreatedAt = createdAt ?? this.createdAt;
    final nextKind = kind ?? this.kind;
    final nextTags = tags == null ? this.tags : _frozen(tags);
    final nextContent = content ?? this.content;
    final nextId =
        id ??
        (payloadChanged
            ? computeEventId(
                pubKey: nextPubKey,
                createdAt: nextCreatedAt,
                kind: nextKind,
                tags: nextTags,
                content: nextContent,
              )
            : this.id);
    return Nip01Event._(
      id: nextId,
      pubKey: nextPubKey,
      createdAt: nextCreatedAt,
      kind: nextKind,
      tags: nextTags,
      content: nextContent,
      sig: sig ?? (nextId == this.id ? this.sig : null),
    );
  }

  /// The NIP-01 JSON object of this event, ready for `jsonEncode`.
  ///
  /// An unsigned event, such as a NIP-59 rumor, has no `sig` key.
  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubKey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    if (sig != null) 'sig': sig,
  };

  String toJsonString() => json.encode(toJson());

  // Individual events with the same "id" are equivalent
  @override
  bool operator ==(other) => other is Nip01Event && id == other.id;
  @override
  int get hashCode => id.hashCode;

  /// seconds since epoch
  static int secondsSinceEpoch() {
    final secondsSinceEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return secondsSinceEpoch;
  }

  /// return first `e` tag found
  String? getEId() {
    return getFirstTag("e");
  }

  /// values of all tags named [tag], e.g. 'p', exactly as the event holds them
  List<String> getTags(String tag) {
    List<String> foundTags = [];
    for (final e in tags) {
      if (e.length > 1) {
        final key = e[0];
        final value = e[1];

        if (key == tag) {
          foundTags.add(value);
        }
      }
    }
    return foundTags;
  }

  /// return all `t` tags in event
  List<String> get tTags {
    return getTags("t");
  }

  /// return all `p` tags in event
  List<String> get pTags {
    return getTags("p");
  }

  /// return all e tags in event that have a `reply` marker
  List<String> get replyETags {
    List<String> replyIds = [];
    for (final tag in tags) {
      if (tag.length >= 4) {
        final key = tag[0];
        final value = tag[1];
        final marker = tag[3];

        if (key == "e" && marker == "reply") {
          replyIds.add(value);
        }
      }
    }
    return replyIds;
  }

  /// return first found `d` tag
  String? getDtag() {
    return getFirstTag("d");
  }

  /// Get first tag matching given name
  String? getFirstTag(String name) {
    for (final tag in tags) {
      if (tag.length > 1) {
        final key = tag[0];
        final value = tag[1];

        if (key == name) {
          return value;
        }
      }
    }
    return null;
  }

  @override
  String toString() {
    return 'Nip01Event{pubKey: $pubKey, createdAt: $createdAt, kind: $kind, tags: $tags, content: $content}';
  }
}
