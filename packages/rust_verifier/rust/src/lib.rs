use std::slice;

use hex::decode_to_slice;
use secp256k1::{schnorr::Signature, XOnlyPublicKey, SECP256K1};
use sha2::{Digest, Sha256};

/// Verifies id derivation and the Schnorr signature of a Nostr event from one
/// packed ASCII buffer (id, pubkey, signature) plus the remaining fields needed
/// to recompute the id hash.
///
/// Strings cross as UTF-16 code units with explicit lengths, as Dart holds
/// them, so a NUL or a lone surrogate is hashed as Dart's `json.encode` and
/// `JSON.stringify` write it. `created_at` and `kind` are hashed exactly as
/// Dart's `int` holds them.
///
/// # Safety
/// `packed` must point to exactly `packed_len` (256) readable bytes, and `text`
/// to `text_len` code units: the content (its first `content_len` units)
/// followed by every tag item. `tag_sizes` must hold `tags_count` item counts,
/// and `tag_item_lengths` the length in code units of each tag item. Either may
/// be null when it would be empty.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn verify_nostr_event_packed(
    packed: *const u8,
    packed_len: usize,
    created_at: i64,
    kind: i64,
    text: *const u16,
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
    let (event_id_hex, rest) = bytes.split_at(64);
    let (pub_key_hex, signature_hex) = rest.split_at(64);

    let mut event_id = [0u8; 32];
    let mut pub_key = [0u8; 32];
    let mut signature = [0u8; 64];
    if !decode_lowercase_hex(event_id_hex, &mut event_id)
        || !decode_lowercase_hex(pub_key_hex, &mut pub_key)
        || !decode_lowercase_hex(signature_hex, &mut signature)
    {
        return 0;
    }
    let Ok(pub_key_str) = std::str::from_utf8(pub_key_hex) else {
        return 0;
    };

    let (content, tag_items) =
        unsafe { slice::from_raw_parts(text, text_len) }.split_at(content_len);
    let Some(tags) = (unsafe { parse_tags(tag_items, tag_sizes, tag_item_lengths, tags_count) })
    else {
        return 0;
    };

    if compute_event_id(pub_key_str, created_at, kind, &tags, content) != event_id {
        return 0;
    }

    i32::from(verify_schnorr(pub_key, &event_id, signature))
}

/// Splits `items`, every tag item's UTF-16 code units concatenated in order,
/// back into tags. `tag_sizes` holds the item count of each tag and
/// `tag_item_lengths` the length of each item. Returns `None` on a null pointer
/// or lengths that do not cover `items` exactly, which callers treat as a
/// verification failure.
///
/// # Safety
/// `tag_sizes` must point to `tags_count` `u32`s, and `tag_item_lengths` to as
/// many `u32`s as `tag_sizes` adds up to.
unsafe fn parse_tags(
    items: &[u16],
    tag_sizes: *const u32,
    tag_item_lengths: *const u32,
    tags_count: u32,
) -> Option<Vec<Vec<&[u16]>>> {
    let sizes = unsafe { slice_or_empty(tag_sizes, tags_count as usize) }?;
    let item_count = sizes.iter().map(|&size| size as usize).sum();
    let mut lengths = unsafe { slice_or_empty(tag_item_lengths, item_count) }?.iter();

    let mut rest = items;
    let mut tags = Vec::with_capacity(sizes.len());
    for &size in sizes {
        let mut tag = Vec::with_capacity(size as usize);
        for _ in 0..size {
            let (item, tail) = rest.split_at_checked(*lengths.next()? as usize)?;
            tag.push(item);
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

/// Decodes `hex` into `out`, refusing uppercase digits as NIP-01 does.
fn decode_lowercase_hex(hex: &[u8], out: &mut [u8]) -> bool {
    hex.iter()
        .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'))
        && decode_to_slice(hex, out).is_ok()
}

fn verify_schnorr(pub_key: [u8; 32], message: &[u8; 32], signature: [u8; 64]) -> bool {
    let Ok(pub_key) = XOnlyPublicKey::from_byte_array(pub_key) else {
        return false;
    };
    SECP256K1
        .verify_schnorr(&Signature::from_byte_array(signature), message, &pub_key)
        .is_ok()
}

/// Appends JSON string contents with the escapes of Dart's `json.encode`, which
/// `JSON.stringify` shares: a lone surrogate becomes `\udxxx`.
fn push_json_escaped(output: &mut String, value: &[u16]) {
    for unit in char::decode_utf16(value.iter().copied()) {
        match unit {
            Ok('"') => output.push_str("\\\""),
            Ok('\\') => output.push_str("\\\\"),
            Ok('\u{08}') => output.push_str("\\b"),
            Ok('\u{0c}') => output.push_str("\\f"),
            Ok('\n') => output.push_str("\\n"),
            Ok('\r') => output.push_str("\\r"),
            Ok('\t') => output.push_str("\\t"),
            Ok(c @ '\u{00}'..='\u{1f}') => push_unicode_escape(output, c as u16),
            Ok(c) => output.push(c),
            Err(error) => push_unicode_escape(output, error.unpaired_surrogate()),
        }
    }
}

fn push_unicode_escape(output: &mut String, unit: u16) {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    output.push_str("\\u");
    for shift in [12, 8, 4, 0] {
        output.push(HEX[usize::from((unit >> shift) & 0xf)] as char);
    }
}

fn compute_event_id(
    pubkey: &str,
    created_at: i64,
    kind: i64,
    tags: &[Vec<&[u16]>],
    content: &[u16],
) -> [u8; 32] {
    let text_len = content.len()
        + tags
            .iter()
            .flatten()
            .map(|item| item.len() + 3)
            .sum::<usize>();
    let mut serialized_event = String::with_capacity(128 + text_len);
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

    let mut event_id = [0u8; 32];
    event_id.copy_from_slice(Sha256::digest(serialized_event.as_bytes()).as_slice());
    event_id
}

// ── Tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use std::ptr::null;

    use super::*;

    const PUBKEY: &str = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";

    // A kind 1 that another client signed, from bip340ExternalEvents.
    const NOTE_ID: &str = "f96a38174fce32765cec1778fdabd4ff4b168b0fe8c222593309bfe1383ce0c4";
    const NOTE_PUBKEY: &str = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
    const NOTE_SIG: &str = "1b87de9f4e6329c0580804b1f412e3e533906f7122092f13778064329cdb4e9d8a89391a7121c3326de6a508afc22b62908e34d0284e4f0b5ba7aeb17ff62e8f";
    const NOTE_CREATED_AT: i64 = 1788049179;
    const NOTE_CONTENT: &str = "Remember this?\n\nhttps://www.youtube.com/watch?v=aA-jiiepOrE";

    fn utf16(value: &str) -> Vec<u16> {
        value.encode_utf16().collect()
    }

    fn bytes<const N: usize>(hex: &str) -> [u8; N] {
        let mut bytes = [0u8; N];
        decode_to_slice(hex, &mut bytes).unwrap();
        bytes
    }

    fn event_id_of(tags: &[Vec<&str>], content: &str) -> String {
        let tags: Vec<Vec<Vec<u16>>> = tags
            .iter()
            .map(|tag| tag.iter().map(|item| utf16(item)).collect())
            .collect();
        let tags: Vec<Vec<&[u16]>> = tags
            .iter()
            .map(|tag| tag.iter().map(Vec::as_slice).collect())
            .collect();
        hex::encode(compute_event_id(
            PUBKEY,
            1726215220,
            1,
            &tags,
            &utf16(content),
        ))
    }

    fn verify_note(id: &str, pubkey: &str, sig: &str, content: &str) -> i32 {
        let packed = [id, pubkey, sig].concat();
        let content = utf16(content);
        unsafe {
            verify_nostr_event_packed(
                packed.as_ptr(),
                packed.len(),
                NOTE_CREATED_AT,
                1,
                content.as_ptr(),
                content.len(),
                content.len(),
                null(),
                null(),
                0,
            )
        }
    }

    fn strings(tags: Option<Vec<Vec<&[u16]>>>) -> Option<Vec<Vec<String>>> {
        tags.map(|tags| {
            tags.iter()
                .map(|tag| {
                    tag.iter()
                        .map(|item| String::from_utf16_lossy(item))
                        .collect()
                })
                .collect()
        })
    }

    #[test]
    fn schnorr_signature_test_valid() {
        let event_id = bytes("a47c525970d21575c67e6f1e47674f1b82fc7edabb098fac4be21bb05425b389");
        let signature = bytes("b03ddc4930776698d39caa3df0cd887558ceea281eb9e2524daaba324906b2e3efc06f2f65a7fbba95c0b3ce9817df81f53d2d8da0124028446b0cc3a59ae6d9");
        assert!(verify_schnorr(bytes(PUBKEY), &event_id, signature));
    }

    #[test]
    fn schnorr_signature_test_invalid() {
        let event_id = bytes("a47c525970d21575c67e6f1e47674f1b82fc7edabb098fac4be21bb05425b389");
        let signature = bytes("a03ddc4930776698d39caa3df0cd887558ceea281eb9e2524daaba324906b2e3efc06f2f65a7fbba95c0b3ce9817df81f53d2d8da0124028446b0cc3a59ae6d9");
        assert!(!verify_schnorr(bytes(PUBKEY), &event_id, signature));
    }

    #[test]
    fn hash_event_data_valid() {
        assert_eq!(
            event_id_of(&[], "hello world"),
            "2bd7b2af40868949001713ffdcf95e1b1659dbbabe659ef9299d0fe11e31421d"
        );
    }

    #[test]
    fn hash_event_data_invalid() {
        assert_ne!(
            event_id_of(&[], "invalid"),
            "2bd7b2af40868949001713ffdcf95e1b1659dbbabe659ef9299d0fe11e31421d"
        );
    }

    #[test]
    fn hash_event_data_escapes_control_characters_in_content_and_tags() {
        for code in 0..0x20u8 {
            let value = format!("before{}after", char::from(code));
            for (tags, content) in [
                (vec![], value.as_str()),
                (vec![vec!["t", value.as_str()]], ""),
            ] {
                let serialized = serde_json::to_vec(&serde_json::json!([
                    0,
                    PUBKEY,
                    1726215220u64,
                    1,
                    tags,
                    content
                ]))
                .unwrap();
                assert_eq!(
                    event_id_of(&tags, content),
                    hex::encode(Sha256::digest(serialized)),
                    "control character {code:#04x}, tags: {tags:?}"
                );
            }
        }
    }

    // Expected values from JSON.stringify, which Dart's json.encode matches.
    #[test]
    fn push_json_escaped_writes_lone_surrogates_as_escapes() {
        for (units, expected) in [
            (&[0xd800][..], r"\ud800"),
            (&[0xdfff], r"\udfff"),
            (&[0xdf0d, 0xd83c], r"\udf0d\ud83c"),
            (&[0xd800, 0xd83c, 0xdf0d], "\\ud800🌍"),
            (&[0xd83c, 0xdf0d], "🌍"),
        ] {
            let mut output = String::new();
            push_json_escaped(&mut output, units);
            assert_eq!(output, expected, "code units {units:04x?}");
        }
    }

    #[test]
    fn parse_tags_splits_items_by_code_unit_length() {
        let items = utf16("e\0xp日本🌍");
        let tags = unsafe { parse_tags(&items, [2, 0, 1].as_ptr(), [1, 2, 5].as_ptr(), 3) };
        assert_eq!(
            strings(tags),
            Some(vec![
                vec!["e".to_owned(), "\0x".to_owned()],
                vec![],
                vec!["p日本🌍".to_owned()],
            ])
        );
    }

    #[test]
    fn parse_tags_rejects_lengths_that_do_not_cover_items() {
        let items = utf16("eabc");
        for lengths in [[1, 2], [1, 4]] {
            let tags = unsafe { parse_tags(&items, [2].as_ptr(), lengths.as_ptr(), 1) };
            assert_eq!(tags, None, "item lengths {lengths:?}");
        }
    }

    #[test]
    fn verify_nostr_event_packed_accepts_a_note_another_client_signed() {
        assert_eq!(verify_note(NOTE_ID, NOTE_PUBKEY, NOTE_SIG, NOTE_CONTENT), 1);
    }

    #[test]
    fn verify_nostr_event_packed_rejects_changed_content() {
        assert_eq!(
            verify_note(NOTE_ID, NOTE_PUBKEY, NOTE_SIG, "Remember that?"),
            0
        );
    }

    #[test]
    fn verify_nostr_event_packed_rejects_id_mismatch() {
        let wrong_id = "0".repeat(64);
        assert_eq!(
            verify_note(&wrong_id, NOTE_PUBKEY, NOTE_SIG, NOTE_CONTENT),
            0
        );
    }

    #[test]
    fn verify_nostr_event_packed_rejects_uppercase_hex() {
        let upper = str::to_uppercase;
        for (id, pubkey, sig) in [
            (upper(NOTE_ID), NOTE_PUBKEY.to_owned(), NOTE_SIG.to_owned()),
            (NOTE_ID.to_owned(), upper(NOTE_PUBKEY), NOTE_SIG.to_owned()),
            (NOTE_ID.to_owned(), NOTE_PUBKEY.to_owned(), upper(NOTE_SIG)),
        ] {
            assert_eq!(verify_note(&id, &pubkey, &sig, NOTE_CONTENT), 0);
        }
    }

    #[test]
    fn verify_nostr_event_packed_rejects_wrong_packed_length() {
        let content = utf16("hello world");
        let rc = unsafe {
            verify_nostr_event_packed(
                [0u8; 10].as_ptr(),
                10,
                0,
                1,
                content.as_ptr(),
                content.len(),
                content.len(),
                null(),
                null(),
                0,
            )
        };
        assert_eq!(rc, 0);
    }

    #[test]
    fn verify_nostr_event_packed_rejects_content_longer_than_text() {
        let packed = [b'0'; 256];
        let content = utf16("hello world");
        let rc = unsafe {
            verify_nostr_event_packed(
                packed.as_ptr(),
                packed.len(),
                0,
                1,
                content.as_ptr(),
                content.len(),
                content.len() + 1,
                null(),
                null(),
                0,
            )
        };
        assert_eq!(rc, 0);
    }
}
