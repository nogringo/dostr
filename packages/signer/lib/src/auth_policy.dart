import 'account.dart';

/// Which identity a request may be attributed to, and from when.
sealed class AuthPolicy {
  const AuthPolicy();

  /// Stays on the anonymous connection and never sends AUTH. A relay that
  /// refuses the request without an identity simply does not serve it.
  const factory AuthPolicy.never() = AuthPolicyNever;

  /// Starts anonymous and moves to a connection bound to [account] only once a
  /// relay refused the request without an identity.
  const factory AuthPolicy.allow(Account account) = AuthPolicyAllow;

  /// Goes out on a connection bound to [account] from the start; it is never
  /// sent on the anonymous one.
  const factory AuthPolicy.require(Account account) = AuthPolicyRequire;

  /// identity this may authenticate as, null when it never authenticates
  Account? get account;
}

/// Never authenticates, see [AuthPolicy.never].
class AuthPolicyNever extends AuthPolicy {
  /// never authenticates
  const AuthPolicyNever();

  @override
  Account? get account => null;

  @override
  String toString() => 'never';
}

/// Authenticates as [account] once refused, see [AuthPolicy.allow].
class AuthPolicyAllow extends AuthPolicy {
  @override
  final Account account;

  /// authenticates as [account] once refused
  const AuthPolicyAllow(this.account);

  @override
  String toString() => 'allow:${account.pubkey}';
}

/// Authenticates as [account] from the start, see [AuthPolicy.require].
class AuthPolicyRequire extends AuthPolicy {
  @override
  final Account account;

  /// authenticates as [account] from the start
  const AuthPolicyRequire(this.account);

  @override
  String toString() => 'require:${account.pubkey}';
}
