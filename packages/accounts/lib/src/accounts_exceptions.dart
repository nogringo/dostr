/// Thrown when an account is added for a pubkey that is already an account.
class AccountExistsException implements Exception {
  final String pubkey;

  const AccountExistsException(this.pubkey);

  @override
  String toString() => 'AccountExistsException: $pubkey is already an account';
}

/// Thrown when switching to a pubkey that is not an account.
class UnknownAccountException implements Exception {
  final String pubkey;

  const UnknownAccountException(this.pubkey);

  @override
  String toString() => 'UnknownAccountException: $pubkey is not an account';
}

/// Thrown by `Accounts.sign` when nobody is logged in, or when the logged
/// account is read-only.
class AccountCannotSignException implements Exception {
  /// the logged account, null when nobody is logged in
  final String? pubkey;

  const AccountCannotSignException([this.pubkey]);

  @override
  String toString() => pubkey == null
      ? 'AccountCannotSignException: nobody is logged in'
      : 'AccountCannotSignException: $pubkey is read-only';
}
