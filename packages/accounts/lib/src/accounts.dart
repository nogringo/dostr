import 'dart:async';
import 'dart:collection';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:rxdart/rxdart.dart';

import 'accounts_exceptions.dart';

/// The accounts of an app, each one the [NostrSigner] of its pubkey, and the
/// one logged in among them.
///
/// Each account belongs to [Accounts]: removing it, or disposing of
/// [Accounts], disposes of its signer.
class Accounts implements AuthAccounts {
  /// Builds the signers of [loginPrivateKey] and [loginPublicKey].
  final LocalSignerFactory signerFactory;

  final Map<String, NostrSigner> _accounts = {};
  String? _loggedPubkey;

  final _stateController = BehaviorSubject<NostrSigner?>.seeded(null);

  final _accountsController = BehaviorSubject<Map<String, NostrSigner>>.seeded(
    UnmodifiableMapView(<String, NostrSigner>{}),
  );

  Accounts(this.signerFactory);

  /// The accounts by pubkey: an unmodifiable snapshot, the last one
  /// [accountsStream] emitted.
  Map<String, NostrSigner> get accounts => _accountsController.value;

  /// The logged account on subscription, then each time it changes. Null
  /// when nobody is logged in.
  Stream<NostrSigner?> get authStateChanges => _stateController.stream;

  /// The accounts by pubkey on subscription, then a new snapshot each time
  /// one is added or removed.
  Stream<Map<String, NostrSigner>> get accountsStream =>
      _accountsController.stream;

  /// Adds an account that signs with [privkey], whose pubkey it derives, and
  /// logs it in.
  void loginPrivateKey({required String privkey}) =>
      _loginLocal(signerFactory.create(privkey));

  /// Adds a read-only account and logs it in.
  void loginPublicKey({required String pubkey}) =>
      _loginLocal(signerFactory.readOnly(pubkey));

  /// Adds an account that signs with [signer] and logs it in.
  ///
  /// [signer] belongs to [Accounts] from then on, unless this throws.
  void loginExternalSigner({required NostrSigner signer}) => _login(signer);

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
  /// account. Otherwise [signer] belongs to [Accounts] from then on.
  void addAccount({required NostrSigner signer}) {
    final pubkey = signer.publicKey;
    _checkNew(pubkey);
    _accounts[pubkey] = signer;
    _notifyAccountsChange();
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
    if (account == null || !account.canSign) {
      throw AccountCannotSignException(account?.publicKey);
    }
    if (event.pubkey != account.publicKey) {
      throw ArgumentError.value(
        event.pubkey,
        'event.pubkey',
        'is not the logged account ${account.publicKey}',
      );
    }
    return account.sign(event);
  }

  @override
  NostrSigner? getLoggedAccount() => _accounts[_loggedPubkey];

  @override
  NostrSigner? getAccount(String pubkey) => _accounts[pubkey];

  /// Whether the logged account can sign events.
  bool get canSign => getLoggedAccount()?.canSign ?? false;

  bool get cannotSign => !canSign;

  bool get isLoggedIn => _loggedPubkey != null;

  bool get isNotLoggedIn => !isLoggedIn;

  /// The pubkey of the logged account, null when nobody is logged in.
  String? get loggedPubkey => _loggedPubkey;

  /// Logs in [signer], which this made, and disposes of it if that throws.
  void _loginLocal(NostrSigner signer) {
    try {
      _login(signer);
    } catch (_) {
      unawaited(signer.dispose());
      rethrow;
    }
  }

  void _login(NostrSigner signer) {
    addAccount(signer: signer);
    switchAccount(pubkey: signer.publicKey);
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
