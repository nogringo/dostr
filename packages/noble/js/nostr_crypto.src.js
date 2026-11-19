// Everything runs on @noble, without crypto.subtle, which a page served over
// plain http does not have.
import { cbc } from '@noble/ciphers/aes.js';
import { chacha20 } from '@noble/ciphers/chacha.js';
import { equalBytes } from '@noble/ciphers/utils.js';
import { schnorr, secp256k1 } from '@noble/curves/secp256k1.js';
import { expand, extract } from '@noble/hashes/hkdf.js';
import { hmac } from '@noble/hashes/hmac.js';
import { sha256 } from '@noble/hashes/sha2.js';
import {
  bytesToHex,
  concatBytes,
  hexToBytes,
  randomBytes,
} from '@noble/hashes/utils.js';

const utf8Encoder = new TextEncoder();
const utf8Decoder = new TextDecoder('utf-8', { fatal: true });

/**
 * Whether a BIP-340 signature of a 32-byte hash is valid
 * @param {string} signatureHex
 * @param {string} hashHex
 * @param {string} publicKeyHex x-only
 * @returns {boolean}
 */
function verifySignature(signatureHex, hashHex, publicKeyHex) {
  try {
    return schnorr.verify(
      hexToBytes(signatureHex),
      hexToBytes(hashHex),
      hexToBytes(publicKeyHex),
    );
  } catch {
    return false;
  }
}

/**
 * The BIP-340 signature of a 32-byte hash, with fresh auxiliary randomness
 * @param {string} privateKeyHex
 * @param {string} hashHex
 * @returns {string}
 */
function signEvent(privateKeyHex, hashHex) {
  return bytesToHex(schnorr.sign(hexToBytes(hashHex), hexToBytes(privateKeyHex)));
}

/**
 * The x-only public key of a private key, which throws when it is not one
 * @param {string} privateKeyHex
 * @returns {string}
 */
function getPublicKey(privateKeyHex) {
  return bytesToHex(schnorr.getPublicKey(hexToBytes(privateKeyHex)));
}

function bytesToBase64(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

const BASE64_ALPHABET =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

// What Dart's base64.decode reads, as dostr_nip44 does: both alphabets, `=`
// or `%3D` padding, no whitespace, and no stray bits before the padding.
function base64ToBytes(base64) {
  const encoded = base64
    .replace(/%3d/gi, '=')
    .replace(/-/g, '+')
    .replace(/_/g, '/');
  const padding = /^[A-Za-z0-9+/]*(={0,2})$/.exec(encoded)?.[1].length;
  if (padding === undefined || encoded.length % 4 !== 0) {
    throw new Error('Invalid base64');
  }
  if (padding > 0) {
    const last = BASE64_ALPHABET.indexOf(encoded[encoded.length - padding - 1]);
    if (last & (padding === 2 ? 0x0f : 0x03)) throw new Error('Invalid base64');
  }
  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// The x of the ECDH point. An x-only public key is taken as its even point.
function sharedX(privateKeyHex, publicKeyHex) {
  const publicKey = hexToBytes(
    publicKeyHex.length === 64 ? '02' + publicKeyHex : publicKeyHex,
  );
  return secp256k1
    .getSharedSecret(hexToBytes(privateKeyHex), publicKey, true)
    .subarray(1, 33);
}

// ---------------------------------------------------------------------------
// NIP-04
// ---------------------------------------------------------------------------

/**
 * @param {string} privateKeyHex
 * @param {string} publicKeyHex
 * @param {string} plaintext
 * @returns {string}
 */
function nip04Encrypt(privateKeyHex, publicKeyHex, plaintext) {
  const key = sharedX(privateKeyHex, publicKeyHex);
  const iv = randomBytes(16);
  const ciphertext = cbc(key, iv).encrypt(utf8Encoder.encode(plaintext));
  return `${bytesToBase64(ciphertext)}?iv=${bytesToBase64(iv)}`;
}

/**
 * @param {string} privateKeyHex
 * @param {string} publicKeyHex
 * @param {string} ciphertext
 * @returns {string}
 */
function nip04Decrypt(privateKeyHex, publicKeyHex, ciphertext) {
  const parts = ciphertext.split('?iv=');
  if (parts.length !== 2) {
    throw new Error('Not a NIP-04 payload: it needs one ?iv=');
  }
  const [dataB64, ivB64] = parts;

  const key = sharedX(privateKeyHex, publicKeyHex);
  const plaintext = cbc(key, base64ToBytes(ivB64)).decrypt(base64ToBytes(dataB64));
  return utf8Decoder.decode(plaintext);
}

// ---------------------------------------------------------------------------
// NIP-44
// ---------------------------------------------------------------------------

const MAX_PLAINTEXT_LENGTH = 0xffffffff;
// nostr-protocol/nips#1907: from this length on, a 6-byte prefix
const EXTENDED_PREFIX_THRESHOLD = 0x10000;

function calcPaddedLen(unpaddedLen) {
  if (unpaddedLen <= 32) return 32;
  const nextPower = 2 ** ((unpaddedLen - 1).toString(2).length);
  const chunk = nextPower <= 256 ? 32 : nextPower / 8;
  return chunk * Math.ceil(unpaddedLen / chunk);
}

function pad(plaintext) {
  const unpaddedLen = plaintext.length;
  if (unpaddedLen < 1 || unpaddedLen > MAX_PLAINTEXT_LENGTH) throw new Error('Invalid plaintext length');
  const extended = unpaddedLen >= EXTENDED_PREFIX_THRESHOLD;
  const prefixLen = extended ? 6 : 2;
  const padded = new Uint8Array(prefixLen + calcPaddedLen(unpaddedLen));
  const view = new DataView(padded.buffer);
  if (extended) {
    view.setUint32(2, unpaddedLen);
  } else {
    view.setUint16(0, unpaddedLen);
  }
  padded.set(plaintext, prefixLen);
  return padded;
}

function unpad(padded) {
  const view = new DataView(padded.buffer, padded.byteOffset, padded.byteLength);
  const extended = view.getUint16(0) === 0;
  const prefixLen = extended ? 6 : 2;
  const unpaddedLen = extended ? view.getUint32(2) : view.getUint16(0);
  if ((extended && unpaddedLen < EXTENDED_PREFIX_THRESHOLD) ||
      padded.length !== prefixLen + calcPaddedLen(unpaddedLen)) {
    throw new Error('Invalid padding');
  }
  return padded.subarray(prefixLen, prefixLen + unpaddedLen);
}

function messageKeys(conversationKey, nonce) {
  const keys = expand(sha256, conversationKey, nonce, 76);
  return {
    chachaKey: keys.subarray(0, 32),
    chachaNonce: keys.subarray(32, 44),
    hmacKey: keys.subarray(44, 76),
  };
}

/**
 * The NIP-44 conversation key between two peers, the same on both sides
 * @param {string} privateKeyHex
 * @param {string} publicKeyHex
 * @returns {Uint8Array}
 */
function nip44ConversationKey(privateKeyHex, publicKeyHex) {
  return extract(
    sha256,
    sharedX(privateKeyHex, publicKeyHex),
    utf8Encoder.encode('nip44-v2'),
  );
}

/**
 * @param {Uint8Array} conversationKey
 * @param {string} plaintext
 * @param {Uint8Array} [nonce] for test vectors only
 * @returns {string}
 */
function nip44Encrypt(conversationKey, plaintext, nonce = randomBytes(32)) {
  const { chachaKey, chachaNonce, hmacKey } = messageKeys(conversationKey, nonce);
  const ciphertext = chacha20(chachaKey, chachaNonce, pad(utf8Encoder.encode(plaintext)));
  const mac = hmac(sha256, hmacKey, concatBytes(nonce, ciphertext));
  return bytesToBase64(concatBytes(new Uint8Array([2]), nonce, ciphertext, mac));
}

/**
 * @param {Uint8Array} conversationKey
 * @param {string} payloadB64
 * @returns {string}
 */
function nip44Decrypt(conversationKey, payloadB64) {
  if (payloadB64.startsWith('#')) throw new Error('Unsupported version');
  if (payloadB64.length < 132) throw new Error('Invalid payload size');
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(payloadB64)) {
    throw new Error('Not standard base64 with padding');
  }
  const payload = base64ToBytes(payloadB64);
  if (payload.length < 99) throw new Error('Invalid data size');
  if (payload[0] !== 2) throw new Error('Unsupported version');

  const nonce = payload.subarray(1, 33);
  const ciphertext = payload.subarray(33, payload.length - 32);
  const mac = payload.subarray(payload.length - 32);

  const { chachaKey, chachaNonce, hmacKey } = messageKeys(conversationKey, nonce);
  if (!equalBytes(hmac(sha256, hmacKey, concatBytes(nonce, ciphertext)), mac)) {
    throw new Error('Invalid MAC');
  }
  return utf8Decoder.decode(unpad(chacha20(chachaKey, chachaNonce, ciphertext)));
}

globalThis.DostrNoble = {
  // build.sh defines BUNDLE_VERSION, which the Dart side checks
  version: BUNDLE_VERSION,
  verifySignature,
  signEvent,
  getPublicKey,
  nip04Encrypt,
  nip04Decrypt,
  nip44ConversationKey,
  nip44Encrypt,
  nip44Decrypt,
};
