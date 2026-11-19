import 'nip_05.dart';

/// What [Nip05Resolver.resolve] learned about an identifier: [Nip05Found],
/// [Nip05NotFound], or a [Nip05ResolveError] when it could not tell.
sealed class Nip05ResolveResult {
  const Nip05ResolveResult();
}

/// What [Nip05Resolver.check] learned about an identifier and a pubkey:
/// [Nip05Verified], [Nip05Mismatch], [Nip05NotFound], or a [Nip05ResolveError]
/// when it could not tell.
sealed class Nip05CheckResult {
  const Nip05CheckResult();
}

/// The domain gives a pubkey for the identifier, read from the cache or the
/// network.
class Nip05Found extends Nip05ResolveResult {
  final Nip05 data;

  /// when the domain gave [data], in UTC
  final DateTime fetchedAt;

  const Nip05Found(this.data, {required this.fetchedAt});

  @override
  bool operator ==(Object other) =>
      other is Nip05Found && other.data == data && other.fetchedAt == fetchedAt;

  @override
  int get hashCode => Object.hash(data, fetchedAt);

  @override
  String toString() => 'Nip05Found($data, fetchedAt: $fetchedAt)';
}

/// The identifier points to the pubkey it was checked against.
class Nip05Verified extends Nip05CheckResult {
  final Nip05 data;

  /// when the domain gave [data], in UTC
  final DateTime fetchedAt;

  const Nip05Verified(this.data, {required this.fetchedAt});

  @override
  bool operator ==(Object other) =>
      other is Nip05Verified &&
      other.data == data &&
      other.fetchedAt == fetchedAt;

  @override
  int get hashCode => Object.hash(data, fetchedAt);

  @override
  String toString() => 'Nip05Verified($data, fetchedAt: $fetchedAt)';
}

/// The identifier points to another pubkey, [data]'s.
class Nip05Mismatch extends Nip05CheckResult {
  final Nip05 data;

  /// when the domain gave [data], in UTC
  final DateTime fetchedAt;

  const Nip05Mismatch(this.data, {required this.fetchedAt});

  @override
  bool operator ==(Object other) =>
      other is Nip05Mismatch &&
      other.data == data &&
      other.fetchedAt == fetchedAt;

  @override
  int get hashCode => Object.hash(data, fetchedAt);

  @override
  String toString() => 'Nip05Mismatch($data, fetchedAt: $fetchedAt)';
}

/// The identifier does not exist: the `.well-known/nostr.json` of its domain
/// is missing or has no entry under its name, or it is not a NIP-05
/// identifier, in which case no request was sent.
class Nip05NotFound extends Nip05ResolveResult implements Nip05CheckResult {
  const Nip05NotFound();

  @override
  bool operator ==(Object other) => other is Nip05NotFound;

  @override
  int get hashCode => (Nip05NotFound).hashCode;

  @override
  String toString() => 'Nip05NotFound()';
}

/// Whether the identifier exists could not be determined.
///
/// Switch on [Nip05ResolveNetworkError] and [Nip05ResolveInvalidResponse] to
/// tell a transient transport failure from a server giving a body that is not
/// a nostr.json.
sealed class Nip05ResolveError extends Nip05ResolveResult
    implements Nip05CheckResult {
  /// The underlying error that caused the resolution to fail.
  Exception get cause;
  const Nip05ResolveError();
}

/// The `.well-known/nostr.json` file could not be fetched.
///
/// Covers DNS failures, timeouts, refused connections and HTTP error statuses
/// other than 404. Often transient, so worth retrying later.
class Nip05ResolveNetworkError extends Nip05ResolveError implements Exception {
  @override
  final Exception cause;
  const Nip05ResolveNetworkError(this.cause);

  @override
  String toString() =>
      'Nip05ResolveNetworkError: failed to fetch nostr.json: $cause';
}

/// The file was fetched but is not a valid nostr.json: the server redirects,
/// which NIP-05 forbids, its body is larger than the repository reads, is not a
/// JSON object or has a `names` that is not one, or the entry for the name is
/// not a hex pubkey, such as an npub. The server is misconfigured.
class Nip05ResolveInvalidResponse extends Nip05ResolveError
    implements Exception {
  @override
  final Exception cause;
  const Nip05ResolveInvalidResponse(this.cause);

  @override
  String toString() =>
      'Nip05ResolveInvalidResponse: invalid nostr.json response: $cause';
}
