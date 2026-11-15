import 'dart:async';
import 'dart:collection';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import 'accounts_exceptions.dart';

/// The accounts of an app, and the one logged in among them.
///
/// Each account owns its signer: removing the account, or disposing of
/// [Accounts], disposes of the signer.
class Accounts implements AuthAccounts {
  /// Builds the signers of [loginPrivateKey] and [loginPublicKey].
  final LocalEventSignerFactory eventSignerFactory;

  final Map<String, Account> _accounts = {};
  String? _loggedPubkey;

  final _stateController = BehaviorSubject<Account?>.seeded(null);

  final _accountsController = BehaviorSubject<Map<String, Account>>.seeded(
    UnmodifiableMapView(<String, Account>{}),
  );

  Accounts(this.eventSignerFactory);

  /// The accounts by pubkey: an unmodifiable snapshot, the last one
  /// [accountsStream] emitted.
  @override
  Map<String, Account> get accounts => _accountsController.value;

  /// The logged account on subscription, then each time it changes. Null
  /// when nobody is logged in.
  Stream<Account?> get authStateChanges => _stateController.stream;

  /// The accounts by pubkey on subscription, then a new snapshot each time
  /// one is added or removed.
  Stream<Map<String, Account>> get accountsStream => _accountsController.stream;

  /// Adds an account that signs with [privkey], whose pubkey it derives, and
  /// logs it in.
  void loginPrivateKey({required String privkey}) {
    final pubkey = eventSignerFactory.derivePublicKey(privkey);
    _loginLocal(AccountType.privateKey, pubkey: pubkey, privkey: privkey);
  }

  /// Adds a read-only account and logs it in.
  void loginPublicKey({required String pubkey}) =>
      _loginLocal(AccountType.publicKey, pubkey: pubkey);

  /// Adds an account that signs with [signer] and logs it in. A NIP-46
  /// signer must know its pubkey first, from `getPublicKeyAsync`.
  ///
  /// [signer] belongs to the account from then on, unless this throws.
  void loginExternalSigner({required EventSigner signer}) =>
      _login(AccountType.externalSigner, signer);

  bool hasAccount(String pubkey) => _accounts.containsKey(pubkey);

  /// Removes the logged account. Nobody is logged in afterwards, even when
  /// other accounts remain.
  Future<void> logout() async {
    final pubkey = _loggedPubkey;
    if (pubkey != null) await removeAccount(pubkey: pubkey);
  }

  void switchAccount({required String pubkey}) {
    if (!hasAccount(pubkey)) throw UnknownAccountException(pubkey);
    _loggedPubkey = pubkey;
    _notifyAuthStateChange();
  }

  /// Adds an account for the pubkey of [signer], without logging it in.
  ///
  /// Throws an [AccountExistsException] when that pubkey is already an
  /// account. Otherwise [signer] belongs to the account from then on.
  Account addAccount({required AccountType type, required EventSigner signer}) {
    final pubkey = signer.getPublicKey();
    _checkNew(pubkey);
    final account = Account(type: type, pubkey: pubkey, signer: signer);
    _accounts[pubkey] = account;
    _notifyAccountsChange();
    return account;
  }

  /// Removes the account of [pubkey], if any, logs it out if it was logged
  /// in, and completes once its signer is disposed of.
  Future<void> removeAccount({required String pubkey}) async {
    final account = _accounts.remove(pubkey);
    if (account == null) return;
    _notifyAccountsChange();
    if (_loggedPubkey == pubkey) {
      _loggedPubkey = null;
      _notifyAuthStateChange();
    }
    await account.dispose();
  }

  /// Signs [event] with the signer of the logged account.
  ///
  /// Throws an [AccountCannotSignException] when nobody is logged in or the
  /// logged account is read-only, and an [ArgumentError] when [event] is not
  /// the logged account's.
  Future<Nip01Event> sign(Nip01Event event) async {
    final account = getLoggedAccount();
    if (account == null || !account.signer.canSign()) {
      throw AccountCannotSignException(account?.pubkey);
    }
    if (event.pubKey != account.pubkey) {
      throw ArgumentError.value(
        event.pubKey,
        'event.pubKey',
        'is not the logged account ${account.pubkey}',
      );
    }
    return account.signer.sign(event);
  }

  @override
  Account? getLoggedAccount() => _accounts[_loggedPubkey];

  /// Whether the logged account can sign events.
  bool get canSign => getLoggedAccount()?.signer.canSign() ?? false;

  bool get cannotSign => !canSign;

  bool get isLoggedIn => _loggedPubkey != null;

  bool get isNotLoggedIn => !isLoggedIn;

  /// The pubkey of the logged account, null when nobody is logged in.
  String? getPublicKey() => _loggedPubkey;

  void _loginLocal(
    AccountType type, {
    required String pubkey,
    String? privkey,
  }) {
    _checkNew(pubkey);
    _login(
      type,
      eventSignerFactory.create(privateKey: privkey, publicKey: pubkey),
    );
  }

  void _login(AccountType type, EventSigner signer) {
    final account = addAccount(type: type, signer: signer);
    switchAccount(pubkey: account.pubkey);
  }

  void _checkNew(String pubkey) {
    if (hasAccount(pubkey)) throw AccountExistsException(pubkey);
  }

  void _notifyAuthStateChange() {
    final account = getLoggedAccount();
    if (account != _stateController.value) _stateController.add(account);
  }

  void _notifyAccountsChange() =>
      _accountsController.add(UnmodifiableMapView(Map.of(_accounts)));

  /// Disposes of every account's signer and closes the streams.
  Future<void> dispose() async {
    await Future.wait(_accounts.values.map((account) => account.dispose()));
    await _stateController.close();
    await _accountsController.close();
  }
}
