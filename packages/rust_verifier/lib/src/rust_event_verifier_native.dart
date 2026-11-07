import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:ndk_nip01/hex.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'rust_lib.dart' as rust_lib;

/// An implementation of [EventVerifier] that uses native Rust for event verification.
///
/// This class provides a bridge between Dart and Rust via FFI using native assets,
/// allowing for efficient verification of Nostr events using Rust's performance capabilities.
class RustEventVerifier implements EventVerifier {
  /// Creates a new instance of [RustEventVerifier].
  RustEventVerifier();

  @override
  Future<bool> verify(Nip01Event event) async {
    final signature = event.sig;
    if (signature == null ||
        !isLowercaseHex(event.id, length: 64) ||
        !isLowercaseHex(event.pubKey, length: 64) ||
        !isLowercaseHex(signature, length: 128)) {
      return false;
    }

    // Id derivation and Schnorr verification both happen in one native call.
    // Strings cross as bytes with explicit lengths: as C strings, a NUL would
    // cut what Rust hashes.
    final content = utf8.encode(event.content);
    final tagItems = [
      for (final tag in event.tags)
        for (final item in tag) utf8.encode(item),
    ];
    var textLength = content.length;
    for (final item in tagItems) {
      textLength += item.length;
    }

    const packedLength = 64 + 64 + 128;
    final packed = malloc<Uint8>(packedLength);
    Pointer<Uint8> text = nullptr;
    Pointer<Uint32> tagSizes = nullptr;
    Pointer<Uint32> tagItemLengths = nullptr;

    // Every allocation below must happen inside the try block: if one throws
    // (e.g. native OOM) partway through, prior allocations must still be freed.
    try {
      text = malloc<Uint8>(textLength > 0 ? textLength : 1);
      final textBytes = text.asTypedList(textLength)..setAll(0, content);
      var offset = content.length;
      for (final item in tagItems) {
        textBytes.setAll(offset, item);
        offset += item.length;
      }

      final tagsCount = event.tags.length;
      if (tagsCount > 0) {
        tagSizes = malloc<Uint32>(tagsCount);
        for (var i = 0; i < tagsCount; i++) {
          tagSizes[i] = event.tags[i].length;
        }
      }
      if (tagItems.isNotEmpty) {
        tagItemLengths = malloc<Uint32>(tagItems.length);
        for (var i = 0; i < tagItems.length; i++) {
          tagItemLengths[i] = tagItems[i].length;
        }
      }

      final bytes = packed.asTypedList(packedLength);
      _copyAscii(event.id, bytes, 0);
      _copyAscii(event.pubKey, bytes, 64);
      _copyAscii(signature, bytes, 128);

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
            tagsCount,
          ) ==
          1;
    } finally {
      malloc.free(packed);
      if (text != nullptr) malloc.free(text);
      if (tagSizes != nullptr) malloc.free(tagSizes);
      if (tagItemLengths != nullptr) malloc.free(tagItemLengths);
    }
  }

  static void _copyAscii(String source, List<int> target, int offset) {
    final codeUnits = source.codeUnits;
    for (var index = 0; index < codeUnits.length; index++) {
      target[offset + index] = codeUnits[index];
    }
  }
}
