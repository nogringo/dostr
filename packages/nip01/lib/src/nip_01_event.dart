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
  /// The object needs a string `pubkey` and `content`, an int `created_at`
  /// and `kind`, and `tags` that are lists of strings. An `id` and a `sig`
  /// are strings when present: a missing id is computed from the payload and
  /// a missing sig reads as null. Anything else throws a [FormatException],
  /// where [tryFromJson] returns null.
  ///
  /// Only the shape is checked, so that it reads back whatever [toJson]
  /// wrote. The id is not checked against the payload, nor the sig against
  /// the pubkey: use [hasValidId] or an [EventVerifier] for that.
  Nip01Event.fromJson(Map<dynamic, dynamic> data)
    : this._(
        id: _optional<String>(data, 'id'),
        pubKey: _required<String>(data, 'pubkey'),
        createdAt: _required<int>(data, 'created_at'),
        kind: _required<int>(data, 'kind'),
        tags: _tagsFromJson(data),
        content: _required<String>(data, 'content'),
        sig: _optional<String>(data, 'sig'),
      );

  /// The event that [fromJson] reads from [data], or null where it throws or
  /// [data] is not a map.
  ///
  /// Use it for JSON that comes from outside, such as a relay, a remote
  /// signer or a seal.
  static Nip01Event? tryFromJson(Object? data) {
    if (data is! Map) return null;
    try {
      return Nip01Event.fromJson(data);
    } on FormatException {
      return null;
    }
  }

  static List<List<String>> _tagsFromJson(Map<dynamic, dynamic> data) =>
      switch (_required<List>(data, 'tags')) {
        final tags when _areTags(tags) => List.unmodifiable([
          for (final List tag in tags) List<String>.unmodifiable(tag),
        ]),
        final tags => throw FormatException(
          '"tags" is not a list of string lists',
          tags,
        ),
      };

  static bool _areTags(List tags) =>
      tags.every((tag) => tag is List && tag.every((value) => value is String));

  static T? _optional<T>(Map<dynamic, dynamic> data, String key) =>
      switch (data[key]) {
        null => null,
        final T value => value,
        final value => throw FormatException('"$key" is not a $T', value),
      };

  static T _required<T>(Map<dynamic, dynamic> data, String key) =>
      _optional<T>(data, key) ?? (throw FormatException('"$key" is missing'));

  static List<List<String>> _frozen(List<List<String>> tags) =>
      List.unmodifiable([
        for (final tag in tags) List<String>.unmodifiable(tag),
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

  /// A copy with the same [id] and no [sig], such as a NIP-59 rumor.
  Nip01Event withoutSig() => Nip01Event._(
    id: id,
    pubKey: pubKey,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: content,
    sig: null,
  );

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

  /// Events with the same [id] are equal, whatever their payload or [sig]: an
  /// event with a forged id equals the real one, so check it before using it
  /// to deduplicate events that are not verified yet.
  @override
  bool operator ==(other) => other is Nip01Event && id == other.id;
  @override
  int get hashCode => id.hashCode;

  /// seconds since epoch
  static int secondsSinceEpoch() {
    final secondsSinceEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return secondsSinceEpoch;
  }

  /// The id of this event's payload (NIP-01), whatever [id] it holds.
  String get payloadId => computeEventId(
    pubKey: pubKey,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: content,
  );

  /// Whether [id] is the hash of this event's payload (NIP-01).
  bool get hasValidId => id == payloadId;

  @Deprecated('Use getFirstTag("e")')
  String? getEId() => getFirstTag('e');

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
  @Deprecated('A NIP-10 marker: read it from tags')
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

  /// The value of the first `d` tag, the identifier of an addressable event.
  String? get dTag => getFirstTag('d');

  @Deprecated('Use dTag')
  String? getDtag() => dTag;

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
    return 'Nip01Event{id: $id, pubKey: $pubKey, createdAt: $createdAt, kind: $kind, tags: $tags, content: $content}';
  }
}
