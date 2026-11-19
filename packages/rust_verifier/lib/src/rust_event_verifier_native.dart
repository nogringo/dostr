import 'dart:ffi';
import 'dart:typed_data';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip01/hex.dart';
import 'package:ffi/ffi.dart';

import 'rust_lib.dart' as rust_lib;

/// An [EventVerifier] that checks the id and the sig in one native Rust call.
class RustEventVerifier implements EventVerifier {
  @override
  Future<bool> verify(Nip01Event event) async {
    final signature = event.sig;
    if (signature == null ||
        !isLowercaseHex(event.id, length: 64) ||
        !isLowercaseHex(event.pubkey, length: 64) ||
        !isLowercaseHex(signature, length: 128)) {
      return false;
    }

    // Id derivation and Schnorr verification both happen in one native call.
    // Strings cross as UTF-16 code units with explicit lengths: as UTF-8, a
    // lone surrogate would turn into U+FFFD, and as C strings a NUL would cut
    // what Rust hashes.
    final content = event.content;
    final tags = event.tags;
    var textLength = content.length;
    var itemCount = 0;
    for (final tag in tags) {
      itemCount += tag.length;
      for (final item in tag) {
        textLength += item.length;
      }
    }

    const packedLength = 64 + 64 + 128;
    final packed = malloc<Uint8>(packedLength);
    Pointer<Uint16> text = nullptr;
    Pointer<Uint32> tagSizes = nullptr;
    Pointer<Uint32> tagItemLengths = nullptr;

    // Every allocation below must happen inside the try block: if one throws
    // (e.g. native OOM) partway through, prior allocations must still be freed.
    try {
      text = malloc<Uint16>(textLength > 0 ? textLength : 1);
      final units = text.asTypedList(textLength);
      _copyCodeUnits(content, units, 0);
      var offset = content.length;

      if (tags.isNotEmpty) tagSizes = malloc<Uint32>(tags.length);
      if (itemCount > 0) tagItemLengths = malloc<Uint32>(itemCount);
      var itemIndex = 0;
      for (var tagIndex = 0; tagIndex < tags.length; tagIndex++) {
        final tag = tags[tagIndex];
        tagSizes[tagIndex] = tag.length;
        for (final item in tag) {
          tagItemLengths[itemIndex++] = item.length;
          _copyCodeUnits(item, units, offset);
          offset += item.length;
        }
      }

      final bytes = packed.asTypedList(packedLength);
      _copyHex(event.id, bytes, 0);
      _copyHex(event.pubkey, bytes, 64);
      _copyHex(signature, bytes, 128);

      return rust_lib.verifyNostrEventPackedNative(
            packed,
            packedLength,
            event.createdAt,
            event.kind,
            text,
            textLength,
            content.length,
            tagSizes,
            tagItemLengths,
            tags.length,
          ) ==
          1;
    } finally {
      malloc.free(packed);
      if (text != nullptr) malloc.free(text);
      if (tagSizes != nullptr) malloc.free(tagSizes);
      if (tagItemLengths != nullptr) malloc.free(tagItemLengths);
    }
  }

  // Typed targets and plain loops: List<int> or codeUnits copy 3x slower in AOT.
  static void _copyCodeUnits(String source, Uint16List target, int offset) {
    for (var index = 0; index < source.length; index++) {
      target[offset + index] = source.codeUnitAt(index);
    }
  }

  static void _copyHex(String source, Uint8List target, int offset) {
    for (var index = 0; index < source.length; index++) {
      target[offset + index] = source.codeUnitAt(index);
    }
  }
}
