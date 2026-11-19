import 'dart:ffi';

/// Verifies the id and the Schnorr signature of a Nostr event in one call.
///
/// [packed] holds the id (64 bytes), the pubkey (64 bytes) and the signature
/// (128 bytes) as lowercase hex. [text] holds the UTF-16 content (its first
/// [contentLength] code units) followed by every tag item. [tagSizes] gives the
/// item count of each tag and [tagItemLengths] the length of each item, in
/// code units.
@Native<
  Int32 Function(
    Pointer<Uint8>, // packed
    IntPtr, // packedLength
    Int64, // createdAt
    Int64, // kind
    Pointer<Uint16>, // text
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
  Pointer<Uint16> text,
  int textLength,
  int contentLength,
  Pointer<Uint32> tagSizes,
  Pointer<Uint32> tagItemLengths,
  int tagsCount,
);
