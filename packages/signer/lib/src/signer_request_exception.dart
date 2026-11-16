/// Thrown by a signer request that did not complete: the signer turned it
/// down, it was cancelled, or no valid result came back.
sealed class SignerRequestException implements Exception {
  /// the request that did not complete, when the signer tells it
  String? get requestId;
}

/// Thrown when the signer turns a request down: the user refused it on the
/// signer (bunker, browser extension, NIP-55 signer app, etc.), or the signer
/// answered with an error.
class SignerRequestRejectedException extends SignerRequestException {
  @override
  final String? requestId;

  /// The original error message from the remote signer
  final String? originalMessage;

  SignerRequestRejectedException({this.requestId, this.originalMessage});

  @override
  String toString() {
    final parts = <String>['SignerRequestRejectedException'];
    if (requestId != null) {
      parts.add('Request $requestId was rejected');
    }
    if (originalMessage != null) {
      parts.add('($originalMessage)');
    }
    return parts.join(': ');
  }
}

/// Exception thrown when a signer request is cancelled by the user.
///
/// This is a "soft cancel" - the request is removed from the pending list
/// and the caller receives this exception, but the remote signer (bunker,
/// browser extension, etc.) may still have the request pending.
class SignerRequestCancelledException extends SignerRequestException {
  @override
  final String requestId;

  SignerRequestCancelledException(this.requestId);

  @override
  String toString() =>
      'SignerRequestCancelledException: Request $requestId was cancelled';
}

/// Thrown when a request got no valid result: the signer could not carry it
/// out, such as a ciphertext that does not decrypt, or answered with
/// something unusable, such as an event signed by another pubkey.
class SignerRequestFailedException extends SignerRequestException {
  @override
  final String? requestId;

  final String message;

  /// the error behind [message], if any
  final Object? cause;

  SignerRequestFailedException(this.message, {this.requestId, this.cause});

  @override
  String toString() {
    final parts = <String>['SignerRequestFailedException'];
    if (requestId != null) {
      parts.add('Request $requestId failed');
    }
    parts.add(cause == null ? message : '$message ($cause)');
    return parts.join(': ');
  }
}
