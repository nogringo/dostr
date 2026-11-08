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

  /// Supported NIPs, normalized by [normalizeNip]
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
  /// `retention` or `relay_countries`
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
  }) : nips = List.unmodifiable(nips.map(normalizeNip)),
       extra = Map.unmodifiable(extra);

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
  /// whole document. A number field takes an integer, `1.0` included
  factory RelayInfo.fromJson(Map<String, dynamic> json) {
    final limitation = _map(json["limitation"]);
    final fees = _map(json["fees"]);
    return RelayInfo(
      name: _string(json["name"]),
      description: _string(json["description"]),
      banner: _string(json["banner"]),
      icon: _string(json["icon"]),
      pubKey: _string(json["pubkey"]),
      self: _string(json["self"]),
      contact: _string(json["contact"]),
      nips: [for (final nip in _list(json["supported_nips"])) ?_nip(nip)],
      software: _string(json["software"]),
      version: _string(json["version"]),
      privacyPolicy: _string(json["privacy_policy"]),
      termsOfService: _string(json["terms_of_service"]),
      paymentsUrl: _string(json["payments_url"]),
      limitation: limitation != null
          ? RelayLimitation.fromJson(limitation)
          : null,
      fees: fees != null ? RelayFees.fromJson(fees) : null,
      extra: _extra(json, _fields),
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
      'supported_nips': [for (final nip in nips) int.tryParse(nip) ?? nip],
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
  /// `max_filters`
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
  }) : extra = Map.unmodifiable(extra);

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

  factory RelayLimitation.fromJson(Map<String, dynamic> json) {
    return RelayLimitation(
      maxMessageLength: _int(json["max_message_length"]),
      maxSubscriptions: _int(json["max_subscriptions"]),
      maxLimit: _int(json["max_limit"]),
      maxSubidLength: _int(json["max_subid_length"]),
      maxEventTags: _int(json["max_event_tags"]),
      maxContentLength: _int(json["max_content_length"]),
      minPowDifficulty: _int(json["min_pow_difficulty"]),
      authRequired: _bool(json["auth_required"]),
      paymentRequired: _bool(json["payment_required"]),
      restrictedWrites: _bool(json["restricted_writes"]),
      createdAtLowerLimit: _int(json["created_at_lower_limit"]),
      createdAtUpperLimit: _int(json["created_at_upper_limit"]),
      defaultLimit: _int(json["default_limit"]),
      extra: _extra(json, _fields),
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

  /// The fields this class does not read, as the relay served them
  final Map<String, dynamic> extra;

  RelayFees({
    Iterable<RelayFee> admission = const [],
    Iterable<RelayFee> subscription = const [],
    Iterable<RelayFee> publication = const [],
    Map<String, dynamic> extra = const {},
  }) : admission = List.unmodifiable(admission),
       subscription = List.unmodifiable(subscription),
       publication = List.unmodifiable(publication),
       extra = Map.unmodifiable(extra);

  static const _fields = {'admission', 'subscription', 'publication'};

  factory RelayFees.fromJson(Map<String, dynamic> json) {
    List<RelayFee> fees(Object? value) => [
      for (final fee in _list(value))
        if (_map(fee) case final json?) RelayFee.fromJson(json),
    ];
    return RelayFees(
      admission: fees(json["admission"]),
      subscription: fees(json["subscription"]),
      publication: fees(json["publication"]),
      extra: _extra(json, _fields),
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

  /// The fields this class does not read, as the relay served them
  final Map<String, dynamic> extra;

  RelayFee({
    this.amount,
    this.unit,
    this.period,
    Iterable<int> kinds = const [],
    Map<String, dynamic> extra = const {},
  }) : kinds = List.unmodifiable(kinds),
       extra = Map.unmodifiable(extra);

  static const _fields = {'amount', 'unit', 'period', 'kinds'};

  factory RelayFee.fromJson(Map<String, dynamic> json) {
    return RelayFee(
      amount: _int(json["amount"]),
      unit: _string(json["unit"]),
      period: _int(json["period"]),
      kinds: [for (final kind in _list(json["kinds"])) ?_int(kind)],
      extra: _extra(json, _fields),
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

/// Equal when their documents are
mixin _Document {
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          _equality.equals(toJson(), (other as _Document).toJson());

  @override
  int get hashCode => _equality.hash(toJson());

  @override
  String toString() => '$runtimeType${toJson()}';
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

Map<String, dynamic> _extra(Map<String, dynamic> json, Set<String> fields) => {
  for (final MapEntry(:key, :value) in json.entries)
    if (!fields.contains(key)) key: value,
};
