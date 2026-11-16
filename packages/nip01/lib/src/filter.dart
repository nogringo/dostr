import 'dart:collection';

/// The NIP-01 filter of a REQ: an event matches it when it meets every
/// condition the filter sets. Its fields can change: [clone] gives an
/// independent copy.
///
/// https://github.com/nostr-protocol/nips/blob/master/01.md#communication-between-clients-and-relays
class Filter {
  /// The ids of the events to match.
  List<String>? ids;

  /// The pubkeys of the authors to match, in hex.
  List<String>? authors;

  /// The kinds to match.
  List<int>? kinds;

  /// A NIP-50 search query, for the relays that support it.
  String? search;

  /// The values of the `#e` filter: the ids of the events referred to.
  List<String>? get eTags => getTag("e");

  /// The values of the `#p` filter: the pubkeys referred to.
  List<String>? get pTags => getTag("p");

  /// The values of the `#a` filter: the `kind:pubkey:d` coordinates of the
  /// addressable or replaceable events referred to.
  List<String>? get aTags => getTag("a");

  /// The values of the `#d` filter: the identifiers of the addressable events
  /// to match.
  List<String>? get dTags => getTag("d");

  /// The oldest `created_at` to match, in Unix seconds, included.
  int? since;

  /// The newest `created_at` to match, in Unix seconds, included.
  int? until;

  /// The most events a relay returns for the initial query, the newest ones.
  int? limit;

  Map<String, List<String>>? _tags;

  /// The tag filters, by tag name without the NIP-01 '#', such as 'p' or 'e'.
  ///
  /// The map cannot be modified, so that every name stays bare: change it with
  /// [setTag] or this setter, which both take a name with or without its '#'.
  /// Only the JSON form, of [toJson] and [Filter.fromJson], has the '#'.
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

    if (tags != null) {
      body.addAll({
        for (final entry in tags!.entries) _wireTagKey(entry.key): entry.value,
      });
    }

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
