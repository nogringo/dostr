import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Verifies id derivation and the Schnorr signature of a Nostr event from one
/// packed ASCII buffer containing event id (64 bytes), pubkey (64 bytes), and
/// signature (128 bytes), plus the remaining fields needed to recompute the id
/// hash. Replaces the previous
/// `Nip01Utils.isIdValid` (Dart-side JSON re-serialization and re-hashing) with
/// a single native call.
@Native<
  Int32 Function(
    Pointer<Uint8>, // packed
    IntPtr, // packedLength
    Uint64, // createdAt
    Uint32, // kind
    Pointer<Pointer<Utf8>>, // tagsData
    Pointer<Uint32>, // tagsLengths
    Uint32, // tagsCount
    Pointer<Utf8>, // content
  )
>(symbol: 'verify_nostr_event_packed')
external int verifyNostrEventPackedNative(
  Pointer<Uint8> packed,
  int packedLength,
  int createdAt,
  int kind,
  Pointer<Pointer<Utf8>> tagsData,
  Pointer<Uint32> tagsLengths,
  int tagsCount,
  Pointer<Utf8> content,
);
