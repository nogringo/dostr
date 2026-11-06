## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - The protocol (blind signatures, v4 tokens, NUT-13 secrets and the mint
   API) lives in `ndk_cashu_protocol`, which `ndk_cashu` re-exports.
 - `receive` takes the input fees (NUT-02) out of the outputs it asks for, and
   refuses a token that does not cover them. It asked for the full amount,
   which a mint with fees rejects.
 - A melt unblinds its NUT-08 change. It failed after the payment went
   through, and the transaction ended up marked as failed.
