import 'dart:ffi';

/// Verifies id derivation and the Schnorr signature of a Nostr event from one
/// packed ASCII buffer containing event id (64 bytes), pubkey (64 bytes), and
/// signature (128 bytes), plus the remaining fields needed to recompute the id
/// hash. Replaces the previous
/// `Nip01Event.hasValidId` (Dart-side JSON re-serialization and re-hashing) with
/// a single native call.
///
/// [text] holds the UTF-8 content (its first [contentLength] bytes) followed by
/// every tag item. [tagSizes] gives the item count of each tag and
/// [tagItemLengths] the byte length of each item.
@Native<
  Int32 Function(
    Pointer<Uint8>, // packed
    IntPtr, // packedLength
    Int64, // createdAt
    Int64, // kind
    Pointer<Uint8>, // text
    IntPtr, // textLength
    IntPtr, // contentLength
    Pointer<Uint32>, // tagSizes
    Pointer<Uint32>, // tagItemLengths
    Uint32, // tagsCount
  )
>(symbol: 'verify_nostr_event_packed')
external int verifyNostrEventPackedNative(
  Pointer<Uint8> packed,
  int packedLength,
  int createdAt,
  int kind,
  Pointer<Uint8> text,
  int textLength,
  int contentLength,
  Pointer<Uint32> tagSizes,
  Pointer<Uint32> tagItemLengths,
  int tagsCount,
);
