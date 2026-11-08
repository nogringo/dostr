/// NIP-11 relay information document, as declared by the relay and not
/// verified. Every field the relay omits is null
class RelayInfo {
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

  RelayInfo._({
    required this.nips,
    this.name,
    this.description,
    this.banner,
    this.icon,
    this.pubKey,
    this.self,
    this.contact,
    this.software,
    this.version,
    this.privacyPolicy,
    this.termsOfService,
    this.paymentsUrl,
    this.limitation,
    this.fees,
  });

  /// Fields with an unexpected type are read as null instead of failing the
  /// whole document
  factory RelayInfo.fromJson(Map<String, dynamic> json) {
    final limitation = json["limitation"];
    final fees = json["fees"];
    return RelayInfo._(
      name: _string(json["name"]),
      description: _string(json["description"]),
      banner: _string(json["banner"]),
      icon: _string(json["icon"]),
      pubKey: _string(json["pubkey"]),
      self: _string(json["self"]),
      contact: _string(json["contact"]),
      nips: List.unmodifiable([
        for (final nip in _list(json["supported_nips"]))
          if (nip != null) normalizeNip(nip),
      ]),
      software: _string(json["software"]),
      version: _string(json["version"]),
      privacyPolicy: _string(json["privacy_policy"]),
      termsOfService: _string(json["terms_of_service"]),
      paymentsUrl: _string(json["payments_url"]),
      limitation: limitation is Map<String, dynamic>
          ? RelayLimitation.fromJson(limitation)
          : null,
      fees: fees is Map<String, dynamic> ? RelayFees.fromJson(fees) : null,
    );
  }

  /// The document under its NIP-11 names, without the fields left null or
  /// empty, so [RelayInfo.fromJson] reads it back, from a persistent cache
  /// for example
  Map<String, dynamic> toJson() => {
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
class RelayLimitation {
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

  RelayLimitation._({
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
  });

  factory RelayLimitation.fromJson(Map<String, dynamic> json) {
    return RelayLimitation._(
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
    );
  }

  Map<String, dynamic> toJson() => {
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
class RelayFees {
  final List<RelayFee> admission;
  final List<RelayFee> subscription;
  final List<RelayFee> publication;

  RelayFees._({
    required this.admission,
    required this.subscription,
    required this.publication,
  });

  factory RelayFees.fromJson(Map<String, dynamic> json) {
    List<RelayFee> fees(Object? value) => List.unmodifiable([
      for (final fee in _list(value))
        if (fee is Map<String, dynamic>) RelayFee.fromJson(fee),
    ]);
    return RelayFees._(
      admission: fees(json["admission"]),
      subscription: fees(json["subscription"]),
      publication: fees(json["publication"]),
    );
  }

  Map<String, dynamic> toJson() {
    List<Map<String, dynamic>> json(List<RelayFee> fees) => [
      for (final fee in fees) fee.toJson(),
    ];
    return {
      if (admission.isNotEmpty) 'admission': json(admission),
      if (subscription.isNotEmpty) 'subscription': json(subscription),
      if (publication.isNotEmpty) 'publication': json(publication),
    };
  }
}

class RelayFee {
  final int? amount;

  /// e.g. "msats"
  final String? unit;

  /// Subscription period in seconds
  final int? period;

  /// Event kinds a publication fee applies to
  final List<int> kinds;

  RelayFee._({required this.kinds, this.amount, this.unit, this.period});

  factory RelayFee.fromJson(Map<String, dynamic> json) {
    return RelayFee._(
      amount: _int(json["amount"]),
      unit: _string(json["unit"]),
      period: _int(json["period"]),
      kinds: List.unmodifiable(_list(json["kinds"]).whereType<int>()),
    );
  }

  Map<String, dynamic> toJson() => {
    if (kinds.isNotEmpty) 'kinds': kinds,
    'amount': ?amount,
    'unit': ?unit,
    'period': ?period,
  };
}

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

bool? _bool(Object? value) => value is bool ? value : null;

List<Object?> _list(Object? value) => value is List ? value : const [];
