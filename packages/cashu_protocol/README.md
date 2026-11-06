# ndk_cashu_protocol

The [Cashu](https://cashu.space) ecash protocol in pure Dart, without Nostr:
blind signatures, v4 tokens, deterministic secrets and the mint API. It holds
no state: the proofs, keysets and derivation counters are the caller's to
store.

For a full wallet (storage, pending quotes, restore, NIP-60 events), use
[`ndk_cashu`](https://pub.dev/packages/ndk_cashu), which is built on this
package and re-exports it.

> Experimental, do not use in production.

## Install

```yaml
dependencies:
  ndk_cashu_protocol: ^0.1.0
```

## Usage

Decode a token and ask its mint which proofs are still unspent:

```dart
import 'package:http/http.dart' as http;
import 'package:ndk_cashu_protocol/ndk_cashu_protocol.dart';
import 'package:ndk_http/ndk_http.dart';

final token = CashuTokenEncoder.decodedToken(encoded)!;
final mint = CashuRepoImpl(client: NdkHttp(http.Client()));

final states = await mint.checkTokenState(
  mintUrl: token.mintUrl,
  proofPubkeys: token.proofs.map((proof) => proof.Y).toList(),
);
```

Swap the token for fresh proofs derived from a seed phrase (NUT-13), so they
can be restored from the seed alone:

```dart
final seed = CashuSeed(
  userSeedPhrase: CashuUserSeedphrase(seedPhrase: seedPhrase),
);

final keysetInfo = (await mint.getKeysets(mintUrl: token.mintUrl))
    .firstWhere((keyset) => keyset.active && keyset.unit == token.unit);
final keys = await mint.getKeys(
  mintUrl: token.mintUrl,
  keysetId: keysetInfo.id,
);
final keyset = CahsuKeyset.fromResponses(
  keysetResponse: keysetInfo,
  keysResponse: keys.first,
);

final outputs = await CashuBdhke.createBlindedMsgForAmounts(
  keysetId: keyset.id,
  amounts: CashuTools.splitAmount(
    CashuTools.sumOfProofs(proofs: token.proofs),
  ),
  cashuSeed: seed,
  cashuSeedSecretGenerator: DartCashuKeyDerivation(),
  nextCounter: () => counters.next(keyset.id),
);

final signatures = await mint.swap(
  mintUrl: token.mintUrl,
  proofs: token.proofs,
  outputs: outputs.map((output) => output.blindedMessage).toList(),
);

final proofs = CashuBdhke.unblindSignatures(
  mintSignatures: signatures,
  blindedMessages: outputs,
  mintPublicKeys: keyset,
);
```

The mint returns the signatures in the order of the outputs, which `swap`
sends as given: sort the outputs by amount (NUT-03), here already done by
`splitAmount`, and unblind them in that order.

`nextCounter` hands out the derivation counter of each output, here from the
app's own `counters` store. Persist it before the swap: a counter used twice
derives an output the mint already signed. This example ignores input fees:
with a keyset whose `inputFeePPK` is not 0, the outputs must add up to the
inputs minus the fee.

## What it covers

- NUT-00: blind signatures (`CashuBdhke`, `CashuTools.hashToCurve`) and v4
  `cashuB` tokens (`CashuTokenEncoder`). V3 `cashuA` tokens are not supported.
- NUT-01, NUT-02: keys and keysets (`CahsuKeyset`).
- NUT-03, NUT-04, NUT-05: swap, mint and melt, through `CashuRepo`, whose
  `CashuRepoImpl` talks to the mint over [`ndk_http`](https://pub.dev/packages/ndk_http).
- NUT-06: mint info (`CashuMintInfo`).
- NUT-07: proof states.
- NUT-09: restore.
- NUT-13: deterministic secrets from a BIP-39 seed phrase (`CashuSeed`,
  `DartCashuKeyDerivation`), for both keyset id versions.
- NUT-20: mint quotes locked to a key that `CashuKeyDerivation.deriveQuoteKey`
  derives from the seed, and signed when minting.

A decoded v4 token holds its keyset ids and signatures in lowercase hex, as
mints do. A blinding factor that `CashuBdhke.blindMessage` generates is a
uniformly random secp256k1 scalar.

## Coming from `ndk_cashu`

These types used to live in `ndk_cashu`, which still exports them, so
`package:ndk_cashu/ndk_cashu.dart` keeps working. Besides the import:

- `CashuBdhke.createBlindedMsgForAmounts` takes a `nextCounter` callback
  instead of `cacheManager` and `mintUrl`, and throws when it cannot derive an
  output instead of leaving it out.
- `CashuBdhke.unblindSignatures` pairs signatures and outputs by position, as
  the mint returns them, and takes each amount from the signature. It accepts
  fewer signatures than outputs, for NUT-08 change.
- `CashuRepoImpl.swap` no longer sorts the outputs: sort them before.
- `kQuoteKeyDerivationCounterSlot` stays in `ndk_cashu`, as it names a storage
  slot.
- `CashuConfig` stays in `ndk_cashu`. Here, its protocol constants are
  `CashuTools.apiVersion`, `CashuTools.hashToCurveDomainSeparator` and
  `CashuRepoImpl.networkTimeout`.
