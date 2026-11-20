import 'ncryptsec.dart';

/// A failure of [Ncryptsec.decrypt].
sealed class Nip49Exception implements Exception {
  const Nip49Exception();
}

/// Thrown by [Ncryptsec.decrypt] when the password is wrong, or when the
/// ncryptsec was altered after it was made.
final class Nip49WrongPasswordException extends Nip49Exception {
  /// An exception for a wrong password or an altered ncryptsec.
  const Nip49WrongPasswordException();

  @override
  String toString() => 'Nip49WrongPasswordException: wrong password';
}

/// Thrown by [Ncryptsec.decrypt], before any scrypt work, when the [logN] of
/// the ncryptsec is above the [maxLogN] it was given.
final class Nip49CostTooHighException extends Nip49Exception {
  /// The scrypt cost of the ncryptsec.
  final int logN;

  /// The highest cost [Ncryptsec.decrypt] was allowed to run.
  final int maxLogN;

  /// An exception for a [logN] above [maxLogN].
  const Nip49CostTooHighException(this.logN, this.maxLogN);

  @override
  String toString() =>
      'Nip49CostTooHighException: logN $logN is above $maxLogN';
}
