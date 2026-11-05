use std::ffi::{c_char, CStr};
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
/// # Safety
/// `packed` must point to exactly `packed_len` (256) readable bytes. `tags_data`/
/// `tags_lengths` must describe `tags_count` valid C strings, and `content` must
/// be a valid null-terminated C string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn verify_nostr_event_packed(
    packed: *const u8,
    packed_len: usize,
    created_at: u64,
    kind: u32,
    tags_data: *const *const c_char,
    tags_lengths: *const u32,
    tags_count: u32,
    content: *const c_char,
) -> i32 {
    const PACKED_LEN: usize = 64 + 64 + 128;
    if packed.is_null() || packed_len != PACKED_LEN || content.is_null() {
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
    let content_str = match unsafe { CStr::from_ptr(content) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let tags = match unsafe { parse_tags(tags_data, tags_lengths, tags_count) } {
        Some(t) => t,
        None => return 0,
    };

    let calc_id =
        hash_event_data_internal(pub_key_str, created_at, kind as u16, &tags, content_str);
    if calc_id.as_bytes() != event_id_hex {
        return 0;
    }

    if verify_schnorr_signature_bytes(pub_key_hex, event_id_hex, signature_hex) {
        1
    } else {
        0
    }
}

/// Parses the flat tags array passed across FFI back into `Vec<Vec<String>>`.
/// `tags_lengths` holds the item count of each tag; `tags_data` holds all tag
/// items concatenated in order. Returns `None` on any null pointer or invalid
/// UTF-8, which callers treat as a verification failure.
///
/// # Safety
/// `tags_data` must point to a flat array covering the sum of `tags_lengths`
/// valid C strings, and `tags_lengths` to `tags_count` `u32`s.
unsafe fn parse_tags(
    tags_data: *const *const c_char,
    tags_lengths: *const u32,
    tags_count: u32,
) -> Option<Vec<Vec<String>>> {
    if tags_count == 0 || tags_data.is_null() || tags_lengths.is_null() {
        return Some(Vec::new());
    }

    let lengths = unsafe { slice::from_raw_parts(tags_lengths, tags_count as usize) };
    let mut result: Vec<Vec<String>> = Vec::with_capacity(tags_count as usize);
    let mut offset = 0usize;

    for &len in lengths {
        let mut tag: Vec<String> = Vec::with_capacity(len as usize);
        for i in 0..len as usize {
            let ptr = unsafe { *tags_data.add(offset + i) };
            if ptr.is_null() {
                return None;
            }
            match unsafe { CStr::from_ptr(ptr) }.to_str() {
                Ok(s) => tag.push(s.to_string()),
                Err(_) => return None,
            }
        }
        result.push(tag);
        offset += len as usize;
    }
    Some(result)
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
    created_at: u64,
    kind: u16,
    tags: &[Vec<String>],
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
        let tags: Vec<Vec<String>> = vec![];
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
        let tags: Vec<Vec<String>> = vec![];
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
                (vec![], value.clone()),
                (vec![vec!["t".to_string(), value.clone()]], String::new()),
            ] {
                let serialized = serde_json::to_vec(&serde_json::json!([
                    0, pubkey, 1726215220u64, 1, tags, content
                ]))
                .unwrap();
                let expected = hex::encode(Sha256::digest(serialized));
                assert_eq!(
                    hash_event_data_internal(pubkey, 1726215220, 1, &tags, &content),
                    expected,
                    "control character {code:#04x}, tags: {tags:?}"
                );
            }
        }
    }

    /// Builds a null-terminated C string on the heap, for feeding raw pointer FFI
    /// entry points from safe test code.
    fn cstring(value: &str) -> std::ffi::CString {
        std::ffi::CString::new(value).unwrap()
    }

    #[test]
    fn verify_nostr_event_packed_rejects_wrong_packed_length() {
        let content = cstring("hello world");
        let rc = unsafe {
            verify_nostr_event_packed(
                [0u8; 10].as_ptr(),
                10,
                0,
                1,
                std::ptr::null(),
                std::ptr::null(),
                0,
                content.as_ptr(),
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

        let content = cstring("hello world");
        let rc = unsafe {
            verify_nostr_event_packed(
                packed.as_ptr(),
                packed.len(),
                1726215220,
                1,
                std::ptr::null(),
                std::ptr::null(),
                0,
                content.as_ptr(),
            )
        };
        assert_eq!(rc, 0);
    }
}
