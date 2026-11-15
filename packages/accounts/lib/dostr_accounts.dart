/// Nostr accounts: log in, switch between accounts and sign as the
/// logged one.
///
/// ```dart
/// final accounts = Accounts(const Bip340SignerFactory());
/// accounts.loginPrivateKey(privkey: privkey);
/// final signed = await accounts.sign(event);
/// ```
library;

export 'src/accounts.dart';
export 'src/accounts_exceptions.dart';
