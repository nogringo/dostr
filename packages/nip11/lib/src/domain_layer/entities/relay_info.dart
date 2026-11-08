import 'dart:collection';

import 'package:collection/collection.dart';

/// NIP-11 relay information document, as declared by the relay and not
/// verified. Every field the relay omits is null
class RelayInfo with _Document {
  final String? name;

  final String? description;

  /// Relay banner image
  final String? banner;

  /// Relay icon
  final String? icon;

  /// Nostr public key of the relay admin
  final String? pubKey;

  /// Nostr public key of the relay itself
  final String? self;

  /// Alternative contact of the relay admin
  final String? contact;

  /// Supported NIPs, normalized by [normalizeNip], numbered ones first and in
  /// order, without duplicates
  final List<String> nips;

  /// Software description
  final String? software;

  /// Relay software version identifier
  final String? version;

  /// Dropped from NIP-11, still read when a relay serves it
  final String? privacyPolicy;

  final String? termsOfService;

  /// Where to pay the relay [fees]
  final String? paymentsUrl;

  final RelayLimitation? limitation;
  final RelayFees? fees;

  /// The fields this class does not read, as the relay served them, such as
  /// `retention` or `relay_countries`. Read-only, nested values included
  final Map<String, dynamic> extra;

  RelayInfo({
    this.name,
    this.description,
    this.banner,
    this.icon,
    this.pubKey,
    this.self,
    this.contact,
    Iterable<Object> nips = const [],
    this.software,
    this.version,
    this.privacyPolicy,
    this.termsOfService,
    this.paymentsUrl,
    this.limitation,
    this.fees,
    Map<String, dynamic> extra = const {},
  }) : nips = List.unmodifiable(
         SplayTreeSet<String>.of(nips.map(normalizeNip), _compareNips),
       ),
       extra = _frozenExtra(extra, _fields);

  static const _fields = {
    'name',
    'description',
    'banner',
    'icon',
    'pubkey',
    'self',
    'contact',
    'supported_nips',
    'software',
    'version',
    'privacy_policy',
    'terms_of_service',
    'payments_url',
    'limitation',
    'fees',
  };

  /// Fields with an unexpected type are read as null instead of failing the
  /// whole document. A number field takes an integer, `1.0` included. [json]
  /// can be any `Map`, such as one a Hive box gives back
  factory RelayInfo.fromJson(Map json) {
    final document = _map(json)!;
    final limitation = _map(document["limitation"]);
    final fees = _map(document["fees"]);
    return RelayInfo(
      name: _string(document["name"]),
      description: _string(document["description"]),
      banner: _string(document["banner"]),
      icon: _string(document["icon"]),
      pubKey: _string(document["pubkey"]),
      self: _string(document["self"]),
      contact: _string(document["contact"]),
      nips: [for (final nip in _list(document["supported_nips"])) ?_nip(nip)],
      software: _string(document["software"]),
      version: _string(document["version"]),
      privacyPolicy: _string(document["privacy_policy"]),
      termsOfService: _string(document["terms_of_service"]),
      paymentsUrl: _string(document["payments_url"]),
      limitation: limitation != null
          ? RelayLimitation.fromJson(limitation)
          : null,
      fees: fees != null ? RelayFees.fromJson(fees) : null,
      extra: document,
    );
  }

  /// The document under its NIP-11 names, [extra] included, without the
  /// fields left null or empty, so [RelayInfo.fromJson] reads it back, from a
  /// persistent cache for example
  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'name': ?name,
    'description': ?description,
    'banner': ?banner,
    'icon': ?icon,
    'pubkey': ?pubKey,
    'self': ?self,
    'contact': ?contact,
    if (nips.isNotEmpty)
      'supported_nips': [for (final nip in nips) _number(nip) ?? nip],
    'software': ?software,
    'version': ?version,
    'privacy_policy': ?privacyPolicy,
    'terms_of_service': ?termsOfService,
    'payments_url': ?paymentsUrl,
    'limitation': ?limitation?.toJson(),
    'fees': ?fees?.toJson(),
  };

  /// does this relay support given nip, e.g. "1", "01", "77" or "EE"
  bool supportsNip(String nip) {
    return nips.contains(normalizeNip(nip));
  }

  /// Relays list NIPs as ints (1) or strings ("01", "7D", "ee").
  static String normalizeNip(Object nip) {
    return nip.toString().trim().toUpperCase().replaceFirst(
      RegExp(r'^0+(?=.)'),
      '',
    );
  }
}

/// NIP-11 `limitation` object
class RelayLimitation with _Document {
  final int? maxMessageLength;
  final int? maxSubscriptions;
  final int? maxLimit;
  final int? maxSubidLength;
  final int? maxEventTags;
  final int? maxContentLength;
  final int? minPowDifficulty;
  final bool? authRequired;
  final bool? paymentRequired;
  final bool? restrictedWrites;

  /// Oldest accepted created_at, in seconds before now
  final int? createdAtLowerLimit;

  /// Newest accepted created_at, in seconds after now
  final int? createdAtUpperLimit;

  final int? defaultLimit;

  /// The fields this class does not read, as the relay served them, such as
  /// `max_filters`. Read-only, nested values included
  final Map<String, dynamic> extra;

  RelayLimitation({
    this.maxMessageLength,
    this.maxSubscriptions,
    this.maxLimit,
    this.maxSubidLength,
    this.maxEventTags,
    this.maxContentLength,
    this.minPowDifficulty,
    this.authRequired,
    this.paymentRequired,
    this.restrictedWrites,
    this.createdAtLowerLimit,
    this.createdAtUpperLimit,
    this.defaultLimit,
    Map<String, dynamic> extra = const {},
  }) : extra = _frozenExtra(extra, _fields);

  static const _fields = {
    'max_message_length',
    'max_subscriptions',
    'max_limit',
    'max_subid_length',
    'max_event_tags',
    'max_content_length',
    'min_pow_difficulty',
    'auth_required',
    'payment_required',
    'restricted_writes',
    'created_at_lower_limit',
    'created_at_upper_limit',
    'default_limit',
  };

  factory RelayLimitation.fromJson(Map json) {
    final document = _map(json)!;
    return RelayLimitation(
      maxMessageLength: _int(document["max_message_length"]),
      maxSubscriptions: _int(document["max_subscriptions"]),
      maxLimit: _int(document["max_limit"]),
      maxSubidLength: _int(document["max_subid_length"]),
      maxEventTags: _int(document["max_event_tags"]),
      maxContentLength: _int(document["max_content_length"]),
      minPowDifficulty: _int(document["min_pow_difficulty"]),
      authRequired: _bool(document["auth_required"]),
      paymentRequired: _bool(document["payment_required"]),
      restrictedWrites: _bool(document["restricted_writes"]),
      createdAtLowerLimit: _int(document["created_at_lower_limit"]),
      createdAtUpperLimit: _int(document["created_at_upper_limit"]),
      defaultLimit: _int(document["default_limit"]),
      extra: document,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'max_message_length': ?maxMessageLength,
    'max_subscriptions': ?maxSubscriptions,
    'max_limit': ?maxLimit,
    'max_subid_length': ?maxSubidLength,
    'max_event_tags': ?maxEventTags,
    'max_content_length': ?maxContentLength,
    'min_pow_difficulty': ?minPowDifficulty,
    'auth_required': ?authRequired,
    'payment_required': ?paymentRequired,
    'restricted_writes': ?restrictedWrites,
    'created_at_lower_limit': ?createdAtLowerLimit,
    'created_at_upper_limit': ?createdAtUpperLimit,
    'default_limit': ?defaultLimit,
  };
}

/// NIP-11 `fees` object
class RelayFees with _Document {
  final List<RelayFee> admission;
  final List<RelayFee> subscription;
  final List<RelayFee> publication;

  /// The fields this class does not read, as the relay served them.
  /// Read-only, nested values included
  final Map<String, dynamic> extra;

  RelayFees({
    Iterable<RelayFee> admission = const [],
    Iterable<RelayFee> subscription = const [],
    Iterable<RelayFee> publication = const [],
    Map<String, dynamic> extra = const {},
  }) : admission = List.unmodifiable(admission),
       subscription = List.unmodifiable(subscription),
       publication = List.unmodifiable(publication),
       extra = _frozenExtra(extra, _fields);

  static const _fields = {'admission', 'subscription', 'publication'};

  factory RelayFees.fromJson(Map json) {
    final document = _map(json)!;
    List<RelayFee> fees(Object? value) => [
      for (final fee in _list(value))
        if (_map(fee) case final json?) RelayFee.fromJson(json),
    ];
    return RelayFees(
      admission: fees(document["admission"]),
      subscription: fees(document["subscription"]),
      publication: fees(document["publication"]),
      extra: document,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    List<Map<String, dynamic>> json(List<RelayFee> fees) => [
      for (final fee in fees) fee.toJson(),
    ];
    return {
      ...extra,
      if (admission.isNotEmpty) 'admission': json(admission),
      if (subscription.isNotEmpty) 'subscription': json(subscription),
      if (publication.isNotEmpty) 'publication': json(publication),
    };
  }
}

class RelayFee with _Document {
  final int? amount;

  /// e.g. "msats"
  final String? unit;

  /// Subscription period in seconds
  final int? period;

  /// Event kinds a publication fee applies to
  final List<int> kinds;

  /// The fields this class does not read, as the relay served them.
  /// Read-only, nested values included
  final Map<String, dynamic> extra;

  RelayFee({
    this.amount,
    this.unit,
    this.period,
    Iterable<int> kinds = const [],
    Map<String, dynamic> extra = const {},
  }) : kinds = List.unmodifiable(kinds),
       extra = _frozenExtra(extra, _fields);

  static const _fields = {'amount', 'unit', 'period', 'kinds'};

  factory RelayFee.fromJson(Map json) {
    final document = _map(json)!;
    return RelayFee(
      amount: _int(document["amount"]),
      unit: _string(document["unit"]),
      period: _int(document["period"]),
      kinds: [for (final kind in _list(document["kinds"])) ?_int(kind)],
      extra: document,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    if (kinds.isNotEmpty) 'kinds': kinds,
    'amount': ?amount,
    'unit': ?unit,
    'period': ?period,
  };
}

/// Equal when their documents are. Every field is read-only, so the document
/// is built once
mixin _Document {
  Map<String, dynamic> toJson();

  late final Map<String, dynamic> _document = toJson();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Document &&
          other.runtimeType == runtimeType &&
          _equality.equals(_document, other._document);

  @override
  late final int hashCode = _equality.hash(_document);

  @override
  String toString() => '$runtimeType$_document';
}

const _equality = DeepCollectionEquality();

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => switch (value) {
  int() => value,
  // jsonDecode reads 1e400 as infinity, whose toInt throws
  double() when value.isFinite && value % 1 == 0 => value.toInt(),
  _ => null,
};

/// NIP-11 lists NIPs as integers, and lettered ones as strings
Object? _nip(Object? value) => value is String ? value : _int(value);

bool? _bool(Object? value) => value is bool ? value : null;

List<Object?> _list(Object? value) => value is List ? value : const [];

/// a map from a store such as Hive is not a `Map<String, dynamic>`
Map<String, dynamic>? _map(Object? json) => switch (json) {
  Map<String, dynamic>() => json,
  Map() => {
    for (final MapEntry(:key, :value) in json.entries)
      if (key is String) key: value,
  },
  _ => null,
};

/// [extra] without the [fields] its class reads, read-only all the way down
Map<String, dynamic> _frozenExtra(
  Map<String, dynamic> extra,
  Set<String> fields,
) => Map.unmodifiable({
  for (final MapEntry(:key, :value) in extra.entries)
    if (!fields.contains(key)) key: _frozen(value),
});

Object? _frozen(Object? value) => switch (value) {
  Map<String, dynamic>() => Map<String, dynamic>.unmodifiable(
    value.map((key, value) => MapEntry(key, _frozen(value))),
  ),
  Map() => Map.unmodifiable(
    value.map((key, value) => MapEntry(key, _frozen(value))),
  ),
  List() => List<dynamic>.unmodifiable(value.map(_frozen)),
  _ => value,
};

final _digits = RegExp(r'^\d+$');

/// null for a lettered NIP such as "7D"; `int.tryParse` alone would take "+5"
int? _number(String nip) => _digits.hasMatch(nip) ? int.tryParse(nip) : null;

int _compareNips(String a, String b) => switch ((_number(a), _number(b))) {
  (final a?, final b?) => a.compareTo(b),
  (_?, null) => -1,
  (null, _?) => 1,
  (null, null) => a.compareTo(b),
};
