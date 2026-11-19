## 0.1.1

 - Events with lone surrogates in their content or tags, which `JSON.stringify` and `json.encode` write as `\udxxx` escapes, must verify, and a lone surrogate swapped in for the U+FFFD that was signed must not.

## 0.1.0

 - Initial version: the accept, tamper, encoding, malformed-input and concurrency contract for `EventVerifier` implementations, and `bip340ExternalEvents`, events that other clients signed.
