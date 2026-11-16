import 'nostr_signer.dart';

/// Which identity a request may be attributed to, and from when.
sealed class AuthPolicy {
  const AuthPolicy();

  /// Never authenticates. A relay or server that refuses the request without
  /// an identity does not serve it.
  const factory AuthPolicy.never() = AuthPolicyNever;

  /// Starts anonymous, and authenticates as [signer] only once a relay or
  /// server refused the request without an identity.
  const factory AuthPolicy.allow(NostrSigner signer) = AuthPolicyAllow;

  /// Authenticates as [signer] from the start, and never sends the request
  /// anonymously.
  const factory AuthPolicy.require(NostrSigner signer) = AuthPolicyRequire;

  /// identity this may authenticate as, null when it never authenticates
  NostrSigner? get signer;
}

/// Never authenticates, see [AuthPolicy.never].
class AuthPolicyNever extends AuthPolicy {
  /// never authenticates
  const AuthPolicyNever();

  @override
  NostrSigner? get signer => null;

  @override
  String toString() => 'never';
}

/// Authenticates as [signer] once refused, see [AuthPolicy.allow].
class AuthPolicyAllow extends AuthPolicy {
  @override
  final NostrSigner signer;

  /// authenticates as [signer] once refused
  const AuthPolicyAllow(this.signer);

  @override
  String toString() => 'allow:${signer.publicKey}';
}

/// Authenticates as [signer] from the start, see [AuthPolicy.require].
class AuthPolicyRequire extends AuthPolicy {
  @override
  final NostrSigner signer;

  /// authenticates as [signer] from the start
  const AuthPolicyRequire(this.signer);

  @override
  String toString() => 'require:${signer.publicKey}';
}
