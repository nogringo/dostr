/// Thrown by a signer request that did not complete: the user rejected it on
/// the signer, or it was cancelled.
sealed class SignerRequestException implements Exception {
  /// the request that did not complete, when the signer tells it
  String? get requestId;
}

/// Exception thrown when a signer request is rejected by the remote signer.
///
/// This occurs when the user explicitly rejects/denies the request on the
/// remote signer (bunker, browser extension, NIP-55 signer app, etc.).
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
