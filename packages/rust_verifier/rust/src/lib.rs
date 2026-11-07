use std::slice;

use hex::decode_to_slice;
use secp256k1::{schnorr::Signature, XOnlyPublicKey, SECP256K1};
use sha2::{Digest, Sha256};

/// Verifies id derivation and the Schnorr signature of a Nostr event from one
/// packed ASCII buffer (id, pubkey, signature) plus the remaining fields needed
/// to recompute the id hash.
///
/// This replaces the previous split between a Dart-side id check
/// (`Nip01Utils.isIdValid`, which serializes the event to JSON and re-hashes it)
/// and a Rust-side signature-only check: both now happen here, in one call, with
/// only the fixed-size id/pubkey/signature triplet packed into a single buffer.
///
/// Strings cross as UTF-8 bytes with explicit lengths, never as C strings: a NUL
/// would otherwise cut what gets hashed, letting text be appended after signing.
/// `created_at` and `kind` are hashed exactly as Dart's `int` holds them.
///
/// # Safety
/// `packed` must point to exactly `packed_len` (256) readable bytes, and `text` to
/// `text_len` bytes: the content (its first `content_len` bytes) followed by every
/// tag item. `tag_sizes` must hold `tags_count` item counts, and `tag_item_lengths`
/// the byte length of each tag item. Either may be null when it would be empty.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn verify_nostr_event_packed(
    packed: *const u8,
    packed_len: usize,
    created_at: i64,
    kind: i64,
    text: *const u8,
    text_len: usize,
    content_len: usize,
    tag_sizes: *const u32,
    tag_item_lengths: *const u32,
    tags_count: u32,
) -> i32 {
    const PACKED_LEN: usize = 64 + 64 + 128;
    if packed.is_null() || packed_len != PACKED_LEN || text.is_null() || content_len > text_len {
        return 0;
    }
    let bytes = unsafe { slice::from_raw_parts(packed, packed_len) };
    let event_id_hex = &bytes[..64];
    let pub_key_hex = &bytes[64..128];
    let signature_hex = &bytes[128..];

    let pub_key_str = match std::str::from_utf8(pub_key_hex) {
        Ok(s) => s,
        Err(_) => return 0,
    };
    let (content, tag_items) =
        unsafe { slice::from_raw_parts(text, text_len) }.split_at(content_len);
    let content_str = match std::str::from_utf8(content) {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let tags = match unsafe { parse_tags(tag_items, tag_sizes, tag_item_lengths, tags_count) } {
        Some(t) => t,
        None => return 0,
    };

    let calc_id = hash_event_data_internal(pub_key_str, created_at, kind, &tags, content_str);
    if calc_id.as_bytes() != event_id_hex {
        return 0;
    }

    if verify_schnorr_signature_bytes(pub_key_hex, event_id_hex, signature_hex) {
        1
    } else {
        0
    }
}

/// Splits `items`, every tag item's UTF-8 bytes concatenated in order, back into
/// tags. `tag_sizes` holds the item count of each tag and `tag_item_lengths` the
/// byte length of each item. Returns `None` on a null pointer, invalid UTF-8, or
/// lengths that do not cover `items` exactly, which callers treat as a
/// verification failure.
///
/// # Safety
/// `tag_sizes` must point to `tags_count` `u32`s, and `tag_item_lengths` to as
/// many `u32`s as `tag_sizes` adds up to.
unsafe fn parse_tags(
    items: &[u8],
    tag_sizes: *const u32,
    tag_item_lengths: *const u32,
    tags_count: u32,
) -> Option<Vec<Vec<&str>>> {
    let sizes = unsafe { slice_or_empty(tag_sizes, tags_count as usize) }?;
    let item_count = sizes.iter().map(|&size| size as usize).sum();
    let mut lengths = unsafe { slice_or_empty(tag_item_lengths, item_count) }?.iter();

    let mut rest = items;
    let mut tags = Vec::with_capacity(sizes.len());
    for &size in sizes {
        let mut tag = Vec::with_capacity(size as usize);
        for _ in 0..size {
            let (item, tail) = rest.split_at_checked(*lengths.next()? as usize)?;
            tag.push(std::str::from_utf8(item).ok()?);
            rest = tail;
        }
        tags.push(tag);
    }
    rest.is_empty().then_some(tags)
}

/// # Safety
/// Unless `len` is 0, `ptr` must point to `len` readable `u32`s.
unsafe fn slice_or_empty<'a>(ptr: *const u32, len: usize) -> Option<&'a [u32]> {
    if len == 0 {
        Some(&[])
    } else if ptr.is_null() {
        None
    } else {
        Some(unsafe { slice::from_raw_parts(ptr, len) })
    }
}

fn verify_schnorr_signature_bytes(
    pub_key_hex: &[u8],
    event_id_hex: &[u8],
    signature_hex: &[u8],
) -> bool {
    if pub_key_hex.len() != 64 || event_id_hex.len() != 64 || signature_hex.len() != 128 {
        return false;
    }

    let mut pub_key_array = [0u8; 32];
    let mut event_id_array = [0u8; 32];
    let mut signature_array = [0u8; 64];
    if decode_to_slice(pub_key_hex, &mut pub_key_array).is_err()
        || decode_to_slice(event_id_hex, &mut event_id_array).is_err()
        || decode_to_slice(signature_hex, &mut signature_array).is_err()
    {
        return false;
    }

    let pubkey = match XOnlyPublicKey::from_byte_array(pub_key_array) {
        Ok(key) => key,
        Err(_) => return false,
    };

    let signature = Signature::from_byte_array(signature_array);

    SECP256K1
        .verify_schnorr(&signature, &event_id_array, &pubkey)
        .is_ok()
}

/// Appends JSON string contents using the same escapes as Dart's json.encode.
fn push_json_escaped(output: &mut String, value: &str) {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    for c in value.chars() {
        match c {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\u{08}' => output.push_str("\\b"),
            '\u{0c}' => output.push_str("\\f"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            '\u{00}'..='\u{1f}' => {
                output.push_str("\\u00");
                output.push(HEX[(c as usize) >> 4] as char);
                output.push(HEX[(c as usize) & 0x0f] as char);
            }
            _ => output.push(c),
        }
    }
}

fn hash_event_data_internal(
    pubkey: &str,
    created_at: i64,
    kind: i64,
    tags: &[Vec<&str>],
    content: &str,
) -> String {
    let mut serialized_event = String::with_capacity(256);
    serialized_event.push_str("[0,\"");
    serialized_event.push_str(pubkey);
    serialized_event.push_str("\",");
    serialized_event.push_str(&created_at.to_string());
    serialized_event.push(',');
    serialized_event.push_str(&kind.to_string());
    serialized_event.push_str(",[");

    for (i, tag) in tags.iter().enumerate() {
        if i > 0 {
            serialized_event.push(',');
        }
        serialized_event.push('[');
        for (j, item) in tag.iter().enumerate() {
            if j > 0 {
                serialized_event.push(',');
            }
            serialized_event.push('"');
            push_json_escaped(&mut serialized_event, item);
            serialized_event.push('"');
        }
        serialized_event.push(']');
    }

    serialized_event.push_str("],\"");
    push_json_escaped(&mut serialized_event, content);
    serialized_event.push_str("\"]");

    let mut hasher = Sha256::new();
    hasher.update(serialized_event.as_bytes());
    let result = hasher.finalize();

    hex::encode(result)
}

// ── Tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn schnorr_signature_test_valid() {
        let pub_key_hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
        let event_id = "a47c525970d21575c67e6f1e47674f1b82fc7edabb098fac4be21bb05425b389";
        let signature_hex = "b03ddc4930776698d39caa3df0cd887558ceea281eb9e2524daaba324906b2e3efc06f2f65a7fbba95c0b3ce9817df81f53d2d8da0124028446b0cc3a59ae6d9";
        assert!(verify_schnorr_signature_bytes(
            pub_key_hex.as_bytes(),
            event_id.as_bytes(),
            signature_hex.as_bytes()
        ));
    }

    #[test]
    fn schnorr_signature_test_invalid() {
        let pub_key_hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
        let event_id = "a47c525970d21575c67e6f1e47674f1b82fc7edabb098fac4be21bb05425b389";
        let signature_hex = "a03ddc4930776698d39caa3df0cd887558ceea281eb9e2524daaba324906b2e3efc06f2f65a7fbba95c0b3ce9817df81f53d2d8da0124028446b0cc3a59ae6d9";
        assert!(!verify_schnorr_signature_bytes(
            pub_key_hex.as_bytes(),
            event_id.as_bytes(),
            signature_hex.as_bytes()
        ));
    }

    #[test]
    fn hash_event_data_valid() {
        let valid_id = "2bd7b2af40868949001713ffdcf95e1b1659dbbabe659ef9299d0fe11e31421d";
        let pubkey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
        let created_at = 1726215220;
        let kind = 1;
        let tags: Vec<Vec<&str>> = vec![];
        let content = "hello world";
        assert_eq!(
            hash_event_data_internal(pubkey, created_at, kind, &tags, content),
            valid_id
        );
    }

    #[test]
    fn hash_event_data_invalid() {
        let valid_id = "2bd7b2af40868949001713ffdcf95e1b1659dbbabe659ef9299d0fe11e31421d";
        let pubkey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
        let created_at = 1726215220;
        let kind = 1;
        let tags: Vec<Vec<&str>> = vec![];
        let content = "invalid";
        assert_ne!(
            hash_event_data_internal(pubkey, created_at, kind, &tags, content),
            valid_id
        );
    }

    #[test]
    fn hash_event_data_escapes_control_characters_in_content_and_tags() {
        let pubkey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
        for code in 0..0x20u8 {
            let value = format!("before{}after", char::from(code));
            for (tags, content) in [
                (vec![], value.as_str()),
                (vec![vec!["t", value.as_str()]], ""),
            ] {
                let serialized = serde_json::to_vec(&serde_json::json!([
                    0, pubkey, 1726215220u64, 1, tags, content
                ]))
                .unwrap();
                let expected = hex::encode(Sha256::digest(serialized));
                assert_eq!(
                    hash_event_data_internal(pubkey, 1726215220, 1, &tags, content),
                    expected,
                    "control character {code:#04x}, tags: {tags:?}"
                );
            }
        }
    }

    #[test]
    fn parse_tags_splits_items_by_byte_length() {
        let items = "e\0xp日本".as_bytes();
        let tags = unsafe { parse_tags(items, [2, 0, 1].as_ptr(), [1, 2, 7].as_ptr(), 3) };
        assert_eq!(tags, Some(vec![vec!["e", "\0x"], vec![], vec!["p日本"]]));
    }

    #[test]
    fn parse_tags_rejects_lengths_that_do_not_cover_items() {
        let items = b"eabc";
        for lengths in [[1, 2], [1, 4]] {
            let tags = unsafe { parse_tags(items, [2].as_ptr(), lengths.as_ptr(), 1) };
            assert_eq!(tags, None, "item lengths {lengths:?}");
        }
    }

    #[test]
    fn parse_tags_rejects_a_value_cut_inside_a_utf8_character() {
        let items = "日本".as_bytes();
        let tags = unsafe { parse_tags(items, [2].as_ptr(), [1, 5].as_ptr(), 1) };
        assert_eq!(tags, None);
    }

    #[test]
    fn verify_nostr_event_packed_rejects_wrong_packed_length() {
        let content = b"hello world";
        let rc = unsafe {
            verify_nostr_event_packed(
                [0u8; 10].as_ptr(),
                10,
                0,
                1,
                content.as_ptr(),
                content.len(),
                content.len(),
                std::ptr::null(),
                std::ptr::null(),
                0,
            )
        };
        assert_eq!(rc, 0);
    }

    #[test]
    fn verify_nostr_event_packed_rejects_content_longer_than_text() {
        let packed = [b'0'; 256];
        let content = b"hello world";
        let rc = unsafe {
            verify_nostr_event_packed(
                packed.as_ptr(),
                packed.len(),
                0,
                1,
                content.as_ptr(),
                content.len(),
                content.len() + 1,
                std::ptr::null(),
                std::ptr::null(),
                0,
            )
        };
        assert_eq!(rc, 0);
    }

    #[test]
    fn verify_nostr_event_packed_rejects_id_mismatch() {
        let pubkey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
        let wrong_id = "0000000000000000000000000000000000000000000000000000000000000000";
        let signature = "b03ddc4930776698d39caa3df0cd887558ceea281eb9e2524daaba324906b2e3efc06f2f65a7fbba95c0b3ce9817df81f53d2d8da0124028446b0cc3a59ae6d9";
        let mut packed = Vec::with_capacity(256);
        packed.extend_from_slice(&wrong_id.as_bytes()[..64]);
        packed.extend_from_slice(pubkey.as_bytes());
        packed.extend_from_slice(signature.as_bytes());

        let content = b"hello world";
        let rc = unsafe {
            verify_nostr_event_packed(
                packed.as_ptr(),
                packed.len(),
                1726215220,
                1,
                content.as_ptr(),
                content.len(),
                content.len(),
                std::ptr::null(),
                std::ptr::null(),
                0,
            )
        };
        assert_eq!(rc, 0);
    }
}
