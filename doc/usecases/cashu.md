---
icon: fiscal-host
title: cashu - eCash
---

[!badge variant="primary" text="high level"]

!!!danger experimental
DO NOT USE IN PRODUCTION!
!!!

!!!
no recovery option, if the user deletes the db (by resetting the app) funds are lost \
This API is `experimental` you can try it and submit your feedback.
!!!

## When to use

Cashu usecase can manage eCash (digital cash) within your application. It provides functionalities for funding, spending, and receiving eCash tokens.

## Setup

NDK exposes Cashu as `ndk.cashu`. Pass the seed phrase through `NdkConfig`:

```dart
final ndk = Ndk(
  NdkConfig(
    cache: cacheManager,
    eventVerifier: Bip340EventVerifier(),
    // generate one with CashuSeed.generateSeedPhrase() and store it securely
    cashuUserSeedphrase: CashuUserSeedphrase(seedPhrase: seedPhrase),
  ),
);
```

Proofs, keysets and mint infos go to the NDK cache when it implements `CashuStorage` (`ndk_objectbox`, `ndk_drift`, `ndk_sembast` and `ndk_sqlite3` do), and to memory otherwise. Pending quotes go to `NdkConfig.walletsRepo`, see [wallets](wallets.md). `ndk.cashu` is built on first use: Cashu resumes the pending quotes from then on.

`Cashu` lives in the `ndk_cashu` package, which `ndk` depends on and re-exports. It does not depend on `ndk`: build `Cashu` with a `CashuRepo`, a `WalletsRepo`, a `CashuStorage` and a `CashuKeyDerivation`, see its [README](https://pub.dev/packages/ndk_cashu). For the protocol alone (blind signatures, tokens, NUT-13 secrets and the mint API) without a wallet or Nostr, use `ndk_cashu_protocol`, which `ndk_cashu` re-exports.

## Examples

## add mint url

!!!
When you receive tokens or initiate funding, the mint gets added automatically
!!!

```dart
/// adds to known mints
ndk.cashu.addMintToKnownMints(mintUrl: "https://example.mint");

/// stream [Set<CashuMintInfo>] of known mints
ndk.cashu.knownMints;

/// get [CashuMintInfo] without adding it to known mints
ndk.cashu.getMintInfoNetwork(mintUrl: "https://example.mint");

```

## fund (mint)

```dart
    final initTransaction = await ndk.cashu.initiateFund(
        mintUrl: "https://example.mint",
        amount: "100",
        unit: "sat",
        method: "bolt11",
        memo: "funding example",
      );

    /// pay the request (usually lnbc1...)
    print(initTransaction.qoute!.request);

    /// retrieve funds and listen for status
    final resultStream =
          ndk.cashu.retrieveFunds(draftTransaction: initTransaction);

      await for (final result in resultStream) {
        if (result.state == WalletTransactionState.completed) {
          /// transcation done
          print(result.completionMsg);
        } else if (result.state == WalletTransactionState.pending) {
          /// pending
        }
         else if (result.state == WalletTransactionState.failed) {
          /// transcation done
          print(result.completionMsg);
        }
      }

```

## redeem (melt)

```dart

    final draftTransaction = await ndk.cashu.initiateRedeem(
        mintUrl: "https://example.mint",
        request: "lnbc1...",
        unit: "sat"
        method: "bolt11",
    );

    /// check if everything is ok (fees etc)
    print(draftTransaction.qouteMelt.feeReserve);

    /// redeem funds and listen for status
    final resultStream =
        ndk.cashu.redeem(draftTransaction: draftTransaction);

    await for (final result in resultStream) {
    if (result.state == WalletTransactionState.completed) {
        /// transcation done
        print(result.completionMsg);
    } else if (result.state == WalletTransactionState.pending) {
        /// pending
    }
    else if (result.state == WalletTransactionState.failed) {
        /// transcation done
        print(result.completionMsg);
    }
    }


```

## spend

```dart
    final spendResult = await ndk.cashu.initiateSpend(
        mintUrl: "https://example.mint",
        amount: 5,
        unit: "sat",
        memo: "spending example",
    );

    print("token to spend: ${spendResult.token.toV4TokenString()}");
    print("transaction id: ${spendResult.transaction}");

    /// listen to pending transactions List<CashuWalletTransaction>
    await for (final transaction in ndk.cashu.pendingTransactions) {
      print("latest transaction: $transaction");
    }

    /// listen to recent transactinos List<CashuWalletTransaction>
    await for (final transaction in ndk.cashu.latestTransactions) {
      print("latest transaction: $transaction");
    }


```

## receive

```dart

      final rcvResultStream = ndk.cashu.receive(tokenString);

      await for (final rcvResult in rcvResultStream) {
        if (rcvResult.state == WalletTransactionState.pending) {
            /// pending
        } else if (rcvResult.state ==
            WalletTransactionState.completed) {
            /// completed
        } else if (rcvResult.state ==
            WalletTransactionState.failed) {
            /// failed
            print(result.completionMsg);
        }
      }

```

!!!
All transactions are also available via `pendingTransactions` and `latestTransactions` streams.\
As well as in the `Wallets` usecase
!!!

## check balance

```dart
    /// balances for all mints [List<CashuMintBalance>]
    final balances = await ndk.cashu.getBalances();
    print(balances);

    /// balance for one mint and unit [int]
    final singleBalance = await getBalanceMintUnit(
      mintUrl: "https://example.mint",
      unit: "sat",
    );

    /// stream of [List<CashuMintBalance>]
    ndk.cashu.balances;

```

!!!
balances are also available via `Wallets` usecase
!!!


