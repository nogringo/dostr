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

Cashu lives in the `ndk_cashu` package.

```yaml
dependencies:
  ndk_cashu: ^0.1.0
  ndk_wallets: ^0.1.0 # WalletTransactionState and wallets repositories
```

```dart
import 'package:ndk_cashu/ndk_cashu.dart';
import 'package:ndk_wallets/ndk_wallets.dart';

final cashu = Cashu(
  ndk,
  // generate one with CashuSeed.generateSeedPhrase() and store it securely
  cashuUserSeedphrase: CashuUserSeedphrase(seedPhrase: seedPhrase),
);
```

Proofs, keysets and mint infos go to a `CashuStorage`. Without `storage`, the NDK cache is used when it implements `CashuStorage` (`ndk_objectbox`, `ndk_drift`, `ndk_sembast` and `ndk_sqlite3` do), an in memory `MemCashuStorage` otherwise. Pending quotes go to the `walletsRepo`, see [wallets](wallets.md).

## Examples

## add mint url

!!!
When you receive tokens or initiate funding, the mint gets added automatically
!!!

```dart
/// adds to known mints
cashu.addMintToKnownMints(mintUrl: "https://example.mint");

/// stream [Set<CashuMintInfo>] of known mints
cashu.knownMints;

/// get [CashuMintInfo] without adding it to known mints
cashu.getMintInfoNetwork(mintUrl: "https://example.mint");

```

## fund (mint)

```dart
    final initTransaction = await cashu.initiateFund(
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
          cashu.retrieveFunds(draftTransaction: initTransaction);

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

    final draftTransaction = await cashu.initiateRedeem(
        mintUrl: "https://example.mint",
        request: "lnbc1...",
        unit: "sat"
        method: "bolt11",
    );

    /// check if everything is ok (fees etc)
    print(draftTransaction.qouteMelt.feeReserve);

    /// redeem funds and listen for status
    final resultStream =
        cashu.redeem(draftTransaction: draftTransaction);

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
    final spendResult = await cashu.initiateSpend(
        mintUrl: "https://example.mint",
        amount: 5,
        unit: "sat",
        memo: "spending example",
    );

    print("token to spend: ${spendResult.token.toV4TokenString()}");
    print("transaction id: ${spendResult.transaction}");

    /// listen to pending transactions List<CashuWalletTransaction>
    await for (final transaction in cashu.pendingTransactions) {
      print("latest transaction: $transaction");
    }

    /// listen to recent transactinos List<CashuWalletTransaction>
    await for (final transaction in cashu.latestTransactions) {
      print("latest transaction: $transaction");
    }


```

## receive

```dart

      final rcvResultStream = cashu.receive(tokenString);

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
    final balances = await cashu.getBalances();
    print(balances);

    /// balance for one mint and unit [int]
    final singleBalance = await getBalanceMintUnit(
      mintUrl: "https://example.mint",
      unit: "sat",
    );

    /// stream of [List<CashuMintBalance>]
    cashu.balances;

```

!!!
balances are also available via `Wallets` usecase
!!!


