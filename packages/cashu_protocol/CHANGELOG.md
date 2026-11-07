## 0.1.0

 - Initial release, moved out of the `ndk_cashu` package: blind signatures,
   v4 tokens, NUT-13 secrets and the mint API, without Nostr.
 - `CashuBdhke.createBlindedMsgForAmounts` takes its derivation counters from
   a `nextCounter` callback, and throws instead of leaving out an output it
   cannot derive.
 - A decoded v4 token holds lowercase hex keyset ids and signatures, as mints
   do. They came out in uppercase, so the keyset ids matched no keyset.
 - `CashuBdhke.blindMessage` generates a uniformly random blinding factor. It
   was a number below one million, which a mint can guess to link a proof to
   the blinded message it signed.
 - `CashuBdhke.unblindSignatures` pairs each signature with the output at its
   position and takes the amount from the signature. It sorted both lists by
   amount, which mixed up outputs of the same amount past 32 of them, and it
   could not unblind NUT-08 change: fewer signatures than blank outputs, with
   amounts the mint imprinted.
 - `CashuRepoImpl.swap` sends the outputs in the order it gets them instead of
   sorting the caller's list in place.
 - `CashuTokenUrEncoder` (NUT-16 animated QR codes) moved here from the `ur`
   package, and so did the Uniform Resources encoding of that package, a copy
   of dart-bc-ur under the MIT license (`lib/src/ur/LICENSE`). There is no
   `ur` package to depend on anymore: `URDecoder` and `UREncoder` are exported
   from here, the rest is internal.
 - The UR of a token holds the serialized `cashuB` token as a CBOR byte
   string, as cashu.me does. It held the token's CBOR map, so neither wallet
   could read the other's QR codes.
