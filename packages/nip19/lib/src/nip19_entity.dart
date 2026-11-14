import 'dart:convert';
import 'dart:typed_data';

import 'package:dostr_nip01/hex.dart';

import 'bech32_codec.dart';
import 'hex.dart';
import 'tlv.dart';

const _special = 0;
const _relay = 1;
const _author = 2;
const _kind = 3;

const _uriScheme = 'nostr:';

/// A NIP-19 entity: an [Npub], an [Nsec], a [Note], an [Nprofile], an
/// [Nevent] or an [Naddr].
sealed class Nip19Entity {
  const Nip19Entity();

  /// Decodes [input], with or without the `nostr:` prefix of NIP-21. Throws a
  /// [FormatException] when it is not an entity.
  factory Nip19Entity.decode(String input) => _decode(input);

  /// [input] decoded like [Nip19Entity.decode], or null when it is not an
  /// entity.
  static Nip19Entity? tryDecode(String input) =>
      _tryDecode(() => _decode(input));

  /// This entity as a bech32 string, without the `nostr:` prefix.
  String encode();
}

/// An npub: a public key.
final class Npub extends Nip19Entity {
  /// The prefix of an npub.
  static const prefix = 'npub';

  /// The public key, as lowercase hex.
  final String pubkey;

  /// Throws an [ArgumentError] when [pubkey] is not 32 bytes of hex.
  Npub(String pubkey) : pubkey = _checkKey(pubkey, 'pubkey');

  /// Decodes an npub, with or without the `nostr:` prefix. Throws a
  /// [FormatException] when [input] is not one.
  factory Npub.decode(String input) => _decode(input, prefix) as Npub;

  /// [input] decoded like [Npub.decode], or null when it is not an npub.
  static Npub? tryDecode(String input) => _tryDecode(() => Npub.decode(input));

  @override
  String encode() => encodeBech32(prefix, hexToBytes(pubkey));

  /// This npub as a NIP-21 URI: `nostr:` followed by [encode].
  String get uri => '$_uriScheme${encode()}';

  @override
  bool operator ==(Object other) => other is Npub && other.pubkey == pubkey;

  @override
  int get hashCode => pubkey.hashCode;

  @override
  String toString() => 'Npub($pubkey)';
}

/// An nsec: a private key.
final class Nsec extends Nip19Entity {
  /// The prefix of an nsec.
  static const prefix = 'nsec';

  /// The private key, as lowercase hex.
  final String privateKey;

  /// Throws an [ArgumentError] when [privateKey] is not 32 bytes of hex.
  Nsec(String privateKey) : privateKey = _checkKey(privateKey, 'privateKey');

  /// Decodes an nsec. Throws a [FormatException] when [input] is not one, or
  /// when it has the `nostr:` prefix, which NIP-21 forbids for an nsec.
  factory Nsec.decode(String input) => _decode(input, prefix) as Nsec;

  /// [input] decoded like [Nsec.decode], or null when it is not an nsec.
  static Nsec? tryDecode(String input) => _tryDecode(() => Nsec.decode(input));

  @override
  String encode() => encodeBech32(prefix, hexToBytes(privateKey));

  @override
  bool operator ==(Object other) =>
      other is Nsec && other.privateKey == privateKey;

  @override
  int get hashCode => privateKey.hashCode;

  /// Leaves the private key out, so that it never ends up in a log.
  @override
  String toString() => 'Nsec(hidden)';
}

/// A note: an event id.
final class Note extends Nip19Entity {
  /// The prefix of a note.
  static const prefix = 'note';

  /// The event id, as lowercase hex.
  final String eventId;

  /// Throws an [ArgumentError] when [eventId] is not 32 bytes of hex.
  Note(String eventId) : eventId = _checkKey(eventId, 'eventId');

  /// Decodes a note, with or without the `nostr:` prefix. Throws a
  /// [FormatException] when [input] is not one.
  factory Note.decode(String input) => _decode(input, prefix) as Note;

  /// [input] decoded like [Note.decode], or null when it is not a note.
  static Note? tryDecode(String input) => _tryDecode(() => Note.decode(input));

  @override
  String encode() => encodeBech32(prefix, hexToBytes(eventId));

  /// This note as a NIP-21 URI: `nostr:` followed by [encode].
  String get uri => '$_uriScheme${encode()}';

  @override
  bool operator ==(Object other) => other is Note && other.eventId == eventId;

  @override
  int get hashCode => eventId.hashCode;

  @override
  String toString() => 'Note($eventId)';
}

/// An nprofile: a public key, with relays where to find the profile.
final class Nprofile extends Nip19Entity {
  /// The prefix of an nprofile.
  static const prefix = 'nprofile';

  /// The public key, as lowercase hex.
  final String pubkey;

  /// Relays where the profile may be found.
  final List<String> relays;

  /// Throws an [ArgumentError] when [pubkey] is not 32 bytes of hex, or when a
  /// relay url is longer than 255 bytes.
  Nprofile({required String pubkey, List<String> relays = const []})
    : pubkey = _checkKey(pubkey, 'pubkey'),
      relays = _checkRelays(relays);

  /// Decodes an nprofile, with or without the `nostr:` prefix. Throws a
  /// [FormatException] when [input] is not one.
  factory Nprofile.decode(String input) => _decode(input, prefix) as Nprofile;

  /// [input] decoded like [Nprofile.decode], or null when it is not an
  /// nprofile.
  static Nprofile? tryDecode(String input) =>
      _tryDecode(() => Nprofile.decode(input));

  static Nprofile _fromTlv(TlvValues tlv) {
    final pubkey = _fixed(tlv, _special, 32);
    if (pubkey == null) throw const FormatException('nprofile has no pubkey');
    return Nprofile(
      pubkey: bytesToHex(pubkey),
      relays: _texts(tlv, _relay).toList(),
    );
  }

  @override
  String encode() => encodeBech32(prefix, [
    ...tlvEntry(_special, hexToBytes(pubkey)),
    ..._relayEntries(relays),
  ]);

  /// This nprofile as a NIP-21 URI: `nostr:` followed by [encode].
  String get uri => '$_uriScheme${encode()}';

  @override
  bool operator ==(Object other) =>
      other is Nprofile &&
      other.pubkey == pubkey &&
      _sameRelays(other.relays, relays);

  @override
  int get hashCode => Object.hash(pubkey, Object.hashAll(relays));

  @override
  String toString() => 'Nprofile(pubkey: $pubkey, relays: $relays)';
}

/// An nevent: an event id, with relays where to find the event and, when
/// known, its author and kind.
final class Nevent extends Nip19Entity {
  /// The prefix of an nevent.
  static const prefix = 'nevent';

  /// The event id, as lowercase hex.
  final String eventId;

  /// Relays where the event may be found.
  final List<String> relays;

  /// The public key of the author, as lowercase hex.
  final String? author;

  /// The kind of the event.
  final int? kind;

  /// Throws an [ArgumentError] when [eventId] or [author] is not 32 bytes of
  /// hex, when a relay url is longer than 255 bytes, or when [kind] does not
  /// fit 32 bits.
  Nevent({
    required String eventId,
    List<String> relays = const [],
    String? author,
    int? kind,
  }) : eventId = _checkKey(eventId, 'eventId'),
       relays = _checkRelays(relays),
       author = author == null ? null : _checkKey(author, 'author'),
       kind = kind == null ? null : _checkKind(kind);

  /// Decodes an nevent, with or without the `nostr:` prefix. Throws a
  /// [FormatException] when [input] is not one.
  factory Nevent.decode(String input) => _decode(input, prefix) as Nevent;

  /// [input] decoded like [Nevent.decode], or null when it is not an nevent.
  static Nevent? tryDecode(String input) =>
      _tryDecode(() => Nevent.decode(input));

  static Nevent _fromTlv(TlvValues tlv) {
    final eventId = _fixed(tlv, _special, 32);
    if (eventId == null) throw const FormatException('nevent has no event id');
    final author = _fixed(tlv, _author, 32);
    final kind = _fixed(tlv, _kind, 4);
    return Nevent(
      eventId: bytesToHex(eventId),
      relays: _texts(tlv, _relay).toList(),
      author: author == null ? null : bytesToHex(author),
      kind: kind == null ? null : _readUint32(kind),
    );
  }

  @override
  String encode() => encodeBech32(prefix, [
    ...tlvEntry(_special, hexToBytes(eventId)),
    ..._relayEntries(relays),
    if (author case final author?) ...tlvEntry(_author, hexToBytes(author)),
    if (kind case final kind?) ...tlvEntry(_kind, _uint32(kind)),
  ]);

  /// This nevent as a NIP-21 URI: `nostr:` followed by [encode].
  String get uri => '$_uriScheme${encode()}';

  @override
  bool operator ==(Object other) =>
      other is Nevent &&
      other.eventId == eventId &&
      _sameRelays(other.relays, relays) &&
      other.author == author &&
      other.kind == kind;

  @override
  int get hashCode =>
      Object.hash(eventId, Object.hashAll(relays), author, kind);

  @override
  String toString() =>
      'Nevent(eventId: $eventId, relays: $relays, author: $author, '
      'kind: $kind)';
}

/// An naddr: the coordinate of an addressable or replaceable event, with
/// relays where to find it.
final class Naddr extends Nip19Entity {
  /// The prefix of an naddr.
  static const prefix = 'naddr';

  /// The `d` tag of the event, empty for a replaceable event.
  final String identifier;

  /// The public key of the author, as lowercase hex.
  final String pubkey;

  /// The kind of the event.
  final int kind;

  /// Relays where the event may be found.
  final List<String> relays;

  /// Throws an [ArgumentError] when [pubkey] is not 32 bytes of hex, when
  /// [identifier] or a relay url is longer than 255 bytes, or when [kind] does
  /// not fit 32 bits.
  Naddr({
    required String identifier,
    required String pubkey,
    required int kind,
    List<String> relays = const [],
  }) : identifier = _checkTlvValue(identifier, 'identifier'),
       pubkey = _checkKey(pubkey, 'pubkey'),
       kind = _checkKind(kind),
       relays = _checkRelays(relays);

  /// Decodes an naddr, with or without the `nostr:` prefix. Throws a
  /// [FormatException] when [input] is not one.
  factory Naddr.decode(String input) => _decode(input, prefix) as Naddr;

  /// [input] decoded like [Naddr.decode], or null when it is not an naddr.
  static Naddr? tryDecode(String input) =>
      _tryDecode(() => Naddr.decode(input));

  static Naddr _fromTlv(TlvValues tlv) {
    final identifier = _texts(tlv, _special).firstOrNull;
    final pubkey = _fixed(tlv, _author, 32);
    final kind = _fixed(tlv, _kind, 4);
    if (identifier == null) {
      throw const FormatException('naddr has no identifier');
    }
    if (pubkey == null) throw const FormatException('naddr has no author');
    if (kind == null) throw const FormatException('naddr has no kind');
    return Naddr(
      identifier: identifier,
      pubkey: bytesToHex(pubkey),
      kind: _readUint32(kind),
      relays: _texts(tlv, _relay).toList(),
    );
  }

  /// The coordinate of the event in an `a` tag (NIP-01):
  /// `<kind>:<pubkey>:<identifier>`.
  String get coordinate => '$kind:$pubkey:$identifier';

  @override
  String encode() => encodeBech32(prefix, [
    ...tlvEntry(_special, utf8.encode(identifier)),
    ..._relayEntries(relays),
    ...tlvEntry(_author, hexToBytes(pubkey)),
    ...tlvEntry(_kind, _uint32(kind)),
  ]);

  /// This naddr as a NIP-21 URI: `nostr:` followed by [encode].
  String get uri => '$_uriScheme${encode()}';

  @override
  bool operator ==(Object other) =>
      other is Naddr &&
      other.identifier == identifier &&
      other.pubkey == pubkey &&
      other.kind == kind &&
      _sameRelays(other.relays, relays);

  @override
  int get hashCode =>
      Object.hash(identifier, pubkey, kind, Object.hashAll(relays));

  @override
  String toString() =>
      'Naddr(identifier: $identifier, pubkey: $pubkey, kind: $kind, '
      'relays: $relays)';
}

Nip19Entity _decode(String input, [String? expectedPrefix]) {
  final (prefix, bytes) = decodeBech32(_withoutUriScheme(input));
  if (expectedPrefix != null && prefix != expectedPrefix) {
    throw FormatException('Expected $expectedPrefix, got $prefix');
  }
  return switch (prefix) {
    Npub.prefix => Npub(_key(prefix, bytes)),
    Nsec.prefix => Nsec(_key(prefix, bytes)),
    Note.prefix => Note(_key(prefix, bytes)),
    Nprofile.prefix => Nprofile._fromTlv(parseTlv(bytes)),
    Nevent.prefix => Nevent._fromTlv(parseTlv(bytes)),
    Naddr.prefix => Naddr._fromTlv(parseTlv(bytes)),
    _ => throw FormatException('Unsupported prefix $prefix'),
  };
}

String _withoutUriScheme(String input) {
  if (!input.toLowerCase().startsWith(_uriScheme)) return input;
  final entity = input.substring(_uriScheme.length);
  if (entity.toLowerCase().startsWith(Nsec.prefix)) {
    throw const FormatException('NIP-21 forbids an nsec in a nostr: URI');
  }
  return entity;
}

T? _tryDecode<T>(T Function() decode) {
  try {
    return decode();
  } on FormatException {
    return null;
  }
}

String _key(String prefix, List<int> bytes) {
  if (bytes.length != 32) {
    throw FormatException('$prefix holds ${bytes.length} bytes instead of 32');
  }
  return bytesToHex(bytes);
}

String _checkKey(String value, String name) {
  final key = value.toLowerCase();
  if (!isLowercaseHex(key, length: 64)) {
    throw ArgumentError('must be 32 bytes of hex', name);
  }
  return key;
}

String _checkTlvValue(String value, String name) {
  final length = utf8.encode(value).length;
  if (length > 255) {
    throw ArgumentError('is $length bytes long, more than 255', name);
  }
  return value;
}

List<String> _checkRelays(List<String> relays) =>
    List.unmodifiable(relays.map((relay) => _checkTlvValue(relay, 'relays')));

int _checkKind(int kind) =>
    RangeError.checkValueInInterval(kind, 0, 0xffffffff, 'kind');

List<int>? _fixed(TlvValues tlv, int type, int length) =>
    tlv[type]?.where((value) => value.length == length).firstOrNull;

Iterable<String> _texts(TlvValues tlv, int type) =>
    (tlv[type] ?? const <List<int>>[]).map(_utf8OrNull).nonNulls;

String? _utf8OrNull(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

List<int> _relayEntries(List<String> relays) => [
  for (final relay in relays) ...tlvEntry(_relay, utf8.encode(relay)),
];

List<int> _uint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

int _readUint32(List<int> bytes) =>
    ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0);

bool _sameRelays(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
