import 'ncryptsec.dart';

/// A failure of [Ncryptsec.decrypt].
sealed class Nip49Exception implements Exception {
  const Nip49Exception();
}

/// Thrown by [Ncryptsec.decrypt] when the password is wrong, or when the
/// ncryptsec was altered after it was made.
final class Nip49WrongPasswordException extends Nip49Exception {
  const Nip49WrongPasswordException();

  @override
  String toString() => 'Nip49WrongPasswordException: wrong password';
}

/// Thrown by [Ncryptsec.decrypt], before any scrypt work, when the [logN] of
/// the ncryptsec is above the [maxLogN] it was given.
final class Nip49CostTooHighException extends Nip49Exception {
  final int logN;
  final int maxLogN;

  const Nip49CostTooHighException(this.logN, this.maxLogN);

  @override
  String toString() =>
      'Nip49CostTooHighException: logN $logN is above $maxLogN';
}
