import 'package:dostr_relay_url/dostr_relay_url.dart';

final _name = RegExp(r'^[a-z0-9._-]+$');

final _domain = RegExp(
  r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$',
);

/// A NIP-05 identifier and what its domain gives for it.
class Nip05 {
  /// the identifier as [canonicalIdentifier] gives it
  final String identifier;

  /// in lowercase hex
  final String pubkey;

  /// the relays the domain gives for [pubkey], each once
  final List<RelayUrl> relays;

  const Nip05({
    required this.identifier,
    required this.pubkey,
    this.relays = const [],
  });

  /// [json] can be any `Map`, such as one a Hive box gives back
  factory Nip05.fromJson(Map json) => Nip05(
    identifier: json['identifier'] as String,
    pubkey: json['pubkey'] as String,
    relays: [
      for (final relay in json['relays'] as List? ?? const [])
        ?RelayUrl.tryParse(relay as String),
    ],
  );

  Map<String, dynamic> toJson() => {
    'identifier': identifier,
    'pubkey': pubkey,
    'relays': relays,
  };

  /// Lowercased `name@domain` form of [identifier], or null when it is not a
  /// NIP-05 identifier: the name holds only `a-z0-9-_.`, as NIP-05 allows, and
  /// the domain is a host name with at least one dot.
  /// A bare `domain` is the display form of the root identifier `_@domain`, so
  /// a bare `bob` is not one.
  static String? canonicalIdentifier(String identifier) {
    final parts = identifier.trim().toLowerCase().split('@');
    if (parts.length == 1) {
      parts.insert(0, '_');
    }
    if (parts.length != 2) {
      return null;
    }
    final [name, domain] = parts;
    if (!_name.hasMatch(name) || !_domain.hasMatch(domain)) {
      return null;
    }
    return '$name@$domain';
  }

  @override
  bool operator ==(Object other) =>
      other is Nip05 &&
      other.identifier == identifier &&
      other.pubkey == pubkey &&
      _sameRelays(other.relays, relays);

  @override
  int get hashCode => Object.hash(identifier, pubkey, Object.hashAll(relays));

  @override
  String toString() => 'Nip05${toJson()}';
}

bool _sameRelays(List<RelayUrl> a, List<RelayUrl> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
