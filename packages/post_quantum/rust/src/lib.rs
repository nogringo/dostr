pub mod pq;

use std::slice;

use fips204::traits::{KeyGen, SerDes, Signer, Verifier};
use fips204::{ml_dsa_44, ml_dsa_65, ml_dsa_87};
use hkdf::Hkdf;
use sha2::Sha256;
use zeroize::Zeroize;

// ── Quantum-Secure ML-DSA (FIPS 204) Functions ─────────────────────────
//
// These were CRYSTALS-Dilithium (the round-3 NIST submission). NIST changed the
// algorithm during standardisation, so Dilithium and ML-DSA are not wire-compatible:
// keys and signatures produced by the old code cannot be verified by any FIPS 204
// implementation, and vice versa. Anything published with the previous keys is
// therefore unverifiable by the wider ecosystem, which defeats the point of signing.
//
// `level` selects the parameter set and now takes the ML-DSA numbers — 44, 65 or 87 —
// rather than Dilithium's 2, 3 and 5. The old values are rejected rather than
// remapped, so a caller that was not updated fails loudly instead of silently
// producing keys with different security properties than it asked for.

/// Domain-separation profile for seed-derived keys. Shared with the ML-KEM derivation.
const PQ_PROFILE: &str = "nip-pqc/v1";

/// A BIP-39 seed is always 64 bytes, whatever the mnemonic length.
const SEED_BYTES: usize = 64;

/// Represents a buffer returned to the caller.
/// The caller must free it with `qs_free_buffer`.
#[repr(C)]
pub struct QsBuffer {
    pub data: *mut u8,
    pub len: usize,
}

/// Frees a buffer previously returned by a qs_ function.
///
/// The contents are zeroized before the allocation is released: these buffers carry
/// secret keys, and a freed-but-not-wiped secret is recoverable from a core dump, a
/// swap file, or a later heap read.
///
/// # Safety
/// `buf` must be a QsBuffer previously returned by this library, and must not be
/// freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qs_free_buffer(buf: QsBuffer) {
    if !buf.data.is_null() && buf.len > 0 {
        let mut v = unsafe { Vec::from_raw_parts(buf.data, buf.len, buf.len) };
        v.zeroize();
    }
}

/// Derives the 32-byte ML-DSA key seed (xi) from a BIP-39 seed.
///
/// Domain-separated per algorithm and account so the signing key is a *sibling* of the
/// secp256k1 key rather than a child of it. Deriving from the Nostr private key would
/// be circular: an adversary who recovers it from the published pubkey would repeat the
/// derivation and obtain this key too.
fn derive_dsa_xi(seed: &[u8], level: u32, account: u32) -> Option<[u8; 32]> {
    // A BIP-39 seed is always 64 bytes; requiring exactly that blocks passing a
    // 32-byte secp256k1 private key as the seed.
    if seed.len() != SEED_BYTES {
        return None;
    }
    let info = format!("{PQ_PROFILE}/ml-dsa-{level}/{account}");
    let hk = Hkdf::<Sha256>::new(None, seed);
    let mut xi = [0u8; 32];
    hk.expand(info.as_bytes(), &mut xi).ok()?;
    Some(xi)
}

/// Generates a random ML-DSA keypair.
///
/// `level` selects the parameter set: 44, 65 or 87.
///
/// Prefer `qs_derive_keypair_from_seed` for anything that represents an identity — a
/// randomly generated key cannot be restored from a mnemonic, so losing it loses the
/// identity permanently.
///
/// On success, writes the public key into `out_pk` and the secret key into `out_sk`
/// and returns 1. On failure returns 0.
///
/// # Safety
/// `out_pk` and `out_sk` must be valid, non-aliasing pointers to `QsBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qs_generate_keypair(
    level: u32,
    out_pk: *mut QsBuffer,
    out_sk: *mut QsBuffer,
) -> i32 {
    if out_pk.is_null() || out_sk.is_null() {
        return 0;
    }
    macro_rules! gen {
        ($m:ident) => {{
            match $m::KG::try_keygen() {
                Ok((pk, sk)) => {
                    let mut sk_bytes = sk.into_bytes().to_vec();
                    unsafe {
                        write_buffer(out_pk, pk.into_bytes().to_vec());
                        write_buffer(out_sk, sk_bytes.clone());
                    }
                    sk_bytes.zeroize();
                    1
                }
                Err(_) => 0,
            }
        }};
    }
    match level {
        44 => gen!(ml_dsa_44),
        65 => gen!(ml_dsa_65),
        87 => gen!(ml_dsa_87),
        _ => 0,
    }
}

/// Derives an ML-DSA keypair deterministically from a 64-byte BIP-39 seed.
///
/// One mnemonic therefore restores the signing key, and — because the ML-KEM
/// derivation in `pq.rs` uses the same seed with a different domain string — the
/// encryption key too.
///
/// # Safety
/// `seed_ptr` must be valid for `seed_len` bytes; `out_pk` and `out_sk` must be valid,
/// non-aliasing pointers to `QsBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qs_derive_keypair_from_seed(
    level: u32,
    seed_ptr: *const u8,
    seed_len: usize,
    account: u32,
    out_pk: *mut QsBuffer,
    out_sk: *mut QsBuffer,
) -> i32 {
    if seed_ptr.is_null() || out_pk.is_null() || out_sk.is_null() || seed_len == 0 {
        return 0;
    }
    let seed = unsafe { slice::from_raw_parts(seed_ptr, seed_len) };
    let mut xi = match derive_dsa_xi(seed, level, account) {
        Some(x) => x,
        None => return 0,
    };
    macro_rules! derive {
        ($m:ident) => {{
            let (pk, sk) = $m::KG::keygen_from_seed(&xi);
            let mut sk_bytes = sk.into_bytes().to_vec();
            unsafe {
                write_buffer(out_pk, pk.into_bytes().to_vec());
                write_buffer(out_sk, sk_bytes.clone());
            }
            sk_bytes.zeroize();
            1
        }};
    }
    let rc = match level {
        44 => derive!(ml_dsa_44),
        65 => derive!(ml_dsa_65),
        87 => derive!(ml_dsa_87),
        _ => 0,
    };
    xi.zeroize();
    rc
}

/// Signs a message with an ML-DSA secret key, using an empty FIPS 204 context string.
///
/// `level` selects the parameter set: 44, 65 or 87.
///
/// # Safety
/// All pointers must be valid for their indicated lengths.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qs_sign(
    level: u32,
    sk_ptr: *const u8,
    sk_len: usize,
    msg_ptr: *const u8,
    msg_len: usize,
    out_sig: *mut QsBuffer,
) -> i32 {
    if sk_ptr.is_null() || msg_ptr.is_null() || out_sig.is_null() {
        return 0;
    }
    let sk_bytes = unsafe { slice::from_raw_parts(sk_ptr, sk_len) };
    let msg = unsafe { slice::from_raw_parts(msg_ptr, msg_len) };

    macro_rules! sign {
        ($m:ident) => {{
            let arr: [u8; $m::SK_LEN] = match sk_bytes.try_into() {
                Ok(a) => a,
                Err(_) => return 0,
            };
            let sk = match $m::PrivateKey::try_from_bytes(arr) {
                Ok(k) => k,
                Err(_) => return 0,
            };
            match sk.try_sign(msg, &[]) {
                Ok(sig) => {
                    unsafe { write_buffer(out_sig, sig.to_vec()) };
                    1
                }
                Err(_) => 0,
            }
        }};
    }
    match level {
        44 => sign!(ml_dsa_44),
        65 => sign!(ml_dsa_65),
        87 => sign!(ml_dsa_87),
        _ => 0,
    }
}

/// Verifies an ML-DSA signature against an empty FIPS 204 context string.
///
/// Returns 1 when the signature is valid, 0 otherwise — including for malformed
/// inputs, which are indistinguishable from an invalid signature by design.
///
/// # Safety
/// All pointers must be valid for their indicated lengths.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qs_verify(
    level: u32,
    pk_ptr: *const u8,
    pk_len: usize,
    msg_ptr: *const u8,
    msg_len: usize,
    sig_ptr: *const u8,
    sig_len: usize,
) -> i32 {
    if pk_ptr.is_null() || msg_ptr.is_null() || sig_ptr.is_null() {
        return 0;
    }
    let pk_bytes = unsafe { slice::from_raw_parts(pk_ptr, pk_len) };
    let msg = unsafe { slice::from_raw_parts(msg_ptr, msg_len) };
    let sig_bytes = unsafe { slice::from_raw_parts(sig_ptr, sig_len) };

    macro_rules! verify {
        ($m:ident) => {{
            let pk_arr: [u8; $m::PK_LEN] = match pk_bytes.try_into() {
                Ok(a) => a,
                Err(_) => return 0,
            };
            let sig_arr: [u8; $m::SIG_LEN] = match sig_bytes.try_into() {
                Ok(a) => a,
                Err(_) => return 0,
            };
            let pk = match $m::PublicKey::try_from_bytes(pk_arr) {
                Ok(k) => k,
                Err(_) => return 0,
            };
            i32::from(pk.verify(msg, &sig_arr, &[]))
        }};
    }
    match level {
        44 => verify!(ml_dsa_44),
        65 => verify!(ml_dsa_65),
        87 => verify!(ml_dsa_87),
        _ => 0,
    }
}

/// Helper: move a Vec<u8> into a QsBuffer, leaking the memory for the caller.
///
/// The Vec is converted to a boxed slice first. `qs_free_buffer` reconstructs the
/// allocation with `Vec::from_raw_parts(data, len, len)`, which is undefined behaviour
/// unless capacity equals length — and nothing about `Vec` guarantees that in general.
/// It happens to hold for every value passed here today, so this is a latent trap
/// rather than a live bug: the next contributor to build an output with `push` or
/// `extend` would introduce heap corruption in the free path with no compiler
/// diagnostic. `into_boxed_slice` reallocates to the exact size and removes the trap.
pub(crate) unsafe fn write_buffer(out: *mut QsBuffer, data: Vec<u8>) {
    let data = data.into_boxed_slice();
    let len = data.len();
    let ptr = Box::leak(data).as_mut_ptr();
    unsafe {
        (*out).data = ptr;
        (*out).len = len;
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::Digest;

    #[test]
    fn qs_mldsa_roundtrip_all_levels() {
        for level in [44u32, 65, 87] {
            let seed = [7u8; 64];
            let xi = derive_dsa_xi(&seed, level, 0).unwrap();
            let msg = b"hello quantum world";
            match level {
                44 => {
                    let (pk, sk) = ml_dsa_44::KG::keygen_from_seed(&xi);
                    let sig = sk.try_sign(msg, &[]).unwrap();
                    assert!(pk.verify(msg, &sig, &[]));
                }
                65 => {
                    let (pk, sk) = ml_dsa_65::KG::keygen_from_seed(&xi);
                    let sig = sk.try_sign(msg, &[]).unwrap();
                    assert!(pk.verify(msg, &sig, &[]));
                }
                _ => {
                    let (pk, sk) = ml_dsa_87::KG::keygen_from_seed(&xi);
                    let sig = sk.try_sign(msg, &[]).unwrap();
                    assert!(pk.verify(msg, &sig, &[]));
                }
            }
        }
    }

    #[test]
    fn qs_mldsa_bad_sig_fails() {
        let (pk, sk) = ml_dsa_87::KG::keygen_from_seed(&[3u8; 32]);
        let msg = b"hello quantum world";
        let mut sig = sk.try_sign(msg, &[]).unwrap();
        sig[0] ^= 0xff;
        assert!(!pk.verify(msg, &sig, &[]));
    }

    /// Pinned against `@noble/post-quantum`'s `ml_dsa87`, the implementation the
    /// TypeScript reference uses. The seed is HKDF-derived from bytes 0..64 with
    /// info "nip-pqc/v1/ml-dsa-87/0", exactly as `dsaInfo` does there.
    ///
    /// This is what the previous CRYSTALS-Dilithium code could never satisfy: the
    /// round-3 submission and FIPS 204 are different algorithms, so its keys and
    /// signatures were verifiable only by itself.
    #[test]
    fn qs_mldsa87_matches_fips204_reference_vector() {
        let seed: Vec<u8> = (0u8..64).collect();
        let xi = derive_dsa_xi(&seed, 87, 0).unwrap();
        assert_eq!(
            hex::encode(xi),
            "3d8443c4983bf876911077a0038d5e5084ca107d0d4b6a9438cbf051f79e3917"
        );
        let (pk, _) = ml_dsa_87::KG::keygen_from_seed(&xi);
        let pk_bytes = pk.into_bytes();
        assert_eq!(pk_bytes.len(), ml_dsa_87::PK_LEN);
        assert_eq!(
            hex::encode(Sha256::digest(pk_bytes.as_slice())),
            "dcc0c445e54e2130ded2c1fa04e8aed2fcd80dfaefe2897b41fec827e6cdb609"
        );
    }

    /// A BIP-39 seed is 64 bytes; a secp256k1 private key is 32. Accepting the latter
    /// would make the derivation circular.
    #[test]
    fn qs_seed_derivation_rejects_non_bip39_seeds() {
        assert!(derive_dsa_xi(&[], 87, 0).is_none());
        assert!(derive_dsa_xi(&[0x42; 32], 87, 0).is_none());
        assert!(derive_dsa_xi(&[0x42; 64], 87, 0).is_some());
    }

    /// Same seed, different account or parameter set, different key.
    #[test]
    fn qs_seed_derivation_is_domain_separated() {
        let seed = [9u8; 64];
        let a = derive_dsa_xi(&seed, 87, 0).unwrap();
        assert_ne!(a, derive_dsa_xi(&seed, 87, 1).unwrap());
        assert_ne!(a, derive_dsa_xi(&seed, 65, 0).unwrap());
    }

    /// The Dilithium level numbers must not silently mean something else now.
    #[test]
    fn qs_rejects_legacy_dilithium_levels() {
        unsafe {
            for level in [2u32, 3, 5] {
                let mut pk = QsBuffer {
                    data: std::ptr::null_mut(),
                    len: 0,
                };
                let mut sk = QsBuffer {
                    data: std::ptr::null_mut(),
                    len: 0,
                };
                assert_eq!(qs_generate_keypair(level, &mut pk, &mut sk), 0);
                assert!(pk.data.is_null());
            }
        }
    }

    #[test]
    fn qs_ffi_roundtrip() {
        unsafe {
            let mut pk = QsBuffer {
                data: std::ptr::null_mut(),
                len: 0,
            };
            let mut sk = QsBuffer {
                data: std::ptr::null_mut(),
                len: 0,
            };

            assert_eq!(qs_generate_keypair(87, &mut pk, &mut sk), 1);
            assert!(!pk.data.is_null());
            assert!(!sk.data.is_null());
            assert_eq!(pk.len, ml_dsa_87::PK_LEN);
            assert_eq!(sk.len, ml_dsa_87::SK_LEN);

            let msg = b"test message";
            let mut sig = QsBuffer {
                data: std::ptr::null_mut(),
                len: 0,
            };
            assert_eq!(
                qs_sign(87, sk.data, sk.len, msg.as_ptr(), msg.len(), &mut sig),
                1
            );
            assert_eq!(sig.len, ml_dsa_87::SIG_LEN);

            assert_eq!(
                qs_verify(
                    87,
                    pk.data,
                    pk.len,
                    msg.as_ptr(),
                    msg.len(),
                    sig.data,
                    sig.len
                ),
                1
            );

            let bad_msg = b"wrong message";
            assert_eq!(
                qs_verify(
                    87,
                    pk.data,
                    pk.len,
                    bad_msg.as_ptr(),
                    bad_msg.len(),
                    sig.data,
                    sig.len
                ),
                0
            );

            qs_free_buffer(pk);
            qs_free_buffer(sk);
            qs_free_buffer(sig);
        }
    }

    /// The seed-derived FFI path must agree with direct derivation, and be stable
    /// across calls — that is what makes a mnemonic able to restore the key.
    #[test]
    fn qs_ffi_seed_derivation_is_deterministic() {
        unsafe {
            let seed = [11u8; 64];
            let mut first: Option<Vec<u8>> = None;
            for _ in 0..2 {
                let mut pk = QsBuffer {
                    data: std::ptr::null_mut(),
                    len: 0,
                };
                let mut sk = QsBuffer {
                    data: std::ptr::null_mut(),
                    len: 0,
                };
                assert_eq!(
                    qs_derive_keypair_from_seed(87, seed.as_ptr(), seed.len(), 0, &mut pk, &mut sk),
                    1
                );
                let bytes = std::slice::from_raw_parts(pk.data, pk.len).to_vec();
                match &first {
                    None => first = Some(bytes),
                    Some(f) => assert_eq!(*f, bytes),
                }
                qs_free_buffer(pk);
                qs_free_buffer(sk);
            }
        }
    }
}
