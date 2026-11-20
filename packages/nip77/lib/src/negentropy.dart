import 'dart:collection';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Negentropy Protocol V1 codec, as specified in the NIP-77 appendix.
///
/// See https://github.com/hoytech/negentropy/blob/master/docs/negentropy-protocol-v1.md
class NegentropyEncoder {
  /// Protocol version byte (version 1)
  static const int protocolVersion = 0x61;

  /// Size of event ID in bytes (32 bytes = 64 hex chars)
  static const int idSize = 32;

  /// Size of fingerprint in bytes
  static const int fingerprintSize = 16;

  /// Mode constants
  static const int modeSkip = 0;
  static const int modeFingerprint = 1;
  static const int modeIdList = 2;

  /// Reserved "infinity" timestamp. The spec reserves `2**64 - 1`, which does
  /// not survive dart2js; this sentinel is the largest exactly representable
  /// integer on both native and web, and never touches the wire (infinity is
  /// always encoded as `0`).
  static const int infiniteTimestamp = 9007199254740991;

  /// Smallest frame size limit [reconcile] and [respond] take, other than 0.
  /// The first range of a message always fits in it.
  static const int minFrameSizeLimit = 4096;

  /// Room a frame size limit keeps for the fingerprint that ends a message
  /// cut short, as in the reference implementation
  static const int _frameSizeMargin = 200;

  /// Number of sub-ranges a mismatching range is split into
  static const int _buckets = 16;

  /// Ranges with fewer items than this are sent as an id list instead of split
  static const int _idListThreshold = _buckets * 2;

  /// Encodes an integer as a varint (base-128, most significant digit first)
  static Uint8List encodeVarint(int value) {
    if (value < 0) {
      throw ArgumentError('Varint value must be non-negative');
    }

    if (value == 0) {
      return Uint8List.fromList([0]);
    }

    final bytes = <int>[];
    var remaining = value;

    while (remaining > 0) {
      bytes.insert(0, remaining % 128);
      remaining = remaining ~/ 128;
    }

    for (var i = 0; i < bytes.length - 1; i++) {
      bytes[i] |= 0x80;
    }

    return Uint8List.fromList(bytes);
  }

  /// Decodes a varint from bytes, returns (value, bytesConsumed)
  static (int value, int bytesConsumed) decodeVarint(
    Uint8List data, [
    int offset = 0,
  ]) {
    var value = 0;
    var bytesConsumed = 0;

    while (true) {
      if (offset + bytesConsumed >= data.length) {
        throw ArgumentError('Truncated varint');
      }

      final byte = data[offset + bytesConsumed];
      bytesConsumed++;

      final digit = byte & 0x7F;
      if (value > (infiniteTimestamp - digit) ~/ 128) {
        throw ArgumentError('Varint exceeds the supported integer range');
      }
      value = value * 128 + digit;

      if ((byte & 0x80) == 0) {
        return (value, bytesConsumed);
      }
    }
  }

  /// Calculates the fingerprint of a range: the first 16 bytes of
  /// `SHA256(sum of the IDs mod 2^256, little-endian || varint(count))`.
  static Uint8List calculateFingerprint(List<Uint8List> ids) {
    final accumulator = Uint8List(idSize);
    for (final id in ids) {
      _addId(accumulator, id);
    }
    return _digest(accumulator, ids.length);
  }

  /// [calculateFingerprint] of the ids of `items[lower..upper)`
  static Uint8List _fingerprint(
    List<NegentropyItem> items,
    int lower,
    int upper,
  ) {
    final accumulator = Uint8List(idSize);
    for (var i = lower; i < upper; i++) {
      _addId(accumulator, items[i].id);
    }
    return _digest(accumulator, upper - lower);
  }

  static void _addId(Uint8List accumulator, Uint8List id) {
    var carry = 0;
    for (var i = 0; i < idSize; i++) {
      final sum = accumulator[i] + (i < id.length ? id[i] : 0) + carry;
      accumulator[i] = sum & 0xFF;
      carry = sum >> 8;
    }
  }

  static Uint8List _digest(Uint8List accumulator, int count) {
    final digest = sha256.convert([...accumulator, ...encodeVarint(count)]);
    return Uint8List.fromList(digest.bytes.sublist(0, fingerprintSize));
  }

  /// Encodes a bound. Timestamps are delta encoded against [lastTimestamp],
  /// which is the timestamp of the previously encoded bound in the same
  /// message (0 at the start of every message).
  static Uint8List encodeBound(
    int timestamp,
    Uint8List idPrefix, {
    int lastTimestamp = 0,
  }) {
    if (idPrefix.length > idSize) {
      throw ArgumentError('Bound ID prefix must be at most $idSize bytes');
    }

    final output = BytesBuilder();

    if (timestamp >= infiniteTimestamp) {
      output.addByte(0);
    } else {
      if (timestamp < lastTimestamp) {
        throw ArgumentError('Bound timestamps must be non-decreasing');
      }
      output.add(encodeVarint(timestamp - lastTimestamp + 1));
    }

    output.add(encodeVarint(idPrefix.length));
    output.add(idPrefix);

    return output.toBytes();
  }

  /// Decodes a bound. [lastTimestamp] is the timestamp of the previously
  /// decoded bound in the same message (0 at the start of every message).
  static (int timestamp, Uint8List idPrefix, int bytesConsumed) decodeBound(
    Uint8List data, [
    int offset = 0,
    int lastTimestamp = 0,
  ]) {
    var pos = offset;

    final (encodedTimestamp, timestampBytes) = decodeVarint(data, pos);
    pos += timestampBytes;

    final int timestamp;
    if (encodedTimestamp == 0) {
      timestamp = infiniteTimestamp;
    } else {
      timestamp = lastTimestamp + encodedTimestamp - 1;
      if (timestamp >= infiniteTimestamp) {
        throw ArgumentError('Bound timestamp out of range');
      }
    }

    final (prefixLength, lengthBytes) = decodeVarint(data, pos);
    pos += lengthBytes;

    if (prefixLength > idSize) {
      throw ArgumentError('Bound ID prefix too long: $prefixLength');
    }
    if (pos + prefixLength > data.length) {
      throw ArgumentError('Truncated bound ID prefix');
    }

    final idPrefix = Uint8List.fromList(data.sublist(pos, pos + prefixLength));
    pos += prefixLength;

    return (timestamp, idPrefix, pos - offset);
  }

  /// Parses a hex string to bytes. Throws an [ArgumentError] for an odd
  /// length and a [FormatException] for a character that is not a hex digit.
  static Uint8List hexToBytes(String hex) {
    if (hex.length.isOdd) {
      throw ArgumentError('Hex string must have even length');
    }
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      final high = _hexValue(hex.codeUnitAt(2 * i));
      final low = _hexValue(hex.codeUnitAt(2 * i + 1));
      if (high < 0 || low < 0) {
        throw FormatException(
          'Not a hex digit at offset ${high < 0 ? 2 * i : 2 * i + 1}',
        );
      }
      result[i] = high << 4 | low;
    }
    return result;
  }

  /// Value of the hex digit [codeUnit], or -1
  static int _hexValue(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30;
    final lower = codeUnit | 0x20;
    if (lower >= 0x61 && lower <= 0x66) return lower - 0x57;
    return -1;
  }

  /// Converts bytes to hex string
  static String bytesToHex(List<int> bytes) {
    final codeUnits = Uint8List(bytes.length * 2);
    for (var i = 0; i < bytes.length; i++) {
      final byte = bytes[i];
      codeUnits[2 * i] = _hexDigits.codeUnitAt(byte >> 4);
      codeUnits[2 * i + 1] = _hexDigits.codeUnitAt(byte & 0x0F);
    }
    return String.fromCharCodes(codeUnits);
  }

  static const String _hexDigits = '0123456789abcdef';

  /// Creates the initial message an initiator sends in `NEG-OPEN`.
  static Uint8List createInitialMessage(
    List<NegentropyItem> items, [
    int itemIdSize = idSize,
  ]) {
    if (itemIdSize != idSize) {
      throw ArgumentError('Negentropy v1 requires $idSize byte IDs');
    }

    final sorted = _prepare(items);
    final output = _MessageWriter()..addByte(protocolVersion);
    _splitRange(sorted, 0, sorted.length, _infinityBound, output);

    return output.toBytes();
  }

  /// Reconciles a message received from the other side as the initiator.
  ///
  /// Returns the response to send back plus the IDs discovered so far:
  /// [needIds] are held by the other side only, [haveIds] by us only. A
  /// response consisting of nothing but the version byte means the
  /// reconciliation has converged.
  ///
  /// A [frameSizeLimit] other than 0 keeps the response within that many
  /// bytes, and is at least [minFrameSizeLimit]. A response cut short ends on
  /// one fingerprint for the rest of the set, which the next rounds split
  /// again. [items] can come in any order, and are not changed.
  static (Uint8List response, List<String> needIds, List<String> haveIds)
  reconcile(
    Uint8List message,
    List<NegentropyItem> items, {
    int frameSizeLimit = 0,
  }) {
    final needIds = <String>[];
    final haveIds = <String>[];
    final response = _reconcileAux(
      message,
      items,
      isInitiator: true,
      frameSizeLimit: frameSizeLimit,
      needIds: needIds,
      haveIds: haveIds,
    );
    return (response, needIds, haveIds);
  }

  /// Reconciles a message received from an initiator, as the responding side.
  ///
  /// Only the initiator learns the have/need sets, so this returns just the
  /// response message. [frameSizeLimit] works as in [reconcile].
  static Uint8List respond(
    Uint8List message,
    List<NegentropyItem> items, {
    int frameSizeLimit = 0,
  }) {
    return _reconcileAux(
      message,
      items,
      isInitiator: false,
      frameSizeLimit: frameSizeLimit,
      needIds: [],
      haveIds: [],
    );
  }

  static Uint8List _reconcileAux(
    Uint8List message,
    List<NegentropyItem> items, {
    required bool isInitiator,
    required int frameSizeLimit,
    required List<String> needIds,
    required List<String> haveIds,
  }) {
    checkFrameSizeLimit(frameSizeLimit);
    if (message.isEmpty) {
      throw ArgumentError('Empty negentropy message');
    }
    if (message[0] != protocolVersion) {
      throw ArgumentError(
        'Unsupported negentropy protocol version: '
        '0x${message[0].toRadixString(16)}',
      );
    }

    final sorted = _prepare(items);
    final output = _MessageWriter()..addByte(protocolVersion);
    bool exceedsFrame(int length) =>
        frameSizeLimit != 0 && length > frameSizeLimit - _frameSizeMargin;

    var offset = 1;
    var lastTimestampIn = 0;
    var prevBound = _Bound(0, Uint8List(0));
    var prevIndex = 0;
    var pendingSkip = false;

    // Adjacent skipped ranges are coalesced into one, emitted only once a
    // range that carries a payload follows.
    void flushSkip() {
      if (!pendingSkip) return;
      pendingSkip = false;
      output.addBound(prevBound);
      output.addVarint(modeSkip);
    }

    while (offset < message.length) {
      final (timestamp, idPrefix, boundBytes) = decodeBound(
        message,
        offset,
        lastTimestampIn,
      );
      offset += boundBytes;
      lastTimestampIn = timestamp;
      final currBound = _Bound(timestamp, idPrefix);

      if (offset >= message.length) {
        throw ArgumentError('Truncated range: missing mode');
      }
      final (mode, modeBytes) = decodeVarint(message, offset);
      offset += modeBytes;

      final lower = prevIndex;
      var upper = _lowerBound(sorted, prevIndex, currBound);

      // what this range adds to the response, dropped if it does not fit
      _MessageWriter? range;

      switch (mode) {
        case modeSkip:
          pendingSkip = true;

        case modeFingerprint:
          if (offset + fingerprintSize > message.length) {
            throw ArgumentError('Truncated fingerprint');
          }
          final theirFingerprint = Uint8List.sublistView(
            message,
            offset,
            offset + fingerprintSize,
          );
          offset += fingerprintSize;

          final ourFingerprint = _fingerprint(sorted, lower, upper);

          if (_bytesEqual(theirFingerprint, ourFingerprint)) {
            pendingSkip = true;
          } else {
            flushSkip();
            range = output.continuation();
            _splitRange(sorted, lower, upper, currBound, range);
          }

        case modeIdList:
          final (count, countBytes) = decodeVarint(message, offset);
          offset += countBytes;
          if (count > (message.length - offset) ~/ idSize) {
            throw ArgumentError('Truncated ID list');
          }

          final theirIds = <String>{};
          for (var i = 0; i < count; i++) {
            theirIds.add(
              bytesToHex(
                Uint8List.sublistView(message, offset, offset + idSize),
              ),
            );
            offset += idSize;
          }

          if (isInitiator) {
            for (var i = lower; i < upper; i++) {
              final ourId = bytesToHex(sorted[i].id);
              if (!theirIds.remove(ourId)) {
                haveIds.add(ourId);
              }
            }
            needIds.addAll(theirIds);
            pendingSkip = true;
          } else {
            flushSkip();
            // as many ids as fit, the rest goes to the fingerprint below
            var end = lower;
            while (end < upper &&
                !exceedsFrame(output.length + (end - lower + 1) * idSize)) {
              end++;
            }
            output.addBound(
              end == upper
                  ? currBound
                  : _Bound(sorted[end].timestamp, sorted[end].id),
            );
            output.addVarint(modeIdList);
            output.addVarint(end - lower);
            for (var i = lower; i < end; i++) {
              output.addBytes(sorted[i].id);
            }
            upper = end;
          }

        default:
          throw ArgumentError('Unknown negentropy mode: $mode');
      }

      if (exceedsFrame(output.length + (range?.length ?? 0))) {
        output.addBound(_infinityBound);
        output.addVarint(modeFingerprint);
        output.addBytes(
          _fingerprint(sorted, range == null ? upper : lower, sorted.length),
        );
        return output.toBytes();
      }
      if (range != null) output.append(range);

      prevBound = currBound;
      prevIndex = upper;
    }

    // A trailing skip needs no encoding: the spec appends an implicit skip to
    // infinity after the last range.
    return output.toBytes();
  }

  /// Emits [lower, upper) either as an id list or as [_buckets] sub-ranges
  /// covered by fingerprints, ending on [upperBound].
  static void _splitRange(
    List<NegentropyItem> items,
    int lower,
    int upper,
    _Bound upperBound,
    _MessageWriter output,
  ) {
    final numElems = upper - lower;

    if (numElems < _idListThreshold) {
      output.addBound(upperBound);
      output.addVarint(modeIdList);
      output.addVarint(numElems);
      for (var i = lower; i < upper; i++) {
        output.addBytes(items[i].id);
      }
      return;
    }

    final itemsPerBucket = numElems ~/ _buckets;
    final bucketsWithExtra = numElems % _buckets;
    var curr = lower;

    for (var i = 0; i < _buckets; i++) {
      final bucketSize = itemsPerBucket + (i < bucketsWithExtra ? 1 : 0);
      final next = curr + bucketSize;

      final bound = next >= upper
          ? upperBound
          : _minimalBound(items[next - 1], items[next]);

      output.addBound(bound);
      output.addVarint(modeFingerprint);
      output.addBytes(_fingerprint(items, curr, next));

      curr = next;
    }
  }

  /// Shortest bound that separates [prev] from [curr]
  static _Bound _minimalBound(NegentropyItem prev, NegentropyItem curr) {
    if (curr.timestamp != prev.timestamp) {
      return _Bound(curr.timestamp, Uint8List(0));
    }

    var shared = 0;
    while (shared < idSize && curr.id[shared] == prev.id[shared]) {
      shared++;
    }

    return _Bound(
      curr.timestamp,
      Uint8List.fromList(
        curr.id.sublist(0, shared + 1 > idSize ? idSize : shared + 1),
      ),
    );
  }

  /// Index of the first item at or after [bound], searching from [from]
  static int _lowerBound(List<NegentropyItem> items, int from, _Bound bound) {
    var low = from;
    var high = items.length;

    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (_compareItemToBound(items[mid], bound) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    return low;
  }

  /// [items] sorted by (timestamp, id) ascending without duplicates, as is
  /// when [prepareNegentropyItems] already did it
  static List<NegentropyItem> _prepare(List<NegentropyItem> items) =>
      items is _PreparedItems ? items._items : _sortedUnique(items);

  static List<NegentropyItem> _sortedUnique(Iterable<NegentropyItem> items) {
    final sorted = [...items]..sort(_compareItems);

    final unique = <NegentropyItem>[];
    for (final item in sorted) {
      if (unique.isNotEmpty && _compareItems(unique.last, item) == 0) {
        continue;
      }
      unique.add(item);
    }

    return unique;
  }

  static int _compareItems(NegentropyItem a, NegentropyItem b) {
    final timestampCmp = a.timestamp.compareTo(b.timestamp);
    if (timestampCmp != 0) return timestampCmp;
    return _compareBytes(a.id, b.id);
  }

  /// Compares an item against a bound whose ID prefix is implicitly
  /// zero-padded to [idSize] bytes.
  static int _compareItemToBound(NegentropyItem item, _Bound bound) {
    if (item.timestamp != bound.timestamp) {
      return item.timestamp.compareTo(bound.timestamp);
    }
    for (var i = 0; i < idSize; i++) {
      final boundByte = i < bound.idPrefix.length ? bound.idPrefix[i] : 0;
      if (item.id[i] != boundByte) {
        return item.id[i].compareTo(boundByte);
      }
    }
    return 0;
  }

  static int _compareBytes(Uint8List a, Uint8List b) {
    final minLength = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLength; i++) {
      if (a[i] != b[i]) {
        return a[i].compareTo(b[i]);
      }
    }
    return a.length.compareTo(b.length);
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static final _Bound _infinityBound = _Bound(infiniteTimestamp, Uint8List(0));
}

/// Throws an [ArgumentError] for a frame size limit
/// [NegentropyEncoder.reconcile] and [NegentropyEncoder.respond] do not take.
void checkFrameSizeLimit(int frameSizeLimit) {
  if (frameSizeLimit != 0 &&
      frameSizeLimit < NegentropyEncoder.minFrameSizeLimit) {
    throw ArgumentError.value(
      frameSizeLimit,
      'frameSizeLimit',
      'must be 0 or at least ${NegentropyEncoder.minFrameSizeLimit}',
    );
  }
}

/// [items] sorted and without duplicates once, so a session that reconciles
/// them over many rounds does not sort them again each round.
List<NegentropyItem> prepareNegentropyItems(Iterable<NegentropyItem> items) =>
    _PreparedItems(NegentropyEncoder._sortedUnique(items));

final class _PreparedItems extends UnmodifiableListView<NegentropyItem> {
  _PreparedItems(this._items) : super(_items);

  final List<NegentropyItem> _items;
}

/// Represents an item for negentropy reconciliation
class NegentropyItem {
  final int timestamp;
  final Uint8List id;

  NegentropyItem({required this.timestamp, required this.id}) {
    if (id.length != NegentropyEncoder.idSize) {
      throw ArgumentError(
        'Negentropy IDs must be ${NegentropyEncoder.idSize} bytes, '
        'got ${id.length}',
      );
    }
    if (timestamp < 0 || timestamp >= NegentropyEncoder.infiniteTimestamp) {
      throw ArgumentError('Negentropy timestamp out of range: $timestamp');
    }
  }

  factory NegentropyItem.fromHex({
    required int timestamp,
    required String idHex,
  }) {
    return NegentropyItem(
      timestamp: timestamp,
      id: NegentropyEncoder.hexToBytes(idHex),
    );
  }
}

/// Accumulates a message while delta encoding bound timestamps against the
/// previously written bound.
class _MessageWriter {
  _MessageWriter([this._lastTimestamp = 0]);

  final BytesBuilder _output = BytesBuilder(copy: false);
  int _lastTimestamp;

  int get length => _output.length;

  /// A writer whose bounds follow the ones written here so far, for
  /// [append] to add back
  _MessageWriter continuation() => _MessageWriter(_lastTimestamp);

  void append(_MessageWriter continued) {
    _output.add(continued._output.takeBytes());
    _lastTimestamp = continued._lastTimestamp;
  }

  void addByte(int byte) => _output.addByte(byte);

  void addBytes(Uint8List bytes) => _output.add(bytes);

  void addVarint(int value) =>
      _output.add(NegentropyEncoder.encodeVarint(value));

  void addBound(_Bound bound) {
    _output.add(
      NegentropyEncoder.encodeBound(
        bound.timestamp,
        bound.idPrefix,
        lastTimestamp: _lastTimestamp,
      ),
    );
    _lastTimestamp = bound.timestamp;
  }

  Uint8List toBytes() => _output.toBytes();
}

class _Bound {
  final int timestamp;
  final Uint8List idPrefix;

  _Bound(this.timestamp, this.idPrefix);
}
