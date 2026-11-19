import 'nip_05.dart';

/// Reads NIP-05 identifiers from the `.well-known/nostr.json` of their domain.
abstract interface class Nip05Repository {
  /// What the domain of [identifier] gives for it, or null when it has no such
  /// name or [identifier] is not a NIP-05 one.
  ///
  /// Throws a [FormatException] when the domain answers with something that is
  /// not a nostr.json, and another [Exception] when it cannot be reached. Once
  /// [abortTrigger] completes, with a value or an error, it throws a
  /// `RequestAbortedException` (from `package:http`).
  Future<Nip05?> fetchNip05(String identifier, {Future<void>? abortTrigger});
}
