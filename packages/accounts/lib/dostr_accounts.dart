/// Nostr accounts: log in, switch between accounts and sign as the
/// logged one.
///
/// ```dart
/// final accounts = Accounts(const Bip340EventSignerFactory());
/// accounts.loginPrivateKey(pubkey: pubkey, privkey: privkey);
/// final signed = await accounts.sign(event);
/// ```
library;

export 'src/accounts.dart';
