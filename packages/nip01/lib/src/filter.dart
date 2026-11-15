import 'dart:collection';

/// Represents a filter for querying Nostr events.
///
/// This class encapsulates various criteria that can be used to filter
/// Nostr events when querying relays or local caches.
/// https://github.com/nostr-protocol/nips/blob/master/01.md#communication-between-clients-and-relays
class Filter {
  /// List of event IDs to filter by.
  List<String>? ids;

  /// List of author public keys to filter by.
  List<String>? authors;

  /// List of event kinds to filter by.
  List<int>? kinds;

  /// Text to search for in event content.
  String? search;

  /// List of event tags to filter by.
  List<String>? get eTags => getTag("e");

  /// List of pubkey tags to filter by.
  List<String>? get pTags => getTag("p");

  /// List of replaceable event tags to filter by.
  List<String>? get aTags => getTag("a");

  /// List of addressable event identifiers to filter by.
  List<String>? get dTags => getTag("d");

  /// Unix timestamp to filter events created after this time.
  int? since;

  /// Unix timestamp to filter events created before this time.
  int? until;

  /// Maximum number of events to return.
  int? limit;

  Map<String, List<String>>? _tags;

  /// Read-only view of the tag filters, keyed by the bare tag name ('p', 'e',
  /// 'd', ...), value is a list of tag values.
  ///
  /// The NIP-01 '#' prefix is a wire-format detail only: [toJson] adds it when
  /// a filter is serialized for a relay, everything else, cache reads above
  /// all, sees bare keys.
  ///
  /// The returned map cannot be modified directly, so callers cannot bypass
  /// key normalization. Mutate through [setTag] or the [tags] setter instead;
  /// both accept '#'-prefixed keys such as '#p' and store them bare.
  Map<String, List<String>>? get tags =>
      _tags == null ? null : UnmodifiableMapView(_tags!);

  set tags(Map<String, List<String>>? value) {
    _tags = value == null
        ? null
        : {
            for (final entry in value.entries)
              _bareTagKey(entry.key): entry.value,
          };
  }

  /// [eTags], [pTags], [aTags] and [dTags] set the tag filters of those
  /// names, over the same names in [tags].
  Filter({
    this.ids,
    this.authors,
    this.kinds,
    this.search,
    Map<String, List<String>>? tags,
    List<String>? eTags,
    List<String>? pTags,
    List<String>? aTags,
    List<String>? dTags,
    this.since,
    this.until,
    this.limit,
  }) {
    this.tags = tags;
    if (eTags != null) setTag("e", eTags);
    if (pTags != null) setTag("p", pTags);
    if (aTags != null) setTag("a", aTags);
    if (dTags != null) setTag("d", dTags);
  }

  /// Reads a NIP-01 filter JSON object, as `jsonDecode` returns it.
  ///
  /// When present, `ids`, `authors` and the '#'-prefixed tag filters are lists
  /// of strings, `kinds` a list of ints, `search` a string, and `since`,
  /// `until` and `limit` ints. Anything else throws a [FormatException], where
  /// [tryFromJson] returns null. Other keys are ignored.
  Filter.fromJson(Map<dynamic, dynamic> data)
    : ids = _optionalList<String>(data, 'ids'),
      authors = _optionalList<String>(data, 'authors'),
      kinds = _optionalList<int>(data, 'kinds'),
      search = _optional<String>(data, 'search'),
      since = _optional<int>(data, 'since'),
      until = _optional<int>(data, 'until'),
      limit = _optional<int>(data, 'limit'),
      _tags = _tagsFromJson(data);

  /// The filter that [Filter.fromJson] reads from [data], or null where it
  /// throws or [data] is not a map.
  ///
  /// Use it for JSON that comes from outside, such as a client's REQ.
  static Filter? tryFromJson(Object? data) {
    if (data is! Map) return null;
    try {
      return Filter.fromJson(data);
    } on FormatException {
      return null;
    }
  }

  static Map<String, List<String>>? _tagsFromJson(Map<dynamic, dynamic> data) {
    final tags = {
      for (final key in data.keys)
        if (key is String && key.length > 1 && key.startsWith('#'))
          _bareTagKey(key): ?_optionalList<String>(data, key),
    };
    return tags.isEmpty ? null : tags;
  }

  static T? _optional<T>(Map<dynamic, dynamic> data, String key) =>
      switch (data[key]) {
        null => null,
        final T value => value,
        final value => throw FormatException('"$key" is not a $T', value),
      };

  static List<T>? _optionalList<T>(Map<dynamic, dynamic> data, String key) =>
      switch (data[key]) {
        null => null,
        final List values when values.every((value) => value is T) =>
          List<T>.from(values),
        final value => throw FormatException('"$key" is not a List<$T>', value),
      };

  /// Whether no event can match: NIP-01 says an empty list matches nothing.
  bool get matchesNothing =>
      (ids?.isEmpty ?? false) ||
      (authors?.isEmpty ?? false) ||
      (kinds?.isEmpty ?? false) ||
      (_tags?.values.any((values) => values.isEmpty) ?? false);

  /// The NIP-01 JSON object of this filter, ready for `jsonEncode`.
  Map<String, dynamic> toJson() {
    var body = {
      "ids": ids,
      "authors": authors,
      "kinds": kinds,
      "since": since,
      "until": until,
      "search": search,
      "limit": limit,
    };

    // Add arbitrary tags to the map, NIP-01 wants them '#'-prefixed
    if (tags != null) {
      body.addAll({
        for (final entry in tags!.entries) _wireTagKey(entry.key): entry.value,
      });
    }

    // remove null values
    body.removeWhere((key, value) => value == null);

    return body;
  }

  // coverage:ignore-start
  @override
  String toString() {
    return toJson().toString();
  }
  // coverage:ignore-end

  /// A deep copy: changing its lists leaves this filter as it is.
  Filter clone() {
    return Filter(
      ids: ids != null ? List<String>.from(ids!) : null,
      authors: authors != null ? List<String>.from(authors!) : null,
      kinds: kinds != null ? List<int>.from(kinds!) : null,
      search: search,
      since: since,
      until: until,
      limit: limit,
      tags: tags?.map((name, values) => MapEntry(name, List.of(values))),
    );
  }

  /// Sets the values of the tag filter [tagName], with or without its '#'.
  void setTag(String tagName, List<String> values) {
    (_tags ??= {})[_bareTagKey(tagName)] = values;
  }

  /// The values of the tag filter [tagName], with or without its '#'.
  List<String>? getTag(String tagName) => _tags?[_bareTagKey(tagName)];

  /// Tag key without the NIP-01 '#', the form [tags] stores.
  static String _bareTagKey(String tagName) =>
      tagName.startsWith('#') ? tagName.substring(1) : tagName;

  /// Tag key as NIP-01 serializes it, '#' prefixed.
  static String _wireTagKey(String tagName) =>
      tagName.startsWith('#') ? tagName : '#$tagName';
}
