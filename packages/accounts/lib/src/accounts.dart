import 'dart:async';
import 'dart:collection';

import 'package:rxdart/rxdart.dart';

import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_signer/ndk_signer.dart';

/// A usecase that handles accounts
class Accounts implements AuthAccounts {
  /// Factory for creating EventSigner instances
  final LocalEventSignerFactory eventSignerFactory;

  final Map<String, Account> _accounts = {};
  String? _loggedPubkey;

  /// Stream controller for authentication state changes
  final _stateController = BehaviorSubject<Account?>();

  /// Stream controller for the known accounts
  final _accountsController = BehaviorSubject<Map<String, Account>>.seeded(
    UnmodifiableMapView(<String, Account>{}),
  );

  /// Creates a new Accounts instance with the given event signer factory
  Accounts(this.eventSignerFactory);

  /// pubKey -> Account, read-only view, listen to [accountsStream] for changes
  /// Same instance until the accounts actually change, so every mutation of
  /// [_accounts] has to go through [_notifyAccountsChange]
  @override
  Map<String, Account> get accounts => _accountsController.value;

  /// Stream of authentication state changes
  /// Emits the current Account when logged in, or null when logged out
  Stream<Account?> get authStateChanges => _stateController.stream;

  /// Stream of the known accounts, pubKey -> Account
  /// Emits the current accounts on subscription, then an unmodifiable snapshot
  /// every time an account is added, replaced or removed
  Stream<Map<String, Account>> get accountsStream => _accountsController.stream;

  /// adds a new Account and sets the logged pubkey
  void loginPrivateKey({required String pubkey, required String privkey}) {
    if (_accounts.containsKey(pubkey)) {
      throw Exception("Cannot login, pubkey already logged in");
    }
    addAccount(
      pubkey: pubkey,
      type: AccountType.privateKey,
      signer: eventSignerFactory.create(privateKey: privkey, publicKey: pubkey),
    );
    _loggedPubkey = pubkey;
    _notifyAuthStateChange();
  }

  /// do we have the account for this pubkey?
  bool hasAccount(String pubkey) {
    return _accounts.containsKey(pubkey);
  }

  /// adds a new read-only Account and sets the logged pubkey
  void loginPublicKey({required String pubkey}) {
    if (_accounts.containsKey(pubkey)) {
      throw Exception("Cannot login, pubkey already logged in");
    }
    addAccount(
      pubkey: pubkey,
      type: AccountType.publicKey,
      signer: eventSignerFactory.create(privateKey: null, publicKey: pubkey),
    );
    _loggedPubkey = pubkey;
    _notifyAuthStateChange();
  }

  /// adds a new read-only Account and sets the logged pubkey
  void loginExternalSigner({required EventSigner signer}) {
    final pubkey = signer.getPublicKey();
    if (_accounts.containsKey(pubkey)) {
      throw Exception("Cannot login, pubkey already logged in");
    }
    addAccount(
      pubkey: pubkey,
      type: AccountType.externalSigner,
      signer: signer,
    );
    _loggedPubkey = pubkey;
    _notifyAuthStateChange();
  }

  void logout() {
    if (_loggedPubkey != null) {
      _accounts.remove(_loggedPubkey);
      _loggedPubkey = null;
      _notifyAccountsChange();
      _notifyAuthStateChange();
    }
  }

  /// set logged account
  void switchAccount({required String pubkey}) {
    if (pubkey.isNotEmpty && _accounts.containsKey(pubkey)) {
      _loggedPubkey = pubkey;
      _notifyAuthStateChange();
    } else {
      throw Exception("unknown account for pubkey");
    }
  }

  /// adds an Account
  void addAccount({
    required String pubkey,
    required AccountType type,
    required EventSigner signer,
  }) {
    _accounts[pubkey] = Account(type: type, pubkey: pubkey, signer: signer);
    _notifyAccountsChange();
  }

  /// removes an Account
  void removeAccount({required String pubkey}) {
    final wasLoggedIn = _loggedPubkey == pubkey;
    if (wasLoggedIn) {
      _loggedPubkey = null;
    }
    _accounts.remove(pubkey);
    _notifyAccountsChange();
    if (wasLoggedIn) {
      _notifyAuthStateChange();
    }
  }

  /// low-level method, should not be used directly in most cases, use broadcast instead which calls signing on the signer
  Future<Nip01Event> sign(Nip01Event event) async {
    Account? account = getLoggedAccount();
    if (account != null && account.signer.canSign()) {
      return account.signer.sign(event);
    }
    throw Exception("Cannot sign");
  }

  /// returns currently logged in account
  @override
  Account? getLoggedAccount() {
    return _loggedPubkey != null ? _accounts[_loggedPubkey] : null;
  }

  /// is currently logged in account able to sign events
  bool get canSign {
    Account? account = getLoggedAccount();
    return account != null && account.signer.canSign();
  }

  bool get cannotSign => !canSign;

  /// is logged in
  bool get isLoggedIn => getLoggedAccount() != null;

  /// is not logged in
  bool get isNotLoggedIn => !isLoggedIn;

  /// returns public key of currently logged in account or null if not logged in
  String? getPublicKey() {
    return getLoggedAccount()?.pubkey;
  }

  /// Notifies listeners of auth state changes
  void _notifyAuthStateChange() {
    _stateController.add(getLoggedAccount());
  }

  /// Notifies listeners of accounts changes, no-op if nothing actually changed
  void _notifyAccountsChange() {
    final previous = _accountsController.value;
    final unchanged =
        previous.length == _accounts.length &&
        _accounts.entries.every((entry) => previous[entry.key] == entry.value);
    if (unchanged) return;
    _accountsController.add(UnmodifiableMapView(Map.of(_accounts)));
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _stateController.close();
    await _accountsController.close();
  }
}
